import Foundation

/// FIFO ownership survives actor reentrancy; cancelled waiters never run later.
extension AudioEngine {
    @discardableResult
    func acquireTransport() async -> Bool {
        guard !Task.isCancelled else { return false }
        if !self.transportBusy {
            self.transportBusy = true
            return true
        }
        let id = UUID()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                self.transportWaiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelTransportWaiter(id) }
        }
        if acquired, Task.isCancelled {
            self.releaseTransport()
            return false
        }
        return acquired
    }

    private func cancelTransportWaiter(_ id: UUID) {
        guard let index = self.transportWaiters.firstIndex(where: { $0.id == id }) else { return }
        self.transportWaiters.remove(at: index).continuation.resume(returning: false)
    }

    func releaseTransport() {
        guard !self.transportWaiters.isEmpty else {
            self.transportBusy = false
            return
        }
        // Transfer ownership directly. New arrivals cannot overtake the waiter
        // in the interval between resuming it and its next executor turn.
        self.transportWaiters.removeFirst().continuation.resume(returning: true)
    }
}
