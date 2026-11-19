import Foundation

/// A Cloudflare Access service token. Sent on every request to the configured server so a
/// server behind Access lets the app through.
public struct CloudflareAccessCredentials: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let clientIdHeader = "CF-Access-Client-Id"
    public static let clientSecretHeader = "CF-Access-Client-Secret"

    public let clientId: String
    public let clientSecret: String

    /// Trims both values. `nil` when either is blank.
    public init?(clientId: String, clientSecret: String) {
        let clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientId.isEmpty, !clientSecret.isEmpty else { return nil }
        self.clientId = clientId
        self.clientSecret = clientSecret
    }

    private enum CodingKeys: String, CodingKey {
        case clientId
        case clientSecret
    }

    /// Applies the same trimming and blank checks as `init?(clientId:clientSecret:)`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let clientId = try container.decode(String.self, forKey: .clientId)
        let clientSecret = try container.decode(String.self, forKey: .clientSecret)
        guard let credentials = Self(clientId: clientId, clientSecret: clientSecret) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "The Cloudflare Access client ID or secret is blank.")
            )
        }
        self = credentials
    }

    /// Never includes the secret, so logging or string interpolation can't leak it.
    public var description: String {
        "CloudflareAccessCredentials(clientId: \(clientId), clientSecret: <redacted>)"
    }

    public var debugDescription: String { description }

    public var headers: [String: String] {
        [
            Self.clientIdHeader: clientId,
            Self.clientSecretHeader: clientSecret,
        ]
    }
}

/// Supplies the Cloudflare Access token for each request. Read on every call, so saving or
/// removing the token takes effect without rebuilding the client.
public protocol CloudflareAccessProviding: Sendable {
    func cloudflareAccessCredentials() -> CloudflareAccessCredentials?
}
