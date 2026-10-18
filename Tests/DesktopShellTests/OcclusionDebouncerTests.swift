import Foundation
import Testing
@testable import DesktopShell

@MainActor
struct OcclusionDebouncerTests {
    @MainActor private final class Scheduler {
        var actions: [@MainActor () -> Void] = []
        var delays: [TimeInterval] = []
        var cancelled: [Int] = []
        func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void {
            let index = actions.count
            actions.append(action)
            delays.append(delay)
            return { self.cancelled.append(index) }
        }
        // Deliberately run even cancelled work: Dispatch cancellation alone is insufficient.
        func fire(_ index: Int) { actions[index]() }
    }

    @Test("初始可见，重复可见不安排任务、不发事件")
    func initiallyVisible() {
        let scheduler = Scheduler()
        let subject = OcclusionDebouncer(schedule: scheduler.schedule)
        var changes: [Bool] = []; subject.onChange = { changes.append($0) }
        subject.update(rawOccluded: false); subject.update(rawOccluded: false)
        #expect(!subject.isOccluded)
        #expect(scheduler.actions.isEmpty && changes.isEmpty)
    }

    @Test("连续遮挡只安排一次一秒延迟，到期只发一次 true")
    func sustainedOcclusion() throws {
        let scheduler = Scheduler()
        let subject = OcclusionDebouncer(schedule: scheduler.schedule)
        var changes: [Bool] = []; subject.onChange = { changes.append($0) }
        for _ in 0..<5 { subject.update(rawOccluded: true) }
        #expect(!subject.isOccluded && changes.isEmpty)
        try #require(scheduler.actions.count == 1)
        #expect(scheduler.delays == [1.0])
        scheduler.fire(0); scheduler.fire(0)
        subject.update(rawOccluded: true)
        #expect(subject.isOccluded && changes == [true])
        #expect(scheduler.actions.count == 1)
    }

    @Test("短暂遮挡恢复后取消，过期回调不产生效果")
    func briefOcclusion() throws {
        let scheduler = Scheduler()
        let subject = OcclusionDebouncer(schedule: scheduler.schedule)
        var changes: [Bool] = []; subject.onChange = { changes.append($0) }
        subject.update(rawOccluded: true); subject.update(rawOccluded: false)
        try #require(scheduler.actions.count == 1)
        #expect(scheduler.cancelled == [0])
        scheduler.fire(0)
        #expect(!subject.isOccluded && changes.isEmpty)
    }

    @Test("已遮挡恢复立即通知，不重复通知；下一轮重新计时")
    func immediateRecovery() throws {
        let scheduler = Scheduler()
        let subject = OcclusionDebouncer(delay: 0.25, schedule: scheduler.schedule)
        var changes: [Bool] = []; subject.onChange = { changes.append($0) }
        subject.update(rawOccluded: true)
        try #require(scheduler.actions.count == 1); scheduler.fire(0)
        subject.update(rawOccluded: false); subject.update(rawOccluded: false)
        #expect(!subject.isOccluded && changes == [true, false])
        subject.update(rawOccluded: true)
        try #require(scheduler.actions.count == 2)
        #expect(scheduler.delays == [0.25, 0.25])
        scheduler.fire(1)
        #expect(subject.isOccluded && changes == [true, false, true])
    }

    @Test("旧任务被取消后不干扰新一轮遮挡")
    func staleGeneration() throws {
        let scheduler = Scheduler()
        let subject = OcclusionDebouncer(schedule: scheduler.schedule)
        var changes: [Bool] = []; subject.onChange = { changes.append($0) }
        subject.update(rawOccluded: true); subject.update(rawOccluded: false)
        subject.update(rawOccluded: true)
        try #require(scheduler.actions.count == 2)
        scheduler.fire(0)
        #expect(!subject.isOccluded && changes.isEmpty)
        scheduler.fire(1)
        #expect(subject.isOccluded && changes == [true])
    }

    @Test("cancel 取消待执行任务或清空已遮挡状态，不触发回调")
    func cancellation() throws {
        let scheduler = Scheduler()
        let subject = OcclusionDebouncer(schedule: scheduler.schedule)
        var changes: [Bool] = []; subject.onChange = { changes.append($0) }
        subject.update(rawOccluded: true); subject.cancel()
        try #require(scheduler.actions.count == 1)
        #expect(scheduler.cancelled == [0]); scheduler.fire(0)
        #expect(!subject.isOccluded && changes.isEmpty)
        subject.update(rawOccluded: true)
        try #require(scheduler.actions.count == 2); scheduler.fire(1)
        subject.cancel(); subject.cancel(); scheduler.fire(1)
        #expect(!subject.isOccluded && changes == [true])
    }
}
