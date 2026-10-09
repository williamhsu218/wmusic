import Foundation
import Testing
@testable import Library

// IPv4 fixtures use documentation-only TEST-NET ranges; never use a real NAS address.
@Suite("NetworkShareAddress")
struct NetworkShareAddressTests {
    @Test(arguments: [
        "smb://192.0.2.1",
        "192.0.2.1",
        "smb://192.0.2.1/",
        "smb://198.51.100.1",
        "203.0.113.1",
        "my-synology",
        "my-synology.tailnet-name.ts.net",
        "smb://my-synology.tailnet-name.ts.net/",
        "smb://[2001:db8::1]",
        "[2001:db8::1]:1445/",
        "smb://[fe80::1%25en0]/",
    ])
    func connectsToServerBeforeChoosingShare(_ input: String) throws {
        let url = try NetworkShareAddress.connectionURL(for: input)
        #expect(url.scheme == "smb")
        #expect(url.host?.isEmpty == false)
        #expect(url.path.isEmpty)
        #expect(url.user == nil)
        #expect(url.password == nil)
        #expect(url.query == nil)
        #expect(url.fragment == nil)
        // A connection target alone is not an indexed, mounted music source.
        #expect(throws: NetworkShareAddressError.self) { try NetworkShareAddress(input) }
        #expect(NetworkShareAddress.sanitized(url) == nil)
    }

    @Test func connectsToDocumentationIPv4Address() throws {
        let url = try NetworkShareAddress.connectionURL(for: "smb://192.0.2.1")
        #expect(url.absoluteString == "smb://192.0.2.1")
    }

    @Test(arguments: [
        "smb://192.0.2.1/music",
        "203.0.113.1/music/Albums/",
        "my-synology.tailnet-name.ts.net/音乐 文件",
        "smb://[2001:db8::1]:1445/music",
    ])
    func shareConnectionUsesTheSameValidationAsSavedSources(_ input: String) throws {
        #expect(try NetworkShareAddress.connectionURL(for: input) == NetworkShareAddress(input).url)
    }

