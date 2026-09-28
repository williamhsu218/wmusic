import Foundation
import Testing
@testable import Observability

@Suite("UserAgent")
struct UserAgentTests {
    @Test("UA starts with the ASCII WMusic product token and the app version")
    func productToken() {
        #expect(UserAgent.string.hasPrefix("WMusic/\(UserAgent.appVersion)"))
    }

    @Test("UA references its open-source foundation without the upstream website")
    func pointsAtSource() throws {
        let ua = UserAgent.string
        #expect(ua.contains("https://github.com/bocan/bocan-music"))
        #expect(!ua.contains("https://bocan.app"))
    }

    @Test("UA never references cloudcauldron or the old Podcast-Reader token")
    func noLegacyReferences() {
        #expect(!UserAgent.string.contains("cloudcauldron"))
        #expect(!UserAgent.string.contains("Podcast-Reader"))
    }

    @Test("UA is pure ASCII so it survives HTTP header transport")
    func isASCII() {
        let allASCII = UserAgent.string.allSatisfy(\.isASCII)
        #expect(allASCII)
        // The upstream accented display name must not leak onto the wire.
        #expect(!UserAgent.string.contains("Bòcan"))
    }

    @Test("UA follows the Name/Version ( contact ) shape required by MusicBrainz")
    func musicBrainzShape() {
        let ua = UserAgent.string
        #expect(ua.contains("/"))
        #expect(ua.contains(" ( "))
        #expect(ua.hasSuffix(" )"))
    }
}
