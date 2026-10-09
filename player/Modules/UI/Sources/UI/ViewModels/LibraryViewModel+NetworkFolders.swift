import AppKit
import Library

extension LibraryViewModel {
    /// The open panel grants persistent sandbox access; an SMB address alone
    /// cannot grant access to files on the mounted share.
    func addNetworkFolderByPicker() async throws -> Bool {
        guard let scanner else { return false }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        panel.message = L10n.string("Choose a music folder on your connected NAS. Connect the SMB share first if it is not listed.")
        panel.prompt = L10n.string("Add")
        guard await Self.runOpenPanelAsync(panel) == .OK, let url = panel.url else { return false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeURLForRemountingKey])
        guard values.volumeIsLocal == false,
              let remountURL = values.volumeURLForRemounting,
              NetworkShareAddress.sanitized(remountURL) != nil else {
            throw NetworkFolderSelectionError.notSMBFolder
        }
        try await scanner.addRoot(url)
        await self.refreshRoots()
        self.rescanLibrary(mode: .quick)
        return true
    }
}

enum NetworkFolderSelectionError: LocalizedError {
    case notSMBFolder

    var errorDescription: String? {
        L10n.string("Choose a folder on an SMB share. Use Add Folder in Library for local folders.")
    }
}
