import Foundation

/// Failure reported when the caller's deadline expires.
public enum OperationDeadlineError: Error, Sendable, Equatable {
    case timedOut
}

/// Bounds the caller's wait even when an operation ignores task cancellation.
/// Cancellation of the underlying work is best effort: callers must separately
/// close owned sockets/processes and reject late mutations of shared state.
public enum OperationDeadline {
    /// Returns the operation result, or throws when its deadline or caller cancellation wins.
    public static func run<Value: Sendable>(
        for duration: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let race = DeadlineRace<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard race.register(continuation) else { return }
                let work = Task.detached(priority: Task.currentPriority) {
                    do {
                        try Task.checkCancellation()
                        try await race.finish(.success(operation()))
                    } catch {
                        race.finish(.failure(error))
                    }
                }
                let timer = Task.detached {
                    do { try await Task.sleep(for: duration) } catch { return }
                    race.finish(.failure(OperationDeadlineError.timedOut))
                }
                race.install(work: work, timer: timer)
            }
        } onCancel: {
            race.finish(.failure(CancellationError()))
        }
    }
}

/// Completion, timeout and cancellation can race before registration or task
/// installation. All state transitions are locked; callbacks run outside it.
private final class DeadlineRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var tasks: [Task<Void, Never>] = []

    func register(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        let finished = self.lock.withLock { () -> Result<Value, Error>? in
            if let result = self.result {
                return result
            }
            self.continuation = continuation
            return nil
        }
        if let finished {
            continuation.resume(with: finished)
            return false
        }
        return true
    }

    func install(work: Task<Void, Never>, timer: Task<Void, Never>) {
        let finished = self.lock.withLock {
            guard self.result == nil else { return true }
            self.tasks = [work, timer]
            return false
        }
        if finished {
            work.cancel()
            timer.cancel()
        }
    }

    func finish(_ result: Result<Value, Error>) {
        let completion = self.lock.withLock { () -> (CheckedContinuation<Value, Error>?, [Task<Void, Never>]) in
            guard self.result == nil else { return (nil, []) }
            self.result = result
            let completion = (self.continuation, self.tasks)
            self.continuation = nil
            self.tasks = []
            return completion
        }
        for task in completion.1 {
            task.cancel()
        }
        completion.0?.resume(with: result)
    }
}
