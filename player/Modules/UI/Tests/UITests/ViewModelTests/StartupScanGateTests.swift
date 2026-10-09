import Foundation
import Library
import Persistence
import Testing
@testable import UI

/// A main window may be destroyed and recreated while the app keeps its shared
/// LibraryViewModel. Reopening it must not enumerate every library root again,
/// while an explicit File-menu rescan must still work.
@Suite("Startup scan gate")
@MainActor
struct StartupScanGateTests {
    @Test("reopening a window skips the completed startup scan, but manual rescan still runs")
    func completedStartupScanIsNotRepeated() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("wmusic-startup-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let database = try await Database(location: .inMemory)
        let scanner = LibraryScanner(database: database)
        try await scanner.addRoot(folder)
        let maintenance = PendingMaintenanceRepository(database: database)
        #expect(try await maintenance.hasRequest(task: PendingMaintenance.Task.fullRescan))
        let vm = LibraryViewModel(database: database, engine: MockTransport(), scanner: scanner)

        vm.triggerStartupScanIfNeeded()
        // The trigger sets this synchronously, before the real scanner task
        // starts. A no-op implementation cannot pass by merely setting a flag.
        #expect(vm.isScanning)
        try await self.waitForScanToFinish(vm)
        #expect(
            try await !maintenance.hasRequest(task: PendingMaintenance.Task.fullRescan),
            "The real scanner must finish the migration-requested pass"
        )
        #expect(vm.scanSummary == nil, "An empty automatic startup scan should be silent")

        vm.triggerStartupScanIfNeeded()
        #expect(!vm.isScanning, "A second main-window mount must not start another scan")
        #expect(vm.scanSummary == nil, "No second scan should publish a summary")

        vm.rescanLibrary(mode: .quick)
        #expect(vm.isScanning, "The startup gate must not block a user-requested rescan")
        try await self.waitForScanToFinish(vm)
        #expect(vm.scanSummary != nil)
        await scanner.stopWatching()
    }

    private func waitForScanToFinish(_ vm: LibraryViewModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while vm.isScanning && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!vm.isScanning, "The fixture scan did not finish")
        if let task = vm.scanTask {
            await task.value
        }
    }
}
