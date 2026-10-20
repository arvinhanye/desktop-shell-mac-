import Foundation
import CoreAudio
import Testing
@testable import DesktopShell

struct AudioSpectrumTests {
    @Test("未暂停但无人播放不搭建，有人播放立即搭建")
    func playbackRequired() {
        var state = AudioCaptureState()
        state.setPaused(false)
        #expect(state.nextAction() == nil)
        state.deviceChanged()
        #expect(state.nextAction() == nil)
        state.setPlayback(true, now: 10)
        #expect(state.nextAction() == .start(state.generation))
    }

    @Test("2.9 秒内恢复保留当前会话，不重建、不丢掉有效频谱")
    func playbackGap() {
        var state = running()
        let generation = state.generation
        state.setPlayback(false, now: 10)
        #expect(state.noPlaybackDeadline == 13)
        state.expireNoPlayback(now: 12.9)
        #expect(state.nextAction() == nil && state.accepts(generation))
        state.setPlayback(true, now: 12.9)
        state.expireNoPlayback(now: 13)
        #expect(state.noPlaybackDeadline == nil)
        #expect(state.nextAction() == nil && state.accepts(generation))
    }

    @Test("停止满三秒拆除，重复 false 不延长截止时间")
    func playbackTimeout() {
        var state = running()
        let old = state.generation
        state.setPlayback(false, now: 10)
        state.setPlayback(false, now: 12)
        #expect(state.noPlaybackDeadline == 13)
        state.expireNoPlayback(now: 13)
        #expect(state.nextAction() == .stop(.noPlayback))
        #expect(!state.accepts(old) && state.nextAction() == nil)
        state.setPaused(false)
        state.deviceChanged()
        #expect(state.nextAction() == nil)
        state.setPlayback(true, now: 20)
        #expect(state.nextAction() == .start(state.generation))
    }

    @Test("暂停优先；缓冲期暂停后无人播放的恢复不重新捕获")
    func pauseCancelsPlaybackGrace() {
        var state = running()
        state.setPlayback(false, now: 10)
        state.setPaused(true)
        #expect(state.noPlaybackDeadline == nil)
        #expect(state.nextAction() == .stop(.paused))
        state.setPaused(false)
        #expect(state.nextAction() == nil)
        state.setPaused(true)
        state.setPlayback(true, now: 11)
        #expect(state.nextAction() == nil)
        state.setPaused(false)
        #expect(state.nextAction() == .start(state.generation))
    }

    @Test("搭建期间无人播放，到期后拒绝迟到结果并拆除")
    func playbackEndsDuringSetup() {
        var state = AudioCaptureState()
        state.setPlayback(true, now: 0)
        state.setPaused(false)
        let old = state.generation
        #expect(state.nextAction() == .start(old))
        state.setPlayback(false, now: 1)
        state.expireNoPlayback(now: 4)
        #expect(state.nextAction() == nil)
        state.didStart(generation: old, success: true)
        #expect(!state.accepts(old))
        #expect(state.nextAction() == .stop(.noPlayback))
        #expect(state.nextAction() == nil)
    }

    @Test("缓冲期设备变化或错误后，无人播放不重开")
    func noPlaybackAfterTeardown() {
        var state = running()
        state.setPlayback(false, now: 0)
        state.deviceChanged()
        #expect(state.nextAction() == .stop(.deviceChanged))
        #expect(state.nextAction() == nil)
        state = running()
        state.setPlayback(false, now: 0)
        _ = state.captureFailed(generation: state.generation)
        #expect(state.noPlaybackDeadline == nil)
        state.setPaused(false)
        #expect(state.nextAction() == nil)
    }

    @Test("一次性停止任务保留截止时刻，取消后的旧回调无效")
    func playbackTimer() {
        var actions: [() -> Void] = []
        var delays: [Double] = []
        var cancelled: [Int] = []
        let timer = AudioPlaybackTimer { delay, action in
            let index = actions.count
            actions.append(action); delays.append(delay)
            return { cancelled.append(index) }
        }
        var fired = 0
        timer.update(deadline: 13, now: 10) { fired += 1 }
        timer.update(deadline: 13, now: 12.9) { fired += 1 }
        #expect(delays == [3])
        timer.update(deadline: nil, now: 12.9) { fired += 1 }
        #expect(cancelled == [0])
        actions[0]()
        #expect(fired == 0)
        timer.update(deadline: 23, now: 20) { fired += 1 }
        actions[0]()
        #expect(fired == 0)
        actions[1](); actions[1]()
        #expect(fired == 1 && delays == [3, 3])
    }

