import Foundation

/// The single source of truth for the `User-Agent` header on every first-party
/// WMusic HTTP request (feed fetches, podcast search, artwork, MusicBrainz, Cover
/// Art Archive, AcoustID, LRClib, episode downloads).
///
/// Design rules, applied consistently everywhere:
/// - The version is the app's real marketing version (`CFBundleShortVersionString`),
///   read at runtime, never hardcoded.
/// - It points at the open-source project this local build is based on, rather
///   than claiming to be the official Bòcan app or its website.
/// - The product token is ASCII `WMusic`. HTTP header field values are
///   US-ASCII (RFC 9110), so it survives strict servers and proxies.
/// - The shape is `Name/Version ( contact )`, which satisfies the MusicBrainz /
///   Cover Art Archive User-Agent policy, so one string is valid for every caller.
public enum UserAgent {
    /// The app's marketing version, e.g. "1.10.0".
    ///
    /// Falls back to "dev" outside an app bundle (unit tests, SwiftUI previews),
    /// so the token is never an empty or "0" version.
    public static let appVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    /// The canonical `User-Agent` header value for all first-party requests.
    ///
    /// Example: `WMusic/0.1.0 ( https://github.com/bocan/bocan-music )`.
    public static let string =
        "WMusic/\(Self.appVersion) ( https://github.com/bocan/bocan-music )"
}
