import Foundation

@MainActor
final class OcclusionDebouncer {
    typealias Schedule = (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void

    private let delay: TimeInterval
    private let schedule: Schedule
    private var pendingID: UUID?
    private var cancelPending: (() -> Void)?
    private(set) var isOccluded = false
    var onChange: ((Bool) -> Void)?

    init(delay: TimeInterval = 1.0, schedule: @escaping Schedule = { delay, action in
        let work = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return { work.cancel() }
    }) {
        self.delay = delay
        self.schedule = schedule
    }

    func update(rawOccluded: Bool) {
        guard rawOccluded else {
            cancelScheduledChange()
            if isOccluded {
                isOccluded = false
                onChange?(false)
            }
            return
        }
        guard !isOccluded, pendingID == nil else { return }
        let id = UUID()
        pendingID = id
        cancelPending = schedule(delay) { [weak self] in
            guard let self, self.pendingID == id else { return }
            self.pendingID = nil
            self.cancelPending = nil
            self.isOccluded = true
            self.onChange?(true)
        }
    }

    func cancel() {
        cancelScheduledChange()
        isOccluded = false
    }

    private func cancelScheduledChange() {
        // Invalidate before cancelling: already-dequeued work must also be harmless.
        pendingID = nil
        cancelPending?()
        cancelPending = nil
    }
}
