import Darwin
import Foundation

/// An SMB location that is safe to hand to Finder or persist with a library source.
/// Authentication belongs to Finder and the system Keychain, never to this value.
public struct NetworkShareAddress: Sendable, Hashable {
    public let url: URL

    /// Accepts `smb://server/share` or `server/share`, including a folder within a share.
    public init(_ text: String) throws {
        self.url = try Self.validatedURL(text, requiresShare: true)
    }

    /// A Finder connection can start at a server before its share is chosen.
    /// Accepts a LAN/Tailscale address or hostname, with an optional share path.
    public static func connectionURL(for text: String) throws -> URL {
        try Self.validatedURL(text, requiresShare: false)
    }

    private static func validatedURL(_ text: String, requiresShare: Bool) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NetworkShareAddressError.invalidAddress
        }

        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else if trimmed.hasPrefix("//") {
            candidate = "smb:" + trimmed
        } else {
            candidate = "smb://" + trimmed
        }

        guard var components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "smb" else {
            throw NetworkShareAddressError.invalidAddress
        }
        guard components.user == nil, components.password == nil else {
            throw NetworkShareAddressError.containsCredentials
        }
        guard components.query == nil, components.fragment == nil else {
            throw NetworkShareAddressError.containsQueryOrFragment
        }
        guard let host = components.host, Self.isValidHost(host) else {
            throw NetworkShareAddressError.missingHost
        }
        if let port = components.port, !(1...65535).contains(port) {
            throw NetworkShareAddressError.invalidPort
        }
        // URLComponents permits an empty port (`server:/share`). Do not pass an
        // ambiguous authority on to Finder.
        guard let schemeDelimiter = candidate.range(of: "://") else {
            throw NetworkShareAddressError.invalidAddress
        }
        let authority = candidate[schemeDelimiter.upperBound...]
            .prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !authority.hasSuffix(":") else {
            throw NetworkShareAddressError.invalidPort
        }

        var path = components.path
        if path.isEmpty || path == "/" {
            guard !requiresShare else { throw NetworkShareAddressError.missingShare }
            path = ""
        } else {
            guard path.hasPrefix("/") else { throw NetworkShareAddressError.missingShare }
            if path.hasSuffix("/") {
                path.removeLast()
            }
            let pathParts = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
            guard let share = pathParts.first,
                  !share.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NetworkShareAddressError.missingShare
            }
            guard pathParts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  !path.contains("\\"),
                  path.rangeOfCharacter(from: .controlCharacters) == nil else {
                throw NetworkShareAddressError.unsafePath
            }
        }

        components.scheme = "smb"
        // Re-encode the decoded path consistently so an escaped slash cannot
        // conceal a traversal component or produce a different Finder path.
        components.path = path
        guard let url = components.url else {
            throw NetworkShareAddressError.invalidAddress
        }
        return url
    }

    public var shareName: String {
        url.path.split(separator: "/").first.map(String.init) ?? ""
    }

    /// A readable address with no username or password.
    public var displayString: String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else { return url.absoluteString }
        let port = components.port.map { ":\($0)" } ?? ""
        return "smb://\(host)\(port)\(components.path)"
    }

    /// macOS remount URLs may contain a username. Remove credentials before
    /// validation so they are never retained by the app or displayed in Sources.
    public static func sanitized(_ url: URL) -> NetworkShareAddress? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.user = nil
        components.password = nil
        guard let address = components.string else { return nil }
        return try? NetworkShareAddress(address)
    }

    /// A folder inside a share belongs to the same mounted volume as its root.
    /// DNS aliases and IP addresses are intentionally not resolved here.
    public func matchesVolume(_ remountURL: URL) -> Bool {
        guard let other = Self.sanitized(remountURL),
              let own = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let mounted = URLComponents(url: other.url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return own.host?.lowercased() == mounted.host?.lowercased()
            && (own.port ?? 445) == (mounted.port ?? 445)
            && shareName.caseInsensitiveCompare(other.shareName) == .orderedSame
    }

    private static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              !host.contains(where: { "@/\\?#".contains($0) }) else {
            return false
        }
        if host.hasPrefix("[") || host.hasSuffix("]") {
            guard host.hasPrefix("["), host.hasSuffix("]") else { return false }
            let scopedAddress = host.dropFirst().dropLast().split(separator: "%", omittingEmptySubsequences: false)
            guard scopedAddress.count <= 2, let address = scopedAddress.first else { return false }
            if scopedAddress.count == 2 {
                let scope = scopedAddress[1]
                guard !scope.isEmpty,
                      scope.allSatisfy({ $0.isLetter || $0.isNumber || "-_.".contains($0) }) else { return false }
            }
            var bytes = in6_addr()
            return String(address).withCString { inet_pton(AF_INET6, $0, &bytes) == 1 }
        }
        return !host.contains(":") && !host.contains("[") && !host.contains("]")
    }
}

/// Messages deliberately omit the original address, which might contain secrets.
public enum NetworkShareAddressError: Error, Sendable, LocalizedError {
    case invalidAddress
    case missingHost
    case missingShare
    case containsCredentials
    case containsQueryOrFragment
    case invalidPort
    case unsafePath

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "Enter an SMB address such as smb://server/music."
        case .missingHost:
            "The SMB address needs a valid server name or IP address."
        case .missingShare:
            "The SMB address needs a shared folder after the server name."
        case .containsCredentials:
            "Enter the server and shared folder only. Sign in through Finder."
        case .containsQueryOrFragment:
            "An SMB address cannot contain a query or fragment."
        case .invalidPort:
            "The SMB port must be between 1 and 65535."
        case .unsafePath:
            "The shared folder path cannot contain traversal or invalid components."
        }
    }
}
