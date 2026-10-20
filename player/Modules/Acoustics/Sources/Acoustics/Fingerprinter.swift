import Foundation
import Observability

// MARK: - Fingerprinter

/// Computes Chromaprint acoustic fingerprints by invoking the bundled `fpcalc` binary.
///
/// `fpcalc` is Chromaprint's CLI tool. We use it instead of linking `libchromaprint`
/// directly because the pre-built fat binary avoids a complex build-script dependency
/// and produces a smaller Swift package footprint. The binary is code-signed and copied
/// into the app bundle via the "Copy Files" build phase.
public actor Fingerprinter {
    private let fpcalcURL: URL
    private let log = AppLogger.make(.network)
    private let timeout: Duration

    /// - Parameter fpcalcURL: Absolute path to the `fpcalc` executable inside the app bundle.
    ///   Obtain via `Bundle.main.url(forResource: "fpcalc", withExtension: nil)`.
    public init(fpcalcURL: URL, timeout: Duration = .seconds(60)) {
        self.fpcalcURL = fpcalcURL
        self.timeout = timeout
    }

    // MARK: - Public API

    /// Computes the Chromaprint fingerprint for the audio file at `url`.
    ///
    /// Analyses up to 120 seconds of audio (sufficient for AcoustID matching).
    /// The file must be accessible at the point of the call; resolve security-scoped
    /// bookmarks before invoking this method.
    ///
    /// - Parameter url: File URL for the audio file to analyse.
    /// - Returns: `(fingerprint, duration)` where `duration` is in seconds.
    /// - Throws: `AcousticsError.fpcalcFailed` if `fpcalc` exits with a non-zero code.
    public func fingerprint(url: URL) async throws -> (fingerprint: String, duration: Int) {
        let fpcalcURL = self.fpcalcURL
        self.log.debug("fingerprinter.start", ["path": url.lastPathComponent])
        let result: (fingerprint: String, duration: Int)
        do {
            result = try await OperationDeadline.run(for: self.timeout) {
                try await Self.runFpcalc(at: fpcalcURL, fileURL: url)
            }
        } catch OperationDeadlineError.timedOut {
            throw AcousticsError.fpcalcFailed(exitCode: -1, stderr: "Fingerprinting timed out")
        }
        self.log.debug("fingerprinter.done", ["duration": result.duration])
        return result
    }

    // MARK: - Private

    private static func runFpcalc(
        at fpcalcURL: URL,
        fileURL: URL
    ) async throws -> (fingerprint: String, duration: Int) {
        guard fileURL.isFileURL else {
            throw AcousticsError.invalidInput(reason: "fpcalc requires a file URL, got: \(fileURL.scheme ?? "nil")")
        }
        let path = fileURL.path(percentEncoded: false)
        guard !path.contains("\0") else {
            throw AcousticsError.invalidInput(reason: "file path contains a NUL byte")
        }
        let process = Process()
        process.executableURL = fpcalcURL
        process.arguments = ["-json", "-length", "120", path]

        // Pipes read only after process exit can fill up and deadlock fpcalc.
        // Temporary output files avoid that backpressure and are removed on
        // every success, launch failure, cancellation and timeout path.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wmusic-fpcalc-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdoutURL = directory.appendingPathComponent("stdout")
        let stderrURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        defer { try? stdout.close() }
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer { try? stderr.close() }
        process.standardOutput = stdout
        process.standardError = stderr
        let owner = FingerprintProcess(process)
        let (exits, continuation) = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { process in
            continuation.yield(process.terminationStatus)
            continuation.finish()
        }
        let exitCode: Int32 = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try owner.run()
            for await status in exits {
                try Task.checkCancellation()
                return status
            }
            throw CancellationError()
        } onCancel: {
            owner.cancel()
        }
        guard exitCode == 0 else {
            let data = try Data(contentsOf: stderrURL)
            throw AcousticsError.fpcalcFailed(
                exitCode: exitCode,
                stderr: String(bytes: data.prefix(4096), encoding: .utf8) ?? "Unreadable fpcalc error output"
            )
        }
        let data = try Data(contentsOf: stdoutURL)
        return try self.parseFpcalcOutput(data)
    }

    static func parseFpcalcOutput(_ data: Data) throws -> (fingerprint: String, duration: Int) {
        let decoder = JSONDecoder()
        do {
            let output = try decoder.decode(FpcalcOutput.self, from: data)
            return (output.fingerprint, Int(output.duration.rounded()))
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AcousticsError.invalidResponse(reason: "fpcalc JSON parse failed: \(raw.prefix(200))")
        }
    }
}

/// Serializes cancellation against process launch. Escalation targets only the
/// owned child if it ignores SIGTERM; no global process-name kill is used.
private final class FingerprintProcess: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var cancelled = false

    init(_ process: Process) {
        self.process = process
    }

    func run() throws {
        try self.lock.withLock {
            guard !self.cancelled else { throw CancellationError() }
            try self.process.run()
        }
    }

    func cancel() {
        self.lock.withLock {
            self.cancelled = true
            if self.process.isRunning {
                self.process.terminate()
            }
        }
        Task.detached {
            try? await Task.sleep(for: .milliseconds(200))
            self.lock.withLock {
                if self.process.isRunning {
                    kill(self.process.processIdentifier, SIGKILL)
                }
            }
        }
    }
}
