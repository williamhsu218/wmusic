import SwiftUI

enum MusicSourceKind: String, CaseIterable {
    case nasFolders, musicServers
}

/// One entry point for shared music files and Subsonic-compatible services.
struct SourcesSettingsView: View {
    @Binding var kind: MusicSourceKind
    let subsonicViewModel: SubsonicSettingsViewModel?

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.string("Source Type"), selection: self.$kind) {
                Text(localized: "NAS Folders").tag(MusicSourceKind.nasFolders)
                Text(localized: "Music Servers").tag(MusicSourceKind.musicServers)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)
            .padding(16)
            .help(L10n.string("Choose shared music files on a NAS or a Subsonic-compatible streaming service"))
            .accessibilityIdentifier(A11y.SettingsIDs.sourceType)
            Divider()
            if self.kind == .nasFolders {
                NASFoldersSettingsView()
            } else if let vm = self.subsonicViewModel {
                SubsonicSettingsView(viewModel: vm)
            } else {
                ContentUnavailableView(
                    L10n.string("Sources Unavailable"), systemImage: "server.rack",
                    description: Text(localized: "Music server sources can't be configured right now.")
                )
            }
        }
    }
}
