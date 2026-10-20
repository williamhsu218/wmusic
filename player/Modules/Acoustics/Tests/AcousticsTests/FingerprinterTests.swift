import Foundation
import Testing
@testable import Acoustics

@Suite("Fingerprinter")
struct FingerprinterTests {
    private func executable(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wmusic-fpcalc-test-\(UUID())")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    @Test("large stderr cannot block a successful fingerprint subprocess")
    func drainsLargeOutput() async throws {
        let script = try self.executable("/usr/bin/head -c 262144 /dev/zero >&2\nprintf '%s' '{\"fingerprint\":\"test\",\"duration\":3}'\n")
        defer { try? FileManager.default.removeItem(at: script) }
        let result = try await Fingerprinter(fpcalcURL: script, timeout: .seconds(3)).fingerprint(url: URL(filePath: "/tmp/test.wav"))
        #expect(result.fingerprint == "test")
        #expect(result.duration == 3)
    }

    @Test("a hanging subprocess times out")
    func subprocessDeadline() async throws {
        let script = try self.executable("exec /bin/sleep 30\n")
        defer { try? FileManager.default.removeItem(at: script) }
        await #expect(throws: AcousticsError.fpcalcFailed(exitCode: -1, stderr: "Fingerprinting timed out")) {
            _ = try await Fingerprinter(fpcalcURL: script, timeout: .milliseconds(150)).fingerprint(url: URL(filePath: "/tmp/test.wav"))
        }
    }

    @Test("cancelling fingerprint work terminates its child")
    func cancellationKillsChild() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("wmusic-fpcalc-pid-\(UUID())")
        let script = try self.executable("trap '' TERM\necho $$ > '\(pidFile.path)'\nexec /bin/sleep 30\n")
        defer {
            try? FileManager.default.removeItem(at: script)
            try? FileManager.default.removeItem(at: pidFile)
        }
        let task = Task { try await Fingerprinter(fpcalcURL: script).fingerprint(url: URL(filePath: "/tmp/test.wav")) }
        for _ in 0 ..< 500 where !FileManager.default.fileExists(atPath: pidFile.path) {
            try await Task.sleep(for: .milliseconds(5))
        }
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        for _ in 0 ..< 100 where kill(pid, 0) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(kill(pid, 0) == -1)
    }

    // MARK: - fpcalc output parsing

    @Test("parseFpcalcOutput decodes valid JSON")
    func parsesValidJSON() throws {
        let json = #"{"fingerprint":"AQAAZ0mkUYpGHQ==","duration":259}"#
        let data = Data(json.utf8)
        let (fingerprint, duration) = try Fingerprinter.parseFpcalcOutput(data)
        #expect(fingerprint == "AQAAZ0mkUYpGHQ==")
        #expect(duration == 259)
    }

    @Test("parseFpcalcOutput throws invalidResponse on garbage input")
    func throwsOnGarbage() {
        let data = Data("not json at all".utf8)
        #expect(throws: AcousticsError.self) {
            try Fingerprinter.parseFpcalcOutput(data)
        }
    }

    @Test("parseFpcalcOutput throws invalidResponse on empty data")
    func throwsOnEmpty() {
        #expect(throws: AcousticsError.self) {
            try Fingerprinter.parseFpcalcOutput(Data())
        }
    }

    @Test("parseFpcalcOutput round-trips a known fingerprint")
    func roundTrip() throws {
        let expected = "AQAAkklSRUmSREmUREmUREmUREmUREmU"
        let json = "{\"fingerprint\":\"\(expected)\",\"duration\":180}"
        let (fp, dur) = try Fingerprinter.parseFpcalcOutput(Data(json.utf8))
        #expect(fp == expected)
        #expect(dur == 180)
    }

    // MARK: - Input validation (#294)

    @Test("non-file URL throws invalidInput before touching fpcalc")
    func nonFileURLThrows() async throws {
        let fpcalc = URL(fileURLWithPath: "/nonexistent/fpcalc")
        let fingerprinter = Fingerprinter(fpcalcURL: fpcalc)
        let httpsURL = try #require(URL(string: "https://example.com/audio.mp3"))
        await #expect(throws: AcousticsError.invalidInput(reason: "fpcalc requires a file URL, got: https")) {
            try await fingerprinter.fingerprint(url: httpsURL)
        }
    }

    @Test("path containing NUL byte throws invalidInput before touching fpcalc")
    func nulBytePathThrows() async {
        let fpcalc = URL(fileURLWithPath: "/nonexistent/fpcalc")
        let fingerprinter = Fingerprinter(fpcalcURL: fpcalc)
        // Build a URL whose decoded path contains a NUL via percent-encoding.
        // URL(fileURLWithPath:) rejects embedded NUL in a String literal, so we
        // construct the path programmatically.
        var pathWithNul = "/tmp/audio"
        pathWithNul.append(Character(UnicodeScalar(0)))
        pathWithNul.append(contentsOf: ".mp3")
        let nulURL = URL(fileURLWithPath: pathWithNul)
        await #expect(throws: AcousticsError.invalidInput(reason: "file path contains a NUL byte")) {
            try await fingerprinter.fingerprint(url: nulURL)
        }
    }

    // MARK: - Non-zero exit code

    @Test("fpcalcFailed is thrown when fpcalc binary is absent")
    func throwsWhenFpcalcMissing() async {
        let missingURL = URL(fileURLWithPath: "/nonexistent/fpcalc")
        let fingerprinter = Fingerprinter(fpcalcURL: missingURL)
        let audioURL = URL(fileURLWithPath: "/tmp/test.mp3")
        await #expect(throws: (any Error).self) {
            try await fingerprinter.fingerprint(url: audioURL)
        }
    }
}
