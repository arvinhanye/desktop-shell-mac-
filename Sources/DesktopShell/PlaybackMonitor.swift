import Foundation
import CoreAudio

func anyOtherOutputting(_ processes: [(pid: pid_t, runningOutput: Bool)], ownPID: pid_t) -> Bool {
    processes.contains { $0.pid != ownPID && $0.runningOutput }
}

/// The seam keeps Core Audio registration out of deterministic lifecycle tests.
@MainActor
protocol PlaybackSource: AnyObject {
    func processIDs() throws -> [AudioObjectID]
    func processState(_ id: AudioObjectID) throws -> (pid: pid_t, runningOutput: Bool)
    func observe(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                 change: @escaping @MainActor () -> Void) throws -> () -> Void
}

@MainActor
final class PlaybackMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var othersPlaying = false
    private let source: PlaybackSource
    private let ownPID: pid_t
    private let enqueue: (@escaping @MainActor () -> Void) -> Void
    private var listCancellation: (() -> Void)?
    private var processCancellations: [AudioObjectID: () -> Void] = [:]
    private var running = false
    private var published = false
    private var refreshPending = false
    private var generation = 0

    init(source: PlaybackSource? = nil, ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
         enqueue: @escaping (@escaping @MainActor () -> Void) -> Void = { action in
             DispatchQueue.main.async { action() }
         }) {
        self.source = source ?? CoreAudioPlaybackSource()
        self.ownPID = ownPID
        self.enqueue = enqueue
    }

    func start() {
        guard !running else { return }
        running = true
        published = false
        generation += 1
        let current = generation
        do {
            listCancellation = try source.observe(AudioObjectID(kAudioObjectSystemObject),
                selector: kAudioHardwarePropertyProcessObjectList) { [weak self] in
                    self?.scheduleRefresh(generation: current)
                }
        } catch {
            running = false
            reportPlaybackError(error)
            return
        }
        refresh(generation: current)
    }

    func stop() {
        running = false
        generation += 1
        refreshPending = false
        let cancelList = listCancellation
        let cancelProcesses = Array(processCancellations.values)
        listCancellation = nil
        processCancellations.removeAll()
        cancelList?()
        for cancel in cancelProcesses { cancel() }
    }

    deinit {
        // Cancellation closures own the exact original block and queue; no raw
        // unretained context can survive the monitor's lifetime.
        listCancellation?()
        for cancel in processCancellations.values { cancel() }
    }

    private func scheduleRefresh(generation: Int) {
        guard running, self.generation == generation, !refreshPending else { return }
        refreshPending = true
        enqueue { [weak self] in
            guard let self, self.running, self.generation == generation else { return }
            self.refreshPending = false
            self.refresh(generation: generation)
        }
    }

    private func refresh(generation: Int) {
        guard running, self.generation == generation else { return }
        let ids: [AudioObjectID]
        do { ids = Array(Set(try source.processIDs())).sorted() }
        catch { reportPlaybackError(error); return }
        let current = Set(ids)
        for id in Array(processCancellations.keys) where !current.contains(id) {
            processCancellations.removeValue(forKey: id)?()
        }
        for id in ids where processCancellations[id] == nil {
            do {
                // IsRunningOutput is read-only here: the probe established that
                // changes notify IsRunning, not IsRunningOutput itself.
                processCancellations[id] = try source.observe(id, selector: kAudioProcessPropertyIsRunning) { [weak self] in
                    self?.scheduleRefresh(generation: generation)
                }
            } catch { reportPlaybackError(error) }
        }
        var snapshot: [(pid: pid_t, runningOutput: Bool)] = []
        var complete = true
        for id in ids {
            do { snapshot.append(try source.processState(id)) }
            catch { complete = false; reportPlaybackError(error) }
        }
        let playing = anyOtherOutputting(snapshot, ownPID: ownPID)
        // A process can disappear between list and property reads. An incomplete
        // snapshot must not fabricate a stop; a later event reconciles the list.
        guard complete || playing else { return }
        guard !published || playing != othersPlaying else { return }
        published = true
        othersPlaying = playing
        Log.notice("DesktopShell audio: playback=\(playing)")
        onChange?(playing)
    }
}

private struct PlaybackReadError: Error {
    let step: String
    let status: OSStatus
}

private func reportPlaybackError(_ error: Error) {
    let failure = error as? PlaybackReadError
    // Failure metadata only: never include process IDs, names or bundle IDs.
    Log.error("DesktopShell audio: \(failure?.step ?? "playbackRead") failed status=\(failure?.status ?? kAudioHardwareUnspecifiedError)")
}

@MainActor
private final class CoreAudioPlaybackSource: PlaybackSource {
    func processIDs() throws -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        try Self.check("processListSize", AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size))
        guard size > 0 else { return [] }
        guard Int(size) % MemoryLayout<AudioObjectID>.size == 0 else {
            throw PlaybackReadError(step: "processListSize", status: kAudioHardwareBadPropertySizeError)
        }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let capacity = size
        let status = ids.withUnsafeMutableBufferPointer {
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
        }
        try Self.check("processList", status)
        guard size <= capacity, Int(size) % MemoryLayout<AudioObjectID>.size == 0 else {
            throw PlaybackReadError(step: "processList", status: kAudioHardwareBadPropertySizeError)
        }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    func processState(_ id: AudioObjectID) throws -> (pid: pid_t, runningOutput: Bool) {
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout.size(ofValue: pid))
        var address = Self.address(kAudioProcessPropertyPID)
        try Self.check("processPID", AudioObjectGetPropertyData(id, &address, 0, nil, &size, &pid))
        var output: UInt32 = 0
        size = UInt32(MemoryLayout.size(ofValue: output))
        address = Self.address(kAudioProcessPropertyIsRunningOutput)
        try Self.check("processOutput", AudioObjectGetPropertyData(id, &address, 0, nil, &size, &output))
        return (pid, output == 1)
    }

    func observe(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                 change: @escaping @MainActor () -> Void) throws -> () -> Void {
        var address = Self.address(selector)
        let queue = DispatchQueue.main
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { change() }
        }
        try Self.check("addPlaybackListener", AudioObjectAddPropertyListenerBlock(id, &address, queue, block))
        return {
            var address = Self.address(selector)
            let status = AudioObjectRemovePropertyListenerBlock(id, &address, queue, block)
            // Vanished process objects have already lost their listeners.
            if status != noErr && status != kAudioHardwareBadObjectError {
                reportPlaybackError(PlaybackReadError(step: "removePlaybackListener", status: status))
            }
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func check(_ step: String, _ status: OSStatus) throws {
        if status != noErr { throw PlaybackReadError(step: step, status: status) }
    }
}
