import Library
import SwiftUI

// MARK: - LyricsSettingsView

/// Settings tab for all lyrics-related preferences.
public struct LyricsSettingsView: View {
    // MARK: - Preferences

    @AppStorage("lyrics.autoShowPane") private var autoShowPane = false
    @AppStorage("lyrics.fontSize") private var fontSizeDefault: LyricsFontSize = .medium
    @AppStorage("lyrics.sourcePriority") private var sourcePriority: LyricsSourcePriority = .preferSynced
    @AppStorage("lyrics.lrclibEnabled") private var lrclibEnabled = false
    @AppStorage("lyrics.neteaseEnabled") private var neteaseEnabled = false
    @AppStorage("lyrics.kugouEnabled") private var kugouEnabled = false
    @AppStorage("lyrics.embedOnSave") private var embedOnSave = false

    public init() {}

    // MARK: - Body

    public var body: some View {
        Form {
            Section(L10n.string("Display")) {
                Toggle(L10n.string("Show lyrics pane when a track has lyrics"), isOn: self.$autoShowPane)
                    .accessibilityIdentifier(A11y.SettingsIDs.lyricsAutoShow)
                    .help(L10n.string("Opens the pane by itself when a track has lyrics, instead of waiting for you to open it."))

                Picker(L10n.string("Default font size"), selection: self.$fontSizeDefault) {
                    ForEach(LyricsFontSize.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .help(L10n.string("The size lyrics start at. You can still change the size while a track plays."))
            }

            Section(L10n.string("Source priority")) {
                Picker(L10n.string("When multiple sources exist"), selection: self.$sourcePriority) {
                    ForEach(LyricsSourcePriority.allCases, id: \.self) { priority in
                        Text(Self.label(for: priority)).tag(priority)
                    }
                }
                .pickerStyle(.radioGroup)
                .help(L10n.string("Which lyrics win when a track has both its own and a downloaded set."))
            }

            Section(L10n.string("Online lyrics (opt-in)")) {
                Toggle(L10n.string("Fetch missing lyrics online"), isOn: self.$lrclibEnabled)
                    .accessibilityIdentifier(A11y.SettingsIDs.lyricsLrclib)
                    .help(L10n.string("Sends the song title, artist, album and duration to LRClib to find matching lyrics."))
                Toggle(L10n.string("Use NetEase Cloud Music as a fallback"), isOn: self.$neteaseEnabled)
                    .disabled(!self.lrclibEnabled)
                    .accessibilityIdentifier("settings.lyrics.netease")
                    .help(L10n.string("Sends the song title and artist to NetEase when LRClib is unavailable or has no matching lyrics."))
                Toggle(L10n.string("Use Kugou as a fallback"), isOn: self.$kugouEnabled)
                    .disabled(!self.lrclibEnabled)
                    .accessibilityIdentifier("settings.lyrics.kugou")
                    .help(L10n.string("Sends the song title, artist and duration to Kugou when other enabled sources have no matching lyrics."))
                Text(self.lrclibFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("Saving")) {
                Toggle(L10n.string("Write lyrics back into audio files when saving"), isOn: self.$embedOnSave)
                    .accessibilityIdentifier(A11y.SettingsIDs.lyricsEmbedOnSave)
                    .help(L10n.string("Embeds user-edited lyrics as USLT / Vorbis LYRICS tags. Requires file write access."))
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 400, minHeight: 340)
    }

    /// Multi-sentence footer as sentence keys joined in code (#314).
    private var lrclibFooter: String {
        L10n.string("Enabled sources are tried in order: LRClib, NetEase, then Kugou. Local files and your edits keep their existing priority.")
            + " " + L10n.string("Fetched lyrics may be copyrighted; opt-in use is your responsibility.")
    }

    /// UI-side localized labels for the Library-owned priority enum, so the
    /// Library module stays free of UI catalog lookups (#314).
    private static func label(for priority: LyricsSourcePriority) -> String {
        switch priority {
        case .preferEmbedded:
            L10n.string("Prefer embedded tags")

        case .preferSynced:
            L10n.string("Prefer synced (sidecar .lrc)")

        case .preferUser:
            L10n.string("Prefer my edits")
        }
    }
}