    @Test(arguments: [
        "", "smb:///", "file:///Volumes/music", "https://192.0.2.1",
        "smb://nas local", "smb://[invalid]", "smb://ho%40st",
        "smb://alice@192.0.2.1", "smb://alice:secret@192.0.2.1/",
        "smb://192.0.2.1:0", "smb://192.0.2.1:65536", "smb://192.0.2.1:/",
        "smb://192.0.2.1:wrong", "smb://192.0.2.1?user=alice", "smb://192.0.2.1#music",
        "smb://192.0.2.1/music?", "smb://192.0.2.1/music#",
        "smb://192.0.2.1/..", "smb://192.0.2.1/music/../other",
        "smb://192.0.2.1/%2e%2e/music", "smb://192.0.2.1/music%2f..",
        "smb://192.0.2.1/music%5c..", "smb://192.0.2.1/music/%00",
    ])
    func connectionStillRejectsUnsafeAddresses(_ input: String) {
        #expect(throws: NetworkShareAddressError.self) {
            try NetworkShareAddress.connectionURL(for: input)
        }
    }

    @Test(arguments: [
        "smb://nas.local/music",
        "nas.local/music",
        "//nas.local/music",
        "  SMB://192.0.2.2/music/Albums/  ",
        "smb://群晖.local/音乐 文件/古典 音乐",
        "smb://[2001:db8::1]:1445/music",
        "smb://[fe80::1%25en0]/音乐",
    ])
    func acceptsServerAndShare(_ input: String) throws {
        let address = try NetworkShareAddress(input)
        #expect(address.url.scheme == "smb")
        #expect(address.url.user == nil)
        #expect(address.url.password == nil)
        #expect(!address.shareName.isEmpty)
    }

    @Test func preservesReadableUnicodeAndSpaces() throws {
        let address = try NetworkShareAddress("smb://群晖.local/音乐 文件/古典 音乐")
        #expect(address.shareName == "音乐 文件")
        #expect(address.displayString == "smb://群晖.local/音乐 文件/古典 音乐")
        #expect(address.url.absoluteString.contains("%20"))
        #expect(address.url.path == "/音乐 文件/古典 音乐")
    }

    @Test func normalizesEncodedPathAndTrailingSlash() throws {
        let address = try NetworkShareAddress("smb://nas/music%20files/Albums/")
        #expect(address.url.absoluteString == "smb://nas/music%20files/Albums")
        #expect(address.displayString == "smb://nas/music files/Albums")
    }

    @Test(arguments: [
        "", "nas.local", "smb://nas.local/", "smb:///music",
        "https://nas.local/music", "file:///Volumes/music",
        "smb://nas local/music", "smb://ho%40st/music", "smb://[invalid]/music",
        "smb://nas:0/music", "smb://nas:65536/music", "smb://nas:/music",
        "smb://nas:wrong/music", "smb://nas/music?download=1", "smb://nas/music#folder",
        "smb://nas/music?", "smb://nas/music#",
        "smb://nas/../music", "smb://nas/music/..", "smb://nas/music/./Albums",
        "smb://nas/%2e%2E/music", "smb://nas/music%2f..",
        "smb://nas/music%5C..", "smb://nas/music//Albums", "smb://nas//music",
        "smb://nas/music/%00",
    ])
    func rejectsUnsafeOrIncompleteAddresses(_ input: String) {
        #expect(throws: NetworkShareAddressError.self) {
            try NetworkShareAddress(input)
        }
    }

    @Test(arguments: [
        "smb://alice@nas/music",
        "smb://alice:secret@nas/music",
        "smb://alice%40domain:secret%40word@nas/music",
        "smb://@nas/music",
    ])
    func rejectsCredentialsWithoutIncludingThemInErrors(_ input: String) {
        do {
            _ = try NetworkShareAddress(input)
            Issue.record("An address containing credentials was accepted")
        } catch let error as NetworkShareAddressError {
            #expect(error == .containsCredentials)
            #expect(!error.localizedDescription.contains("alice"))
            #expect(!error.localizedDescription.contains("secret"))
            #expect(!error.localizedDescription.contains(input))
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func sanitizesRemountURLBeforeRetainingIt() throws {
        let remount = try #require(URL(string: "smb://alice%40domain:secret%40word@nas.local:445/音乐"))
        let address = try #require(NetworkShareAddress.sanitized(remount))
        #expect(address.url.user == nil)
        #expect(address.url.password == nil)
        #expect(address.displayString == "smb://nas.local:445/音乐")
        #expect(!address.url.absoluteString.contains("alice"))
        #expect(!address.url.absoluteString.contains("secret"))
    }

    @Test(arguments: [
        "file:///Volumes/music", "smb://alice@nas/", "smb://alice@nas/music/..",
        "smb://alice@nas/music?secret=value",
    ])
    func sanitizationStillValidatesLocation(_ input: String) throws {
        let url = try #require(URL(string: input))
        #expect(NetworkShareAddress.sanitized(url) == nil)
    }

    @Test func matchesMountedShareForRequestedSubfolder() throws {
        let address = try NetworkShareAddress("smb://NAS.local/音乐/古典 音乐")
        let remount = try #require(URL(string: "smb://alice@nas.local:445/音乐"))
        #expect(address.matchesVolume(remount))
    }

    @Test(arguments: [
        "smb://other.local/music", "smb://nas.local:1445/music", "smb://nas.local/other",
        "file:///Volumes/music",
    ])
    func doesNotMatchAnotherMountedShare(_ input: String) throws {
        let address = try NetworkShareAddress("smb://nas.local/music/Albums")
        let remount = try #require(URL(string: input))
        #expect(!address.matchesVolume(remount))
    }
}
