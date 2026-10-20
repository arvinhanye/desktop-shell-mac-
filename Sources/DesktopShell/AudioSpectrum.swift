import Foundation
import CoreAudio

/// Decisions only. The worker serializes effects; a short lock protects this
/// mailbox so a pause can supersede setup even while the permission dialog waits.
struct AudioCaptureState {
    enum StopReason: String { case paused, noPlayback, deviceChanged, quit, error }
    enum Action: Equatable { case start(Int), stop(StopReason) }
    private enum Phase { case idle, starting, running(Int) }
    private var phase: Phase = .idle
    private var paused = true
    private var othersPlaying = false
    private(set) var noPlaybackDeadline: TimeInterval?
    private var requested = false
    private var reason: StopReason = .paused
    private(set) var generation = 0
    private(set) var terminated = false

    mutating func setPaused(_ value: Bool) {
        guard !terminated else { return }
        if paused != value { generation += 1 }
        paused = value
        requested = !value && othersPlaying
        if value {
            reason = .paused
            noPlaybackDeadline = nil
        }
    }

    mutating func setPlayback(_ playing: Bool, now: TimeInterval) {
        guard !terminated, playing != othersPlaying else { return }
        othersPlaying = playing
        requested = playing && !paused
        if playing {
            noPlaybackDeadline = nil
        } else if !paused {
            switch phase {
            case .starting, .running: noPlaybackDeadline = now + 3
            case .idle: break // A grace period keeps an existing capture, never starts one.
            }
        }
    }

    mutating func expireNoPlayback(now: TimeInterval) {
        guard let deadline = noPlaybackDeadline, now >= deadline else { return }
        noPlaybackDeadline = nil
        requested = false
        generation += 1
        reason = .noPlayback
    }

    mutating func deviceChanged() {
        guard !terminated, !paused, othersPlaying || noPlaybackDeadline != nil else { return }
        generation += 1
        requested = othersPlaying
        reason = .deviceChanged
    }

    mutating func stop() {
        guard !terminated else { return }
        terminated = true
        paused = true
        requested = false
        noPlaybackDeadline = nil
        generation += 1
        reason = .quit
    }

    mutating func nextAction() -> Action? {
        switch phase {
        case .starting: return nil
        case .running(let active):
            if paused || terminated || active != generation || (!othersPlaying && noPlaybackDeadline == nil) {
                phase = .idle
                noPlaybackDeadline = nil
                return .stop(reason)
            }
            requested = false
            return nil
        case .idle:
            guard !paused, !terminated, othersPlaying, requested else { return nil }
            requested = false
            phase = .starting
            return .start(generation)
        }
    }

    mutating func didStart(generation: Int, success: Bool) {
        phase = success ? .running(generation) : .idle
        if !success {
            noPlaybackDeadline = nil
            if self.generation == generation { self.generation += 1 }
        }
    }

    mutating func captureFailed(generation: Int) -> Bool {
        guard case .running(let active) = phase, active == generation else { return false }
        phase = .idle
        noPlaybackDeadline = nil
        // Only an explicit request made after this capture became obsolete may
        // start another attempt. A queued reconcile is not a retry request.
        if self.generation == generation {
            requested = false
            self.generation += 1
        }
        return true
    }

    func accepts(_ generation: Int) -> Bool {
        guard !paused, !terminated, othersPlaying || noPlaybackDeadline != nil,
              self.generation == generation,
              case .running(let active) = phase else { return false }
        return active == generation
    }
}

/// One-shot scheduling, owned by the capture control queue. A token also rejects
/// cancelled work that had already been dequeued; repeated events keep the deadline.
final class AudioPlaybackTimer {
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> () -> Void
    private let schedule: Schedule
    private var deadline: TimeInterval?
    private var token: UUID?
    private var cancel: (() -> Void)?

    init(schedule: @escaping Schedule) { self.schedule = schedule }

    func update(deadline: TimeInterval?, now: TimeInterval, fire: @escaping () -> Void) {
        guard self.deadline != deadline else { return }
        token = nil
        cancel?()
        cancel = nil
        self.deadline = deadline
        guard let deadline else { return }
        let id = UUID()
        token = id
        cancel = schedule(max(0, deadline - now)) { [weak self] in
            guard let self, self.token == id else { return }
            self.token = nil
            self.deadline = nil
            self.cancel = nil
            fire()
        }
    }

    deinit { cancel?() }
}

