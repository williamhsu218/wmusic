import AppKit
import Library
import SwiftUI

struct NASFoldersSettingsView: View {
    @EnvironmentObject private var vm: LibraryViewModel
    @State private var addressText = ""
    @State private var isChoosing = false
    @State private var message: String?
    @State private var error: String?
    @State private var removal: NetworkFolderSource?

    private var folders: [NetworkFolderSource] {
        self.vm.networkFolders
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.string("Music on your Synology or NAS"), systemImage: "externaldrive.connected.to.line.below")
                        .font(.headline)
                    Text(localized: "Connect an SMB share, then choose its music folder. Songs appear in your library without copying the audio files to this Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(localized: "1. Connect your NAS").font(.headline)
                        TextField(
                            L10n.string("Server Address"), text: self.$addressText,
                            prompt: Text(localized: "NAS server address")
                        )
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .autocorrectionDisabled(true)
                        .help(L10n.string("Enter a LAN IP, Tailscale IP, or hostname. A share name is optional."))
                        .accessibilityIdentifier(A11y.SettingsIDs.nasAddress)
                        Text(localized: "Use a LAN IP, Tailscale IP, or device name, with or without smb://. You can choose the shared folder after connecting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(L10n.string("Connect in Finder…")) { self.connect() }
                                .disabled(self.addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .help(L10n.string("Connect to this server in macOS, then choose a shared folder and sign in"))
                                .accessibilityIdentifier(A11y.SettingsIDs.nasConnect)
                            Text(localized: "Sign in using the macOS window. WMusic does not store your NAS password.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        HStack {
                            Text(localized: "2. Add the music folder").font(.headline)
                            Spacer()
                            Button(L10n.string("Choose NAS Folder…")) { self.chooseFolder() }
                                .disabled(self.isChoosing || self.vm.isScanning)
                                .help(L10n.string("Choose a folder on an already connected SMB share and import its music"))
                                .accessibilityIdentifier(A11y.SettingsIDs.nasChooseFolder)
                        }
                    }
                    .padding(6)
                }

                if let error = self.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let message = self.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text(localized: "NAS Music Folders").font(.headline)
                    Spacer()
                    if self.vm.isScanning {
                        ProgressView().controlSize(.small)
                        Button(L10n.string("Cancel")) { self.vm.cancelScan() }
                            .help(L10n.string("Cancel the in-progress library scan"))
                    } else {
                        Button(L10n.string("Rescan")) { self.vm.rescanLibrary(mode: .quick) }
                            .disabled(self.folders.isEmpty)
                            .help(L10n.string("Check connected music folders for new or changed files"))
                            .accessibilityIdentifier(A11y.SettingsIDs.nasRescan)
                    }
                }

                if self.folders.isEmpty {
                    ContentUnavailableView(
                        L10n.string("No NAS Folders Added"), systemImage: "externaldrive",
                        description: Text(localized: "Already connected in Finder? Choose NAS Folder to add your music.")
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(self.folders) { source in
                            self.folderRow(source)
                            Divider()
                        }
                    }
                }
                Text(localized: "After reconnecting a share, click Rescan. Availability reflects the last scan. NAS folders may need a manual rescan to pick up remote changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .task { await self.vm.refreshRoots() }
        .confirmationDialog(
            L10n.string("Remove NAS folder from library?"),
            isPresented: Binding(get: { self.removal != nil }, set: { if !$0 { self.removal = nil } }),
            titleVisibility: .visible
        ) {
            if let source = self.removal {
                Button(L10n.string("Remove from Library"), role: .destructive) {
                    guard !self.vm.isScanning else { return }
                    Task { await self.vm.removeRoot(id: source.id) }
                    self.removal = nil
                }
                .disabled(self.vm.isScanning)
                .help(L10n.string("Remove this folder from the library without deleting music files"))
            }
            Button(L10n.string("Cancel"), role: .cancel) { self.removal = nil }
                .help(L10n.string("Keep this NAS folder in the library"))
        } message: {
            Text(localized: "This removes the folder's songs from the library. Music files on the NAS are kept.")
        }
    }

    private func folderRow(_ source: NetworkFolderSource) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.connected.to.line.below").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                Text(source.address.displayString).font(.caption).foregroundStyle(.secondary)
                Text(source.root.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Label(
                    source.root.isInaccessible ? L10n.string("Unavailable at last scan") : L10n.string("Available at last scan"),
                    systemImage: source.root.isInaccessible ? "exclamationmark.triangle" : "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(source.root.isInaccessible ? Color.orange : Color.secondary)
            }
            Spacer()
            Button(L10n.string("Reconnect…")) { self.open(source.address) }
                .help(L10n.string("Reconnect this SMB share in Finder, then rescan"))
                .accessibilityIdentifier(A11y.SettingsIDs.nasReconnect)
            Button(role: .destructive) { self.removal = source } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(self.vm.isScanning)
            .help(L10n.string("Remove this folder from the library without deleting music files"))
            .accessibilityLabel(L10n.string("Remove NAS folder"))
        }
        .padding(.vertical, 4)
    }

    private func connect() {
        do {
            self.open(try NetworkShareAddress.connectionURL(for: self.addressText))
        } catch {
            self.message = nil
            self.error = L10n.string("Enter a server IP or hostname, optionally followed by a shared folder. Use SMB for music files and enter credentials only in the macOS connection window.")
        }
    }

    private func open(_ address: NetworkShareAddress) {
        self.open(address.url)
    }

    private func open(_ url: URL) {
        self.error = nil
        if NSWorkspace.shared.open(url) {
            self.message = L10n.string("Choose a shared folder and sign in through macOS, then return here to choose your music folder.")
        } else {
            self.message = nil
            self.error = L10n.string("macOS could not open the SMB connection. Try connecting from Finder's Go → Connect to Server menu.")
        }
    }

    private func chooseFolder() {
        self.isChoosing = true
        self.error = nil
        self.message = nil
        Task {
            defer { self.isChoosing = false }
            do {
                if try await self.vm.addNetworkFolderByPicker() {
                    self.message = L10n.string("NAS folder added. Its music is being scanned into your library.")
                }
            } catch {
                self.error = L10n.string("Could not add the NAS folder: \(error.localizedDescription)")
            }
        }
    }
}
