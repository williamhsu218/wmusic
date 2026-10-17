import Foundation
import Observability

/// AppKit keeps servicing its main run loop while asynchronous shutdown saves
/// playback state. The save itself may need the main actor (podcast resolver /
/// Now Playing), so willTerminate must never wait on a semaphore.
///
/// Logout and restart wait on the quit reply, so a hung save (a sleeping NAS,
/// a stuck sync listener) must not keep WMusic or the session from quitting:
/// the reply is sent at the deadline even if preparation is still running.
@MainActor
final class TerminationCoordinator {
    static let defaultDeadline: Duration = .seconds(3)

    var prepare: (@MainActor () async -> Void)?
    private let deadline: Duration
    private var isPreparing = false
    private var pendingReply: (@MainActor () -> Void)?
    private var deadlineTask: Task<Void, Never>?
    private let log = AppLogger.make(.app)

    init(deadline: Duration = TerminationCoordinator.defaultDeadline) {
        self.deadline = deadline
    }

    func requestTermination(reply: @escaping @MainActor () -> Void) {
        guard !self.isPreparing else { return }
        self.isPreparing = true
        self.pendingReply = reply
        let start = Date()
        let deadline = self.deadline
        self.deadlineTask = Task { [weak self] in
            do {
                try await Task.sleep(for: deadline)
            } catch {
                return
            }
            self?.finish(timedOut: true, start: start)
        }
        Task {
            await self.prepare?()
            self.finish(timedOut: false, start: start)
        }
    }

    /// Replies exactly once: whichever of preparation and deadline comes first.
    private func finish(timedOut: Bool, start: Date) {
        guard let reply = self.pendingReply else { return }
        self.pendingReply = nil
        self.deadlineTask?.cancel()
        let elapsed = -start.timeIntervalSinceNow * 1000
        if timedOut {
            self.log.warning("app.termination.timedOut", ["ms": elapsed])
        } else {
            self.log.debug("app.termination.prepared", ["ms": elapsed])
        }
        reply()
    }
}