    @Test("初始暂停不搭建，恢复搭建，重复恢复不重复，暂停拆除")
    func pauseLifecycle() {
        var state = AudioCaptureState()
        state.setPlayback(true, now: 0)
        #expect(state.nextAction() == nil)
        state.setPaused(false)
        let generation = state.generation
        #expect(state.nextAction() == .start(generation))
        #expect(state.nextAction() == nil)
        state.didStart(generation: generation, success: true)
        #expect(state.accepts(generation))
        state.setPaused(false)
        #expect(state.nextAction() == nil)
        state.setPaused(true)
        #expect(!state.accepts(generation))
        #expect(state.nextAction() == .stop(.paused))
        #expect(state.nextAction() == nil)
    }

    @Test("运行时设备变化重建，暂停时变化不动")
    func deviceChange() {
        var state = running()
        let previous = state.generation
        state.deviceChanged()
        #expect(!state.accepts(previous))
        #expect(state.nextAction() == .stop(.deviceChanged))
        #expect(state.nextAction() == .start(state.generation))
        state.didStart(generation: state.generation, success: true)
        state.setPaused(true)
        #expect(state.nextAction() == .stop(.paused))
        state.deviceChanged()
        #expect(state.nextAction() == nil)
        state.setPaused(false)
        #expect(state.nextAction() == .start(state.generation))
    }

