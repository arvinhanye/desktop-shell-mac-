import Foundation
import CoreAudio
import Testing
@testable import DesktopShell

struct PlaybackPredicateTests {
    @Test("空列表、仅自身输出、其他进程未输出均为 false")
    func noOtherPlayback() {
        #expect(!anyOtherOutputting([], ownPID: 42))
        #expect(!anyOtherOutputting([(42, true)], ownPID: 42))
        #expect(!anyOtherOutputting([(42, true), (51, false)], ownPID: 42))
    }

    @Test("排除自身不会排除其他进程（包括 WebKit 语音）")
    func otherPlayback() {
        #expect(anyOtherOutputting([(42, true), (51, true)], ownPID: 42))
        #expect(anyOtherOutputting([(51, false), (52, true)], ownPID: 42))
    }
}

@MainActor
struct PlaybackMonitorTests {
    private final class Source: PlaybackSource {
        var ids: [AudioObjectID] = []
        var states: [AudioObjectID: (pid: pid_t, runningOutput: Bool)] = [:]
        var reads: [AudioObjectID] = []
        var listReads = 0
        var failList = false
        var observations: [(AudioObjectID, AudioObjectPropertySelector, @MainActor () -> Void)] = []
        var removed: [Int] = []
        enum Failure: Error { case read }
        func processIDs() throws -> [AudioObjectID] {
            listReads += 1
            if failList { throw Failure.read }
            return ids
        }
        func processState(_ id: AudioObjectID) throws -> (pid: pid_t, runningOutput: Bool) {
            reads.append(id)
            guard let value = states[id] else { throw Failure.read }
            return value
        }
        func observe(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                     change: @escaping @MainActor () -> Void) throws -> () -> Void {
            let index = observations.count
            observations.append((id, selector, change))
            return { self.removed.append(index) }
        }
    }

    @MainActor private final class Queue {
        var work: [@MainActor () -> Void] = []
        func enqueue(_ action: @escaping @MainActor () -> Void) { work.append(action) }
        func drain() { let batch = work; work.removeAll(); for action in batch { action() } }
    }

    @Test("初始扫描排除自身；只监听 IsRunning，合并事件后重读全部状态")
    func initialAndCoalesced() throws {
        let source = Source(); let queue = Queue()
        source.ids = [10, 11]; source.states = [10: (42, true), 11: (51, false)]
        let monitor = PlaybackMonitor(source: source, ownPID: 42, enqueue: queue.enqueue)
        var changes: [Bool] = []; monitor.onChange = { changes.append($0) }
        monitor.start(); monitor.start()
        #expect(!monitor.othersPlaying && changes == [false])
        #expect(source.listReads == 1 && source.reads == [10, 11])
        try #require(source.observations.count == 3)
        #expect(source.observations[0].1 == kAudioHardwarePropertyProcessObjectList)
        #expect(source.observations.dropFirst().allSatisfy { $0.1 == kAudioProcessPropertyIsRunning })
        source.states[11] = (51, true)
        source.observations[1].2(); source.observations[2].2(); source.observations[0].2()
        #expect(queue.work.count == 1 && source.listReads == 1)
        queue.drain()
        #expect(monitor.othersPlaying && changes == [false, true])
        #expect(source.listReads == 2 && source.reads == [10, 11, 10, 11])
        source.observations[2].2(); queue.drain()
        #expect(changes == [false, true])
        monitor.stop()
        #expect(Set(source.removed) == Set(0..<3))
    }

    @Test("新进程已经输出时仅列表事件也能发现；消失时注销监听")
    func processReconciliation() throws {
        let source = Source(); let queue = Queue()
        let monitor = PlaybackMonitor(source: source, ownPID: 42, enqueue: queue.enqueue)
        var changes: [Bool] = []; monitor.onChange = { changes.append($0) }
        monitor.start()
        source.ids = [12]; source.states = [12: (52, true)]
        source.observations[0].2(); queue.drain()
        #expect(changes == [false, true])
        try #require(source.observations.count == 2)
        source.ids = []; source.states = [:]
        source.observations[0].2(); queue.drain()
        #expect(changes == [false, true, false])
        #expect(source.removed == [1])
        monitor.stop(); monitor.stop()
        #expect(source.removed == [1, 0])
    }

    @Test("stop 和 restart 隔离队列中及已经注销的旧回调")
    func staleCallbacks() throws {
        let source = Source(); let queue = Queue()
        let monitor = PlaybackMonitor(source: source, ownPID: 42, enqueue: queue.enqueue)
        var changes: [Bool] = []; monitor.onChange = { changes.append($0) }
        monitor.start()
        let old = source.observations[0].2
        old(); monitor.stop()
        source.ids = [12]; source.states = [12: (52, true)]
        monitor.start()
        let reads = source.listReads
        old(); queue.drain()
        #expect(source.listReads == reads && changes == [false, true])
        monitor.stop(); old(); queue.drain()
        #expect(source.listReads == reads)
    }

    @Test("列表瞬时读失败不伪报停止，下个事件可恢复")
    func failedSnapshot() {
        let source = Source(); let queue = Queue()
        source.ids = [12]; source.states = [12: (52, true)]
        let monitor = PlaybackMonitor(source: source, ownPID: 42, enqueue: queue.enqueue)
        var changes: [Bool] = []; monitor.onChange = { changes.append($0) }
        monitor.start()
        source.failList = true
        source.observations[0].2(); queue.drain()
        #expect(monitor.othersPlaying && changes == [true])
        source.failList = false; source.ids = []; source.states = [:]
        source.observations[0].2(); queue.drain()
        #expect(!monitor.othersPlaying && changes == [true, false])
        monitor.stop()
    }

    @Test("初始回调内 stop 不会遗留监听")
    func reentrantStop() {
        let source = Source(); let queue = Queue()
        source.ids = [12]; source.states = [12: (52, true)]
        let monitor = PlaybackMonitor(source: source, ownPID: 42, enqueue: queue.enqueue)
        monitor.onChange = { _ in monitor.stop() }
        monitor.start()
        #expect(Set(source.removed) == Set(0..<2))
        monitor.onChange = nil
    }
}