@MainActor
final class AudioSpectrum {
    var onSpectrum: (([Double]) -> Void)?
    private var worker: AudioCaptureWorker?
    private var stopped = false

    func setPaused(_ paused: Bool) {
        guard !stopped else { return }
        ensureWorker().setPaused(paused)
    }

    func setPlayback(_ playing: Bool) {
        guard !stopped else { return }
        // Some apps keep their output stream open after playback pauses. Capture
        // stays on then, but SpectrumAnalyzer gates FFT and events during silence.
        ensureWorker().setPlayback(playing)
    }

    private func ensureWorker() -> AudioCaptureWorker {
        if worker == nil {
            worker = AudioCaptureWorker { [weak self] bands in self?.onSpectrum?(bands) }
        }
        return worker!
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        onSpectrum = nil
        worker?.shutdown(wait: true)
        worker = nil
    }

    deinit { worker?.shutdown(wait: false) }
}

private struct AudioCaptureError: Error {
    let step: String
    let status: OSStatus
}

/// Pure buffer adaptation, also exercised with synthetic AudioBufferLists.
/// Never retains a Core Audio input pointer beyond the current callback.
final class AudioTapInput {
    struct Update {
        let bands: [Double]?
        let sound: Bool?
    }

    let rate: Double
    let channels: Int
    private let planar: Bool
    private let analyzer: SpectrumAnalyzer
    private var scratch: [Float]

    init(format: AudioStreamBasicDescription) throws {
        let channels = Int(format.mChannelsPerFrame)
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mBitsPerChannel == 32, channels > 0,
              format.mSampleRate.isFinite, format.mSampleRate > 0,
              Int(format.mBytesPerFrame) == (planar ? 1 : channels) * MemoryLayout<Float>.size else {
            throw AudioCaptureError(step: "tapFormat", status: kAudioDeviceUnsupportedFormatError)
        }
        self.rate = format.mSampleRate
        self.channels = channels
        self.planar = planar
        analyzer = SpectrumAnalyzer(sampleRate: rate, channels: channels, parameters: .lano)
        scratch = Array(repeating: 0, count: planar ? 2048 * channels : 0)
    }

    func process(_ input: UnsafePointer<AudioBufferList>) throws -> Update {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let count = planar ? channels : 1
        guard buffers.count >= count else { throw invalidBuffer() }
        // The sole tap is appended after the output subdevice's input streams.
        // Read only that suffix, never a headset/interface microphone buffer.
        let first = buffers.count - count
        let stride = (planar ? 1 : channels) * MemoryLayout<Float>.size
        let frames = Int(buffers[first].mDataByteSize) / stride
        for index in first..<buffers.count {
            let buffer = buffers[index]
            guard Int(buffer.mNumberChannels) == (planar ? 1 : channels),
                  Int(buffer.mDataByteSize) == frames * stride,
                  frames == 0 || buffer.mData != nil else { throw invalidBuffer() }
        }
        let wasSilent = analyzer.isSilent
        var last: [Double]?
        if frames > 0, !planar {
            let samples = buffers[first].mData!.assumingMemoryBound(to: Float.self)
            last = analyzer.process(UnsafeBufferPointer(start: samples, count: frames * channels),
                                    frameCount: frames).last
        } else if frames > 0 {
            // Planar input is interleaved into a reusable bounded scratch buffer;
            // the analyzer keeps the identical per-channel sanitization/averaging.
            var offset = 0
            while offset < frames {
                let chunk = min(2048, frames - offset)
                for channel in 0..<channels {
                    let samples = buffers[first + channel].mData!.assumingMemoryBound(to: Float.self)
                    for frame in 0..<chunk { scratch[frame * channels + channel] = samples[offset + frame] }
                }
                if let result = scratch.withUnsafeBufferPointer({
                    analyzer.process($0, frameCount: chunk).last
                }) { last = result }
                offset += chunk
            }
        }
        return Update(bands: analyzer.isSilent ? nil : last,
                      sound: wasSilent == analyzer.isSilent ? nil : !analyzer.isSilent)
    }

    private func invalidBuffer() -> AudioCaptureError {
        AudioCaptureError(step: "inputBuffer", status: kAudioDeviceUnsupportedFormatError)
    }
}

