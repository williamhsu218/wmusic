import Foundation
import Network
import Observability

/// Owns the `NWListener` for the Phone Sync server: builds the mutual-TLS
/// parameters from the `ServerIdentity`, accepts connections, and hands each to
/// an `HttpConnection`. The full server lifecycle (Bonjour, pairing-mode toggle,
/// sleep/wake) is assembled in ADR-067; this type is the transport core it
/// composes.
public actor SyncListener {
    /// The Bonjour service type for Phone Sync (sync-protocol.md section 1).
    static let serviceType = "_bocansync._tcp"

    private let identity: ServerIdentity
    private let router: Router
    private let trusted: TrustedFingerprintSet
    private let pairingMode: @Sendable () -> Bool
    private let serviceName: @Sendable () -> String
    private let log = AppLogger.make(.sync)
    private let queue = DispatchQueue(label: "com.willhsu.wmusic.local.sync.listener")
    private var listener: NWListener?
    private var listenerID: UUID?
    private var connections: [UUID: NWConnection] = [:]

    var connectionCount: Int {
        self.connections.count
    }

    private var advertise = false
    private var fingerprint: String?
    /// A browser started alongside advertising purely to raise the macOS Local Network
    /// permission prompt. On macOS 15 and later a sandboxed server that only advertises is
    /// never prompted (the prompt fires on browsing or outbound local access), so without
    /// this the Bonjour advertisement is silently suppressed and no phone can discover the
    /// Mac. Browsing triggers the prompt; once the user allows it, the advertisement is
    /// published. Its results are ignored.
    private var permissionBrowser: NWBrowser?

    init(
        identity: ServerIdentity,
        router: Router,
        trusted: TrustedFingerprintSet,
        pairingMode: @escaping @Sendable () -> Bool,
        serviceName: @escaping @Sendable () -> String = { Host.current().localizedName ?? "WMusic" }
    ) {
        self.identity = identity
        self.router = router
        self.trusted = trusted
        self.pairingMode = pairingMode
        self.serviceName = serviceName
    }

    /// Starts the listener on `port` (an ephemeral port when `nil`) and returns
    /// the actual bound port. When `advertise` is true, the listener also
    /// advertises `_bocansync._tcp` over Bonjour.
    func start(port: UInt16? = nil, advertise: Bool = false) async throws -> UInt16 {
        try Task.checkCancellation()
        let loaded = try await self.identity.load()
        try Task.checkCancellation()
        self.fingerprint = loaded.fingerprint.hex
        self.advertise = advertise
        let trusted = self.trusted
        let isTrusted: @Sendable (String) -> Bool = { trusted.contains($0) }

        let tlsOptions = try TLSOptions.make(
            identity: loaded.secIdentity.value,
            pairingMode: self.pairingMode,
            isTrusted: isTrusted
        )
        let parameters = NWParameters(tls: tlsOptions)
        parameters.allowLocalEndpointReuse = true

        let endpointPort: NWEndpoint.Port = port.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        let listener = try NWListener(using: parameters, on: endpointPort)
        self.listener = listener
        let listenerID = UUID()
        self.listenerID = listenerID
        if advertise, let service = self.makeService() {
            listener.service = service
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection, listenerID: listenerID) }
        }

        let boundPort = try await Self.awaitReady(listener, queue: self.queue)
        try Task.checkCancellation()
        if advertise {
            self.startPermissionBrowser()
        }
        return boundPort
    }

    private func accept(_ connection: NWConnection, listenerID: UUID) {
        guard self.listenerID == listenerID else { connection.cancel()
            return
        }
        let id = UUID()
        self.connections[id] = connection
        let trusted = self.trusted
        let handler = HttpConnection(
            connection: connection,
            router: self.router,
            pairingMode: self.pairingMode,
            isTrusted: { trusted.contains($0) },
            onClose: { [weak self] in Task { await self?.removeConnection(id) } }
        )
        handler.start(queue: self.queue)
    }

    private func removeConnection(_ id: UUID) {
        self.connections[id] = nil
    }

    func stop() {
        self.listenerID = nil
        for connection in self.connections.values {
            connection.cancel()
        }
        self.connections.removeAll()
        self.permissionBrowser?.cancel()
        self.permissionBrowser = nil
        self.listener?.cancel()
        self.listener = nil
        self.advertise = false
    }

    /// Browse our own service type so macOS presents the Local Network permission prompt
    /// (see [permissionBrowser]). The browse results are intentionally unused: an
    /// advertise-only server is never prompted on its own, so this is what lets the
    /// Bonjour advertisement actually publish once the user allows access.
    private func startPermissionBrowser() {
        guard self.permissionBrowser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        let log = self.log
        browser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                log.debug("sync.localNetwork.browser.ready")

            case let .waiting(error):
                log.debug("sync.localNetwork.browser.waiting", ["error": String(reflecting: error)])

            case let .failed(error):
                log.error("sync.localNetwork.browser.failed", ["error": String(reflecting: error)])

            default:
                break
            }
        }
        browser.start(queue: self.queue)
        self.permissionBrowser = browser
    }

    /// Re-registers the Bonjour service with the current pairing-mode flag in the
    /// TXT record. Called whenever pairing mode toggles.
    func updatePairingMode(_: Bool) {
        guard self.advertise, let listener = self.listener, let service = self.makeService() else { return }
        listener.service = service
    }

    /// Re-advertises after a wake, when the listener may have dropped its service.
    func reAdvertise() {
        guard self.advertise, let listener = self.listener, let service = self.makeService() else { return }
        listener.service = service
    }

    private func makeService() -> NWListener.Service? {
        guard let fingerprint = self.fingerprint else { return nil }
        let txt = Self.txtRecord(fingerprint: fingerprint, pairingMode: self.pairingMode())
        return NWListener.Service(name: self.serviceName(), type: Self.serviceType, txtRecord: txt.data)
    }

    /// The Bonjour TXT record: `v=1`, `fp=<fingerprint>`, `pm=<0|1>`
    /// (sync-protocol.md section 1).
    static func txtRecord(fingerprint: String, pairingMode: Bool) -> NWTXTRecord {
        NWTXTRecord(["v": "1", "fp": fingerprint, "pm": pairingMode ? "1" : "0"])
    }

    static func awaitReady(
        _ listener: NWListener,
        queue: DispatchQueue,
        timeout: Duration = .seconds(10)
    ) async throws -> UInt16 {
        let (states, continuation) = AsyncThrowingStream<UInt16, Error>.makeStream()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                continuation.yield(listener.port?.rawValue ?? 0)
                continuation.finish()

            case let .failed(error):
                continuation.finish(throwing: error)

            case .cancelled:
                continuation.finish(throwing: CancellationError())

            default:
                break
            }
        }
        let timer = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            continuation.finish(throwing: URLError(.timedOut))
            listener.cancel()
        }
        defer {
            timer.cancel()
            listener.stateUpdateHandler = nil
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            listener.start(queue: queue)
            for try await port in states {
                return port
            }
            throw CancellationError()
        } onCancel: {
            continuation.finish(throwing: CancellationError())
            listener.cancel()
        }
    }
}
