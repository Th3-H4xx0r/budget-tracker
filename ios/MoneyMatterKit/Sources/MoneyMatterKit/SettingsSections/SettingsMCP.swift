import Foundation

/// An MCP client the user authorized through OAuth to read their data.
public struct SettingsMCPConnectedApp: Sendable, Hashable, Identifiable, Decodable {
    public let clientId: String
    public let name: String?
    public let icon: String?
    public let scopes: [String]
    public let connectedAt: Date?
    public let lastUsedAt: Date?

    public var id: String { clientId }

    private enum CodingKeys: String, CodingKey { case clientId, name, icon, scopes, connectedAt, lastUsedAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientId = try container.decode(String.self, forKey: .clientId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        scopes = try container.decodeIfPresent([String].self, forKey: .scopes) ?? []
        connectedAt = try? container.decodeIfPresent(Date.self, forKey: .connectedAt)
        lastUsedAt = try? container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }
}

extension Endpoints {
    /// `GET /user/settings/mcp/connected-apps`.
    public static func settingsMCPConnectedApps() -> Endpoint<[SettingsMCPConnectedApp]> {
        Endpoint(.get, "/user/settings/mcp/connected-apps")
    }

    /// `DELETE /user/settings/mcp/connected-apps/:clientId`: revokes the app's tokens and consent.
    public static func settingsMCPRevokeConnectedApp(clientID: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/user/settings/mcp/connected-apps/\(clientID)")
    }

    /// The MCP server URL to paste into an MCP client.
    public static func settingsMCPServerURL(server: ServerEndpoint) -> URL {
        server.origin.appending(path: "mcp")
    }
}