/// Control and IO use different serial queues: Core Audio dispatches IO blocks
/// synchronously, so stopping on the IO queue itself could wait on that queue.
private final class AudioCaptureWorker {
    private let control = DispatchQueue(label: "DesktopShell.audio.control", qos: .userInitiated)
    private let io = DispatchQueue(label: "DesktopShell.audio.io", qos: .userInitiated)
    private let lock = NSLock()
    private var state = AudioCaptureState()
    private var session: AudioCaptureSession?
    private var listener: AudioObjectPropertyListenerBlock?
    private lazy var playbackTimer = AudioPlaybackTimer { [control] delay, action in
        let work = DispatchWorkItem(block: action)
        control.asyncAfter(deadline: .now() + delay, execute: work)
        return { work.cancel() }
    }
    private let receive: @MainActor ([Double]) -> Void

    init(receive: @escaping @MainActor ([Double]) -> Void) { self.receive = receive }

    private func withState<T>(_ body: (inout AudioCaptureState) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }

    func setPaused(_ paused: Bool) {
        withState { $0.setPaused(paused) }
        control.async { self.reconcile() }
    }

    func setPlayback(_ playing: Bool) {
        withState { $0.setPlayback(playing, now: ProcessInfo.processInfo.systemUptime) }
        control.async { self.reconcile() }
    }

    func shutdown(wait: Bool) {
        withState { $0.stop() }
        let completion = DispatchSemaphore(value: 0)
        control.async {
            self.reconcile()
            self.removeListener()
            completion.signal()
        }
        // Normal teardown finishes before app termination. Permission setup can
        // block in Core Audio indefinitely; do not hang the main thread on quit.
        if wait, completion.wait(timeout: .now() + 1) == .timedOut {
            Log.notice("DesktopShell audio: quit cleanup pending")
        }
    }

    private func reconcile() {
        // Recheck the monotonic deadline after a potentially blocking setup too.
        while let action = withState({ state in
            state.expireNoPlayback(now: ProcessInfo.processInfo.systemUptime)
            return state.nextAction()
        }) {
            switch action {
            case .stop(let reason):
                session?.close(reason: reason)
                session = nil
            case .start(let generation):
                do {
                    try installListener()
                    guard #available(macOS 14.2, *) else {
                        throw AudioCaptureError(step: "systemVersion", status: kAudioHardwareUnsupportedOperationError)
                    }
                    let capture = AudioCaptureSession()
                    session = capture // Own partial resources before any fallible setup.
                    try capture.start(io: io, output: { [weak self] update in
                        self?.deliver(update, generation: generation)
                    }, failure: { [weak self] error in
                        self?.control.async { self?.captureFailed(error, generation: generation) }
                    })
                    withState { $0.didStart(generation: generation, success: true) }
                } catch {
                    report(error)
                    session?.close(reason: .error)
                    session = nil
                    withState { $0.didStart(generation: generation, success: false) }
                }
            }
        }
        playbackTimer.update(deadline: withState { $0.noPlaybackDeadline },
                             now: ProcessInfo.processInfo.systemUptime) { [weak self] in
            self?.reconcile()
        }
    }

    private func captureFailed(_ error: Error, generation: Int) {
        guard withState({ $0.captureFailed(generation: generation) }) else { return }
        report(error)
        session?.close(reason: .error)
        session = nil
        reconcile()
    }

    private func deliver(_ update: AudioTapInput.Update, generation: Int) {
        guard update.bands != nil || update.sound != nil else { return }
        // IO may begin before AudioDeviceStart returns. Queue behind setup so
        // the first sound transition is not discarded just because phase is starting.
        control.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.withState({ $0.accepts(generation) }) else { return }
                if let sound = update.sound { Log.notice("DesktopShell audio: sound=\(sound)") }
                if let bands = update.bands { self.receive(bands) }
            }
        }
    }

    private func installListener() throws {
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.withState { $0.deviceChanged() }
            self.control.async { self.reconcile() }
        }
        var address = audioAddress(kAudioHardwarePropertyDefaultOutputDevice)
        try audioCheck("addOutputListener", AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, control, block))
        listener = block
    }

    private func removeListener() {
        guard let listener else { return }
        var address = audioAddress(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, control, listener)
        if status != noErr { report(AudioCaptureError(step: "removeOutputListener", status: status)) }
        self.listener = nil
    }

    private func report(_ error: Error) {
        let failure = error as? AudioCaptureError
        Log.error("DesktopShell audio: \(failure?.step ?? "capture") failed status=\(failure?.status ?? kAudioHardwareUnspecifiedError)")
    }
}

