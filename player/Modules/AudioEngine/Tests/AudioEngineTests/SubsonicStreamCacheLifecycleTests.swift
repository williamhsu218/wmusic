import Foundation
import Testing
@testable import AudioEngine

private actor CacheCompletionProbe {
    private(set) var count = 0

    func completed() {
        self.count += 1
    }
}

private actor CacheURLGate {
    private var continuation: CheckedContinuation<URL, Error>?
    private(set) var entered = false

    func wait() async throws -> URL {
        self.entered = true
        return try await withCheckedThrowingContinuation { self.continuation = $0 }
    }

    func release(_ result: Result<URL, Error>) {
        self.continuation?.resume(with: result)
        self.continuation = nil
    }
}

@Suite("SubsonicStreamCache lifecycle")
struct SubsonicStreamCacheLifecycleTests {
    @Test("a file larger than the cache budget remains readable when returned")
    func oversizedDownloadRemainsReadable() async throws {
        let dir = try makeStreamCacheTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = Data([1, 2, 3, 4])
        let cache = try SubsonicStreamCache(
            configuration: .init(rootDirectory: dir, budgetBytes: 2),
            loader: RemoteTrackLoader(transport: StreamCacheTestTransport(script: .init(chunks: [data])))
        )
        let url = try await cache.url(for: makeStreamCacheTestKey()) { streamCacheTestURL() }
        #expect(try Data(contentsOf: url) == data)
    }

    @Test("a body with no further chunks times out and removes its partial file")
    func stalledBodyTimesOut() async throws {
        let dir = try makeStreamCacheTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let transport = StreamCacheTestTransport(script: .init(chunks: [Data([1])]), gated: true)
        let cache = try SubsonicStreamCache(
            configuration: .init(rootDirectory: dir, stallTimeout: .milliseconds(100)),
            loader: RemoteTrackLoader(transport: transport)
        )
        let key = makeStreamCacheTestKey()
        await #expect(throws: RemoteTrackLoaderError.self) {
            _ = try await cache.url(for: key) { streamCacheTestURL() }
        }
        await transport.finishGate()
        #expect(await cache.entryCount() == 0)
        #expect(!FileManager.default
            .fileExists(atPath: dir.appendingPathComponent(key.serverID.uuidString).appendingPathComponent(key.cacheFilename).path))
    }

    @Test("steady progress refreshes the stall deadline for a long transfer")
    func progressRefreshesDeadline() async throws {
        let dir = try makeStreamCacheTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let transport = StreamCacheTestTransport(script: .init(chunks: Array(repeating: Data([1]), count: 5)), gated: true)
        let cache = try SubsonicStreamCache(
            configuration: .init(rootDirectory: dir, stallTimeout: .milliseconds(250)),
            loader: RemoteTrackLoader(transport: transport)
        )
        let downloading = Task { try await cache.url(for: makeStreamCacheTestKey()) { streamCacheTestURL() } }
        for _ in 0 ..< 5 {
            try await Task.sleep(for: .milliseconds(75))
            await transport.releaseChunk()
        }
        let url = try await downloading.value
        await transport.finishGate()
        #expect(try Data(contentsOf: url).count == 5)
    }

    @Test("successful URL signing starts a fresh deadline for the response")
    func signingProgressRefreshesDeadline() async throws {
        let dir = try makeStreamCacheTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let transport = StreamCacheTestTransport(script: .init(chunks: [Data([1])]), gated: true)
        let cache = try SubsonicStreamCache(
            configuration: .init(rootDirectory: dir, stallTimeout: .milliseconds(500)),
            loader: RemoteTrackLoader(transport: transport)
        )
        let downloading = Task {
            try await cache.url(for: makeStreamCacheTestKey()) {
                try await Task.sleep(for: .milliseconds(300))
                return streamCacheTestURL()
            }
        }
        while await transport.requestCount == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(300))
        await transport.releaseChunk()
        let url = try await downloading.value
        await transport.finishGate()
        #expect(try Data(contentsOf: url) == Data([1]))
    }

    @Test("a stalled URL signer times out and its late failure cannot delete a successful retry")
    func timeoutAndLateFailure() async throws {
        let dir = try makeStreamCacheTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try SubsonicStreamCache(
            configuration: .init(rootDirectory: dir, stallTimeout: .milliseconds(100)),
            loader: RemoteTrackLoader(transport: StreamCacheTestTransport(script: .init(chunks: [Data([1, 2, 3])])))
        )
        let gate = CacheURLGate()
        let key = makeStreamCacheTestKey()
        await #expect(throws: RemoteTrackLoaderError.self) {
            _ = try await cache.url(for: key) { try await gate.wait() }
        }
        #expect(await cache.entryCount() == 0)
        let retry = try await cache.url(for: key) { streamCacheTestURL() }
        await gate.release(.failure(RemoteTrackLoaderError.unauthorized))
        try await Task.sleep(for: .milliseconds(30))
        #expect(await cache.contains(key))
        #expect(try Data(contentsOf: retry) == Data([1, 2, 3]))
    }

    @Test("cancelling one waiter keeps a shared download alive for the other")
    func cancelOneOfTwoWaiters() async throws {
        let dir = try makeStreamCacheTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = try SubsonicStreamCache(
            configuration: .init(rootDirectory: dir),
            loader: RemoteTrackLoader(transport: StreamCacheTestTransport(script: .init(chunks: [Data([1])])))
        )
        let gate = CacheURLGate()
        let key = makeStreamCacheTestKey()
        let first = Task { try await cache.url(for: key) { try await gate.wait() } }
        while await !gate.entered {
            await Task.yield()
        }
        let second = Task { try await cache.url(for: key) { streamCacheTestURL() } }
        while await cache.waitingRequestCount(for: key) < 2 {
            await Task.yield()
        }
        first.cancel()
        await #expect(throws: CancellationError.self) { _ = try await first.value }
        await gate.release(.success(streamCacheTestURL()))
        let url = try await second.value
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(await cache.waitingRequestCount(for: key) == 0)
    }

    @Test("a URL-provider failure resumes every concurrent waiter")
    func providerFailureResumesAllWaiters() async throws {
        let dir = try makeStreamCacheTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let transport = StreamCacheTestTransport(script: .init(chunks: [Data([1])]))
        let cache = try SubsonicStreamCache(configuration: .init(rootDirectory: dir), loader: RemoteTrackLoader(transport: transport))
        let key = makeStreamCacheTestKey()
        let (gate, release) = AsyncStream<Void>.makeStream()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let probe = CacheCompletionProbe()
        let first = Task {
            do {
                _ = try await cache.url(for: key) {
                    signal.yield(())
                    for await _ in gate {
                        break
                    }
                    throw RemoteTrackLoaderError.unauthorized
                }
            } catch { await probe.completed() }
        }
        for await _ in started {
            break
        }
        let second = Task {
            do { _ = try await cache.url(for: key) { streamCacheTestURL() } } catch { await probe.completed() }
        }
        try await Task.sleep(for: .milliseconds(50))
        release.finish()
        await first.value
        for _ in 0 ..< 100 where await probe.count < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await probe.count == 2)
        #expect(await cache.entryCount() == 0)
        signal.finish()
        second.cancel()
    }
}
