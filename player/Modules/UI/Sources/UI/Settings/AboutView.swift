import SwiftUI

// MARK: - AboutView

public struct AboutView: View {
    private let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    private let build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"

    private let onCheckForUpdates: () -> Void
    private let canCheckForUpdates: Bool

    public init(onCheckForUpdates: @escaping () -> Void = {}, canCheckForUpdates: Bool = true) {
        self.onCheckForUpdates = onCheckForUpdates
        self.canCheckForUpdates = canCheckForUpdates
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text(verbatim: "WMusic")
                    .font(.title.bold())
                Text(localized: "Version \(self.version) (\(self.build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(localized: "A thoughtful local music player for macOS.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text(localized: "Based on Bòcan by Chris Funderburg (Apache 2.0).")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if self.canCheckForUpdates {
                Button(L10n.string("Check for Updates\u{2026}")) {
                    self.onCheckForUpdates()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(localized: "Third-Party Notices")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                NoticesHTMLView()
                    .frame(maxHeight: 160)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(L10n.string("About"))
    }
}
