import Foundation
import Testing
@testable import AudioEngine
@testable import Playback

private actor HeldPrefetch {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var finished = false
    private(set) var stopReturned = false

    func hold() async {
        self.started = true
        self.startWaiters.forEach { $0.resume() }
        self.startWaiters.removeAll()
        await withCheckedContinuation { self.releaseWaiter = $0 }
    }

    func waitUntilStarted() async {
        guard !self.started else { return }
        await withCheckedContinuation { self.startWaiters.append($0) }
    }

    func release() {
        self.releaseWaiter?.resume()
        self.releaseWaiter = nil
    }

    func markFinished() { self.finished = true }
    func markStopReturned() { self.stopReturned = true }
}

@Suite("Gapless cancellation regression")
struct GaplessCancellationTests {
    @Test("stop joins an opening preload and cancels its late arm without reloading current")
    func stopJoinsInFlightPrefetch() async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Fixtures/gapless-a.flac")
        let engine = AudioEngine()
        try await engine.load(fixture)
        let originalTime = await engine.currentTime
        let originalDuration = await engine.duration
        let originalState = await engine._state
        let gate = HeldPrefetch()
        let scheduler = GaplessScheduler(engine: engine, crossfade: CrossfadeScheduler())
        let next = QueueItem(
            trackID: 99, bookmark: nil, fileURL: fixture.absoluteString, duration: originalDuration,
            sourceFormat: AudioSourceFormat(
                sampleRate: 44100, bitDepth: 16, channelCount: 2, isInterleaved: false, codec: "flac"
            )
        )
        await scheduler.configure(
            nextItemProvider: { (next, .gapless(forceGapless: true)) },
            performPrefetch: { _, _ in
                await gate.hold()
                // Simulate a decoder open which cannot abort synchronously.
                // It can finish arming after its caller's polling task is cancelled.
                let arm = Task.detached {
                    try await engine.enableGaplessNext(url: fixture, onTransition: {})
                }
                _ = try await arm.value
                await gate.markFinished()
            },
            onPrefetchFailed: { _ in Issue.record("Fixture prefetch failed") }
        )
        await scheduler.start()
        await gate.waitUntilStarted()
        let stopping = Task {
            await scheduler.stop()
            await gate.markStopReturned()
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(await gate.stopReturned == false)
        await gate.release()
        await stopping.value
        #expect(await gate.finished)
        #expect(await gate.stopReturned)
        #expect(await engine.pendingNextPump == nil)
        #expect(await engine.pendingNextDecoder == nil)
        #expect(await engine.pendingCrossfade == nil)
        #expect(await engine.currentURL == fixture)
        #expect(await engine.currentTime == originalTime)
        #expect(await engine.duration == originalDuration)
        #expect(await engine._state == originalState)
        await engine.stop()
    }
}
