import Foundation
import Library
import Persistence
import Testing
@testable import UI

@Suite("Source scan cancellation")
@MainActor
struct SourceScanCancellationTests {
    @Test("Cancel keeps source actions blocked until the scanner has stopped")
    func cancellationWaitsForScanner() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("wmusic-source-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try await Database(location: .inMemory)
        let scanner = LibraryScanner(database: database)
        try await scanner.addRoot(folder)
        let vm = LibraryViewModel(database: database, engine: MockTransport(), scanner: scanner)

        vm.rescanLibrary(mode: .quick)
        let scanTask = try #require(vm.scanTask)
        vm.cancelScan()
        #expect(vm.isScanning, "Cancelling must not allow an immediate source removal or restart")
        await scanTask.value
        #expect(!vm.isScanning)
        let rootID = try #require(try await scanner.roots().first?.id)
        try await scanner.removeRoot(id: rootID)
        #expect(try await scanner.roots().isEmpty)
        await scanner.stopWatching()
    }
}