    @Test("搭建失败无自动重试，下一次 false 或设备变化可重试", arguments: [false, true])
    func failureRetry(device: Bool) {
        var state = AudioCaptureState()
        state.setPlayback(true, now: 0)
        state.setPaused(false)
        #expect(state.nextAction() == .start(state.generation))
        state.didStart(generation: state.generation, success: false)
        for _ in 0..<5 { #expect(state.nextAction() == nil) }
        if device { state.deviceChanged() } else { state.setPaused(false) }
        #expect(state.nextAction() == .start(state.generation))
    }

    @Test("权限等待期间暂停按最终状态收敛且旧结果被丢弃")
    func pauseDuringStart() {
        var state = AudioCaptureState()
        state.setPlayback(true, now: 0)
        state.setPaused(false)
        let old = state.generation
        #expect(state.nextAction() == .start(old))
        state.setPaused(true)
        #expect(state.nextAction() == nil)
        state.didStart(generation: old, success: true)
        #expect(!state.accepts(old))
        #expect(state.nextAction() == .stop(.paused))
        #expect(state.nextAction() == nil)
    }

    @Test("快速 false true false 仅重建一次并隔离旧回调")
    func rapidChanges() {
        var state = running()
        let old = state.generation
        state.setPaused(true)
        state.setPaused(false)
        #expect(!state.accepts(old))
        #expect(state.nextAction() == .stop(.paused))
        let current = state.generation
        #expect(state.nextAction() == .start(current))
        state.didStart(generation: current, success: true)
        #expect(state.accepts(current))
        #expect(!state.accepts(old))
        #expect(state.nextAction() == nil)
    }

    @Test("退出是终态，包括搭建未完成时退出")
    func quitDuringStart() {
        var state = AudioCaptureState()
        state.setPlayback(true, now: 0)
        state.setPaused(false)
        let old = state.generation
        #expect(state.nextAction() == .start(old))
        state.stop()
        state.setPaused(false)
        state.deviceChanged()
        state.didStart(generation: old, success: true)
        #expect(!state.accepts(old))
        #expect(state.nextAction() == .stop(.quit))
        #expect(state.nextAction() == nil)
    }

    @Test("运行错误停止接收且不会因残留调度自行重试")
    func runtimeFailure() {
        var state = running()
        let generation = state.generation
        let stopped = state.captureFailed(generation: generation)
        #expect(stopped)
        #expect(!state.accepts(generation))
        #expect(state.nextAction() == nil)
        let duplicate = state.captureFailed(generation: generation)
        #expect(!duplicate)
        state.setPaused(false)
        #expect(state.nextAction() == .start(state.generation))
    }

    @Test("失败重试的新会话拒绝旧频谱和旧错误", arguments: [false, true])
    func failureInvalidatesGeneration(duringSetup: Bool) {
        var state = AudioCaptureState()
        state.setPlayback(true, now: 0)
        state.setPaused(false)
        let old = state.generation
        _ = state.nextAction()
        state.didStart(generation: old, success: !duringSetup)
        if !duringSetup { _ = state.captureFailed(generation: old) }
        state.setPaused(false)
        #expect(state.nextAction() == .start(state.generation))
        state.didStart(generation: state.generation, success: true)
        #expect(!state.accepts(old))
        let staleError = state.captureFailed(generation: old)
        #expect(!staleError)
        #expect(state.accepts(state.generation))
    }

    @Test("交错与非交错使用相同采样率和声道语义，只返回最后一组", arguments: [44100.0, 48000.0])
    func buffersMatchAnalyzer(rate: Double) throws {
        let frames = 8192 + 137
        let left = (0..<frames).map { Float(sin(2 * .pi * 1000 * Double($0) / rate) * 0.1) }
        let right = left.map { $0 * 0.5 }
        let interleaved = zip(left, right).flatMap { [$0, $1] }
        let analyzer = SpectrumAnalyzer(sampleRate: rate, channels: 2)
        let expected = interleaved.withUnsafeBufferPointer { analyzer.process($0, frameCount: frames).last }
        for planar in [false, true] {
            let input = try AudioTapInput(format: format(rate: rate, planar: planar))
            // Leading physical-device input is deliberately different and ignored.
            let arrays = planar ? [[Float](repeating: 1, count: frames), left, right]
                                : [[Float](repeating: 1, count: frames), interleaved]
            let update = try withBuffers(arrays, channels: planar ? [1, 1, 1] : [1, 2]) {
                try input.process($0)
            }
            #expect(update.bands == expected)
            #expect(update.sound == true)
            let quiet = planar ? [Array<Float>(repeating: 0, count: 48000 * 3), Array<Float>(repeating: 0, count: 48000 * 3)]
                               : [Array<Float>(repeating: 0, count: 48000 * 6)]
            let silent = try withBuffers(quiet, channels: planar ? [1, 1] : [2]) { try input.process($0) }
            #expect(silent.bands == nil && silent.sound == false)
            let again = try withBuffers(quiet, channels: planar ? [1, 1] : [2]) { try input.process($0) }
            #expect(again.bands == nil && again.sound == nil)
        }
    }

    @Test("空缓冲保持静音，不匹配格式或缓冲明确失败")
    func bufferValidation() throws {
        let input = try AudioTapInput(format: format())
        let empty = try withBuffers([[]], channels: [2]) { try input.process($0) }
        #expect(empty.bands == nil && empty.sound == nil)
        #expect(throws: (any Error).self) {
            try withBuffers([[0, 1, 2]], channels: [2]) { try input.process($0) }
        }
        #expect(throws: (any Error).self) {
            try withBuffers([[0, 1]], channels: [1]) { try input.process($0) }
        }
        let planar = try AudioTapInput(format: format(planar: true))
        #expect(throws: (any Error).self) {
            try withBuffers([[0, 1], [0]], channels: [1, 1]) { try planar.process($0) }
        }
        var invalid = format(); invalid.mSampleRate = .nan
        #expect(throws: (any Error).self) { try AudioTapInput(format: invalid) }
        invalid = format(); invalid.mBitsPerChannel = 16
        #expect(throws: (any Error).self) { try AudioTapInput(format: invalid) }
    }

    private func format(rate: Double = 48000, planar: Bool = false) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | (planar ? kAudioFormatFlagIsNonInterleaved : 0),
            mBytesPerPacket: planar ? 4 : 8, mFramesPerPacket: 1, mBytesPerFrame: planar ? 4 : 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    }

    private func withBuffers<T>(_ arrays: [[Float]], channels: [Int],
                                body: (UnsafePointer<AudioBufferList>) throws -> T) rethrows -> T {
        let buffers = AudioBufferList.allocate(maximumBuffers: arrays.count)
        let pointers = arrays.map { values -> UnsafeMutablePointer<Float> in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: max(1, values.count))
            pointer.initialize(from: values, count: values.count)
            return pointer
        }
        defer {
            for (index, pointer) in pointers.enumerated() {
                pointer.deinitialize(count: arrays[index].count); pointer.deallocate()
            }
            free(buffers.unsafeMutablePointer)
        }
        for index in arrays.indices {
            buffers[index] = AudioBuffer(mNumberChannels: UInt32(channels[index]),
                mDataByteSize: UInt32(arrays[index].count * MemoryLayout<Float>.size), mData: pointers[index])
        }
        return try body(UnsafePointer(buffers.unsafeMutablePointer))
    }

    private func running() -> AudioCaptureState {
        var state = AudioCaptureState()
        state.setPlayback(true, now: 0)
        state.setPaused(false)
        _ = state.nextAction()
        state.didStart(generation: state.generation, success: true)
        return state
    }
}
