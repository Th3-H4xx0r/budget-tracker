import Foundation

public enum CloudflareAccessSetupPayloadError: Error, Equatable {
    /// Not JSON, or a field has the wrong shape.
    case malformed
    case unsupportedVersion
    /// The server isn't `https`.
    case insecureServer
    case missingCredentials
}

/// The QR code shown in web Settings:
/// `{"v":1,"server":"https://…","cfClientId":"…","cfClientSecret":"…"}`.
public struct CloudflareAccessSetupPayload: Sendable, Equatable {
    public static let supportedVersion = 1

    public let server: ServerEndpoint
    public let credentials: CloudflareAccessCredentials

    public static func parse(_ text: String) throws(CloudflareAccessSetupPayloadError) -> CloudflareAccessSetupPayload {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let version = object["v"] as? Int
        else { throw .malformed }
        guard version == supportedVersion else { throw .unsupportedVersion }

        guard let serverText = object["server"] as? String else { throw .malformed }
        let server: ServerEndpoint
        do {
            server = try ServerEndpoint(validating: serverText)
        } catch {
            throw error == .insecureScheme ? .insecureServer : .malformed
        }
        guard server.origin.scheme == "https" else { throw .insecureServer }

        guard let credentials = CloudflareAccessCredentials(
            clientId: object["cfClientId"] as? String ?? "",
            clientSecret: object["cfClientSecret"] as? String ?? ""
        ) else { throw .missingCredentials }

        return CloudflareAccessSetupPayload(server: server, credentials: credentials)
    }
}
