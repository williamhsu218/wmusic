import Foundation
import Testing

@Suite("Asynchronous termination")
@MainActor
struct TerminationCoordinatorTests {
    @Test("main-actor saves complete before the quit reply and repeated requests coalesce")
    func savesBeforeReplyWithoutBlockingMainActor() async {
        let coordinator = TerminationCoordinator()
        var events: [String] = []
        coordinator.prepare = {
            events.append("saving")
            await Task.yield()
            events.append("saved")
        }
        coordinator.requestTermination { events.append("reply") }
        coordinator.requestTermination { events.append("duplicate") }
        // This line executes immediately; requestTermination cannot block the
        // main actor while its preparation task needs that same actor.
        #expect(events.isEmpty)
        for _ in 0 ..< 1000 where events.last != "reply" {
            await Task.yield()
        }
        #expect(events == ["saving", "saved", "reply"])
    }

    @Test("a hung save still replies at the deadline, and only once")
    func hungPreparationRepliesAtDeadline() async throws {
        let coordinator = TerminationCoordinator(deadline: .milliseconds(50))
        let (gate, release) = AsyncStream<Void>.makeStream()
        var events: [String] = []
        coordinator.prepare = {
            for await _ in gate {}
            events.append("late save")
        }
        coordinator.requestTermination { events.append("reply") }
        for _ in 0 ..< 500 where events.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(events == ["reply"])

        // Preparation finishing after the deadline must not reply a second time.
        release.finish()
        for _ in 0 ..< 500 where events.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(events == ["reply", "late save"])
    }

    @Test("quit preparation vacuums the database after saving the queue")
    func vacuumRunsAfterQueueSave() throws {
        let url = URL(filePath: #filePath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/BocanApp.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let start = try #require(source.range(of: "terminationCoordinator.prepare = {"))
        let body = source[start.upperBound...]
        let save = try #require(body.range(of: "await qp.prepareForTermination()"))
        let vacuum = try #require(body.range(of: "try await db.vacuum()"))
        #expect(save.lowerBound < vacuum.lowerBound)
    }
}
