import SwiftUI

// MARK: - SourceBadgeModel

/// A source fact and its explanation, shared by the compact capsule and inspector.
///
/// Built by a pure function so the row's shape can be tested without a view
/// tree, which the host-less test bundle cannot build.
struct SourceBadgeModel: Identifiable, Equatable {
    /// The five facts, in the order the row draws them.
    enum Kind: String, CaseIterable {
        case codec, bitrate, sampleRate, bitDepth, channels
    }

    let kind: Kind
    /// The value as the listener reads it: "FLAC", "1411 kbps", "44.1 kHz".
    let text: String
    /// What the fact means, never a restatement of the value.
    let help: String

    var id: String {
        self.kind.rawValue
    }

    var tint: Color {
        .textSecondary
    }

    /// The badges to draw for `facts`, in the fixed order codec, bitrate,
    /// sample rate, bit depth, channels. A fact the decoder and the track both
    /// leave nil draws nothing, so the row shrinks rather than showing a dash.
    static func badges(for facts: NowPlayingSourceFacts) -> [Self] {
        [
            facts.codec
                .flatMap { $0.isEmpty ? nil : self.codecBadge(codec: $0, profile: facts.codecProfile) },
            facts.bitrateKbps.map(self.bitrateBadge),
            facts.sampleRateHz.map(self.sampleRateBadge),
            facts.bitDepth.map(self.bitDepthBadge),
            facts.channelCount.map(self.channelsBadge),
        ].compactMap(\.self)
    }

    /// The codec sentence carries the file's own profile when the decoder
    /// captured one (E-AC-3 says "Dolby Digital Plus + Dolby Atmos" there,
    /// which is the only place WMusic claims to know about Atmos).
    private static func codecBadge(codec: String, profile: String?) -> Self {
        var help = L10n.string(
            "How the audio is stored in the file. The name of the compression, or PCM for none."
        )
        if let profile, !profile.isEmpty {
            help += " " + L10n.string("The file declares the profile \(profile).")
        }
        return Self(kind: .codec, text: self.displayName(forCodec: codec), help: help)
    }

    private static func bitrateBadge(_ kbps: Int) -> Self {
        Self(
            kind: .bitrate,
            text: L10n.string("\(kbps) kbps"),
            help: L10n.string(
                """
                How much data the file spends per second of sound. \
                Higher is more detail for a lossy codec; for a lossless one it only follows the music.
                """
            )
        )
    }

    private static func sampleRateBadge(_ hertz: Int) -> Self {
        Self(
            kind: .sampleRate,
            text: SampleRateLabel.text(for: hertz),
            help: L10n.string(
                """
                How many samples per second the file holds. \
                44.1 kHz is CD; higher rates carry more of the top end.
                """
            )
        )
    }

    private static func bitDepthBadge(_ bits: Int) -> Self {
        Self(
            kind: .bitDepth,
            text: L10n.string("\(bits)-bit"),
            help: L10n.string(
                """
                How finely each sample is measured. \
                16 bits is CD; 24 bits gives more headroom and a lower noise floor.
                """
            )
        )
    }

    private static func channelsBadge(_ channels: Int) -> Self {
        Self(
            kind: .channels,
            text: ChannelLayoutLabel.text(for: channels),
            help: ChannelLayoutLabel.help(for: channels)
        )
    }

    /// The display name for a raw codec name from `AudioEngine`. The names are
    /// product spellings, not copy, so they are not localized (the module-owned
    /// raw-value rule); an unmapped codec shows its own name uppercased rather
    /// than nothing.
    static func displayName(forCodec raw: String) -> String {
        self.codecDisplayNames[raw.lowercased()] ?? raw.uppercased()
    }

    private static let codecDisplayNames: [String: String] = [
        "flac": "FLAC",
        "alac": "ALAC",
        "aac": "AAC",
        "mp3": "MP3",
        "mp2": "MP2",
        "pcm": "PCM",
        "opus": "Opus",
        "vorbis": "Vorbis",
        "eac3": "E-AC-3",
        "ac3": "AC-3",
        "truehd": "TrueHD",
        "dts": "DTS",
        "dsd_lsbf_planar": "DSD",
        "dsd_msbf_planar": "DSD",
        "wavpack": "WavPack",
        "ape": "APE",
        "musepack": "Musepack",
        "tta": "TTA",
        "wmav2": "WMA",
        "wmapro": "WMA",
    ]
}

// MARK: - SourceBadge

/// One capsule: the value in the tint's 14% fill, ringed by the tint itself.
/// Under increase-contrast the fill goes and the ring thickens, the same
/// trade the rest of the chrome makes.
struct SourceBadge: View {
    /// The tint's share of the capsule fill. Internal so `ContrastTests` can
    /// composite the same number over both backgrounds and audit the label
    /// on top of the result.
    static let fillOpacity = 0.14

    let model: SourceBadgeModel

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.bocanHighContrast) private var overrideHighContrast

    private var highContrast: Bool {
        self.overrideHighContrast ?? (self.colorSchemeContrast == .increased)
    }

    var body: some View {
        Text(verbatim: self.model.text)
            .font(Typography.mini)
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                Capsule(style: .continuous)
                    .fill(self.highContrast ? Color.clear : self.model.tint.opacity(Self.fillOpacity))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(self.model.tint, lineWidth: self.highContrast ? 1.5 : 1)
            }
            .help(self.model.help)
    }
}

// MARK: - SourceBadgesRow

/// One quiet quality capsule. Full source facts remain available on hover
/// and through VoiceOver, even when the compact label has to truncate.
struct SourceBadgesRow: View {
    let facts: NowPlayingSourceFacts

    private var badges: [SourceBadgeModel] {
        SourceBadgeModel.badges(for: self.facts)
    }

    var body: some View {
        let badges = self.badges
        if !badges.isEmpty {
            Text(badges.filter { [.codec, .bitDepth, .sampleRate].contains($0.kind) }.map(\.text).joined(separator: " · "))
            .font(Typography.mini)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.textSecondary.opacity(0.25)))
            .help(badges.map { $0.text + ": " + $0.help }.joined(separator: "\n"))
            .accessibilityLabel(badges.map(\.text).joined(separator: ", "))
        }
    }

}
