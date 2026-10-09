import Foundation

public enum ServerURLError: Error, Sendable, Equatable {
    /// The text isn't a URL with a host.
    case invalid
    /// `http://` was used for a host that isn't `localhost` or `.local`.
    case insecureScheme
}

/// The server the app talks to: its web origin, plus the `/api/v1` base derived from it.
public struct ServerEndpoint: Sendable, Hashable, Codable {
    /// `scheme://host[:port]`, with no path. Sent as the `Origin` header on `/auth/*` writes.
    public let origin: URL

    public init(validating input: String) throws(ServerURLError) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .invalid }
        if !text.contains("://") { text = "https://" + text }

        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              scheme == "https" || scheme == "http"
        else { throw .invalid }

        if scheme == "http", !Self.isLocalHost(host) { throw .insecureScheme }

        var originComponents = URLComponents()
        originComponents.scheme = scheme
        originComponents.host = host
        // An explicit default port would make the Origin header miss the trusted origin.
        let defaultPort = scheme == "https" ? 443 : 80
        originComponents.port = components.port == defaultPort ? nil : components.port
        guard let origin = originComponents.url else { throw .invalid }
        self.origin = origin
    }

    public var host: String { origin.host() ?? "" }

    /// `host` plus an explicit port, so two local servers on different ports stay apart.
    public var hostAndPort: String {
        if let port = origin.port { return "\(host):\(port)" }
        return host
    }

    public var originString: String { origin.absoluteString }

    public var apiBaseURL: URL { origin.appending(path: "api/v1") }

    /// ATS allows plain HTTP only for local networking, so only these hosts accept `http://`.
    public static func isLocalHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
    }
}
