import Foundation
import Security

/// Read-only access to the bearer token the app keeps in the shared Keychain access group,
/// for the widget extension. The app owns writes (`KeychainTokenStore`).
public struct SharedKeychainTokenReader: AccessTokenProviding {
    public let account: String
    public let service: String
    public let accessGroup: String

    public init(
        server: ServerEndpoint,
        service: String = SharedContainer.keychainService,
        accessGroup: String = SharedContainer.keychainAccessGroup
    ) {
        self.account = server.hostAndPort
        self.service = service
        self.accessGroup = accessGroup
    }

    public func accessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }
}
