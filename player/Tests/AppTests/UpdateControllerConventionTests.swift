import Foundation
import Testing

/// Guards the local build against querying or installing the upstream appcast.
@Suite("UpdateController conventions")
struct UpdateControllerConventionTests {
    private func source() throws -> String {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/Updates/UpdateController.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("local builds cannot check for upstream updates")
    func updaterDisabled() throws {
        let source = try self.source()
        #expect(source.contains("canCheckForUpdates = false"))
        #expect(!source.contains("import Sparkle"))
        #expect(!source.contains("SPUStandardUpdaterController"))
    }
}