/// Resource ownership lives exclusively on the control queue. The IO closure
/// owns its processor separately and never reads these handles or writes logs.
private final class AudioCaptureSession {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?

    @available(macOS 14.2, *)
    func start(io: DispatchQueue, output: @escaping (AudioTapInput.Update) -> Void,
               failure: @escaping (Error) -> Void) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.muteBehavior = .unmuted
        description.isPrivate = true
        try audioCheck("createTap", AudioHardwareCreateProcessTap(description, &tap))

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout.size(ofValue: format))
        var address = audioAddress(kAudioTapPropertyFormat)
        try audioCheck("readTapFormat", AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
        let input = try AudioTapInput(format: format)

        var outputID = AudioObjectID(kAudioObjectUnknown)
        size = UInt32(MemoryLayout.size(ofValue: outputID))
        address = audioAddress(kAudioHardwarePropertyDefaultOutputDevice)
        try audioCheck("readDefaultOutput", AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &outputID))
        let outputUID = try audioString(outputID, selector: kAudioDevicePropertyDeviceUID, step: "readOutputUID")
        let tapUID = try audioString(tap, selector: kAudioTapPropertyUID, step: "readTapUID")
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "DesktopShell Spectrum",
            kAudioAggregateDeviceUIDKey: "local.desktopshell.audio.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID]],
            kAudioAggregateDeviceTapAutoStartKey: true
        ]
        try audioCheck("createAggregate", AudioHardwareCreateAggregateDevice(composition as CFDictionary, &device))
        // This flag belongs to the IO queue, not the control queue.
        let callback = AudioInputCallback(input: input, output: output, failure: failure)
        try audioCheck("createIOProc", AudioDeviceCreateIOProcIDWithBlock(&proc, device, io) {
            _, data, _, _, _ in callback.process(data)
        })
        guard let proc else { throw AudioCaptureError(step: "createIOProc", status: kAudioHardwareUnspecifiedError) }
        try audioCheck("startDevice", AudioDeviceStart(device, proc))
        Log.notice("DesktopShell audio: capture started rate=\(format.mSampleRate) channels=\(format.mChannelsPerFrame)")
    }

    func close(reason: AudioCaptureState.StopReason) {
        let hadResources = tap != kAudioObjectUnknown || device != kAudioObjectUnknown || proc != nil
        if let proc {
            cleanup("stopDevice", AudioDeviceStop(device, proc))
            cleanup("destroyIOProc", AudioDeviceDestroyIOProcID(device, proc))
        }
        proc = nil
        if device != kAudioObjectUnknown { cleanup("destroyAggregate", AudioHardwareDestroyAggregateDevice(device)) }
        device = AudioObjectID(kAudioObjectUnknown)
        if #available(macOS 14.2, *), tap != kAudioObjectUnknown {
            cleanup("destroyTap", AudioHardwareDestroyProcessTap(tap))
        }
        tap = AudioObjectID(kAudioObjectUnknown)
        if hadResources { Log.notice("DesktopShell audio: capture stopped reason=\(reason.rawValue)") }
    }

    private func cleanup(_ step: String, _ status: OSStatus) {
        if status != noErr { Log.error("DesktopShell audio: \(step) failed status=\(status)") }
    }
}

private final class AudioInputCallback {
    let input: AudioTapInput
    let output: (AudioTapInput.Update) -> Void
    let failure: (Error) -> Void
    private var failed = false

    init(input: AudioTapInput, output: @escaping (AudioTapInput.Update) -> Void,
         failure: @escaping (Error) -> Void) {
        self.input = input
        self.output = output
        self.failure = failure
    }

    func process(_ data: UnsafePointer<AudioBufferList>) {
        guard !failed else { return }
        do { output(try input.process(data)) }
        catch { failed = true; failure(error) }
    }
}

private func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

private func audioCheck(_ step: String, _ status: OSStatus) throws {
    if status != noErr { throw AudioCaptureError(step: step, status: status) }
}

private func audioString(_ object: AudioObjectID, selector: AudioObjectPropertySelector,
                         step: String) throws -> String {
    var address = audioAddress(selector)
    let pointer = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
    pointer.initialize(to: nil)
    defer { pointer.deinitialize(count: 1); pointer.deallocate() }
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    try audioCheck(step, AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer))
    guard let value = pointer.pointee else {
        throw AudioCaptureError(step: step, status: kAudioHardwareUnspecifiedError)
    }
    return value.takeRetainedValue() as String
}
