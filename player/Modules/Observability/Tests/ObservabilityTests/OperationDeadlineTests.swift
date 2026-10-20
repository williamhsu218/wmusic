import Foundation
import Testing
@testable import Observability

private actor DeadlineGate {
    private var waiter: CheckedContinuation<Int, Never>?
    private(set) var entered = false
    private var released = false

    func wait() async -> Int {
        self.entered = true
        if self.released {
            return 42
        }
        return await withCheckedContinuation { self.waiter = $0 }
    }

    func release() {
        self.released = true
        self.waiter?.resume(returning: 42)
        self.waiter = nil
    }
}

@Suite("Operation deadlines")
struct OperationDeadlineTests {
    @Test("timeout returns before cancellation-ignoring work, and late success is ignored")
    func uncooperativeWork() async throws {
        let gate = DeadlineGate()
        let task = Task { try await OperationDeadline.run(for: .milliseconds(50)) { await gate.wait() } }
        await #expect(throws: OperationDeadlineError.timedOut) { _ = try await task.value }
        await gate.release()
    }

    @Test("caller cancellation resumes promptly even when work does not cooperate")
    func callerCancellation() async throws {
        let gate = DeadlineGate()
        let task = Task { try await OperationDeadline.run(for: .seconds(30)) { await gate.wait() } }
        while await !gate.entered {
            await Task.yield()
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        await gate.release()
    }

    @Test("an already-cancelled caller never starts work")
    func cancelledBeforeRegistration() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await OperationDeadline.run(for: .seconds(1)) {
                Issue.record("cancelled operation must not be started")
                return 1
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test("success and failure propagate without waiting for the deadline")
    func completion() async throws {
        #expect(try await OperationDeadline.run(for: .seconds(30)) { 7 } == 7)
        await #expect(throws: URLError(.notConnectedToInternet)) {
            try await OperationDeadline.run(for: .seconds(30)) { () -> Int in
                throw URLError(.notConnectedToInternet)
            }
        }
    }
}
