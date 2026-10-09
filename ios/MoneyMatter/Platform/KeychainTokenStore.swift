import Foundation
import MoneyMatterKit
import Security
import Synchronization

/// Persists the bearer token for each server.
protocol TokenStoring: AnyObject {
    func token(for server: ServerEndpoint) -> String?
    func saveToken(_ token: String, for server: ServerEndpoint) throws
    func deleteToken(for server: ServerEndpoint)
    /// Removes every server's token, e.g. after a reinstall left Keychain items behind.
    func deleteAllTokens()
}

struct KeychainError: Error, Equatable {
    let status: OSStatus
}

/// The token lives only in the Keychain: a generic password under the app's service, with
/// the server host as the account, readable after first unlock on this device only.
///
/// Reads come from any thread (`APIClient` asks for the token on every request), so the
/// store is nonisolated and caches values behind a lock.
nonisolated final class KeychainTokenStore: TokenStoring, Sendable {
    private let service: String
    private let cache = Mutex<[String: String]>([:])

    init(service: String = AppConfig.keychainService) {
        self.service = service
    }

    func token(for server: ServerEndpoint) -> String? {
        token(account: server.hostAndPort)
    }

    func saveToken(_ token: String, for server: ServerEndpoint) throws {
        try save(token, account: server.hostAndPort)
    }

    func deleteToken(for server: ServerEndpoint) {
        delete(account: server.hostAndPort)
    }

    func deleteAllTokens() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
        cache.withLock { $0.removeAll() }
    }

    /// The provider `APIClient` reads for `server`.
    func tokenProvider(for server: ServerEndpoint) -> any AccessTokenProviding {
        KeychainTokenProvider(store: self, account: server.hostAndPort)
    }

    // MARK: Keychain access

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    fileprivate func token(account: String) -> String? {
        if let cached = cache.withLock({ $0[account] }) { return cached }

        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }

        cache.withLock { $0[account] = token }
        return token
    }

    /// Updates in place, so a failed write never loses the token already stored; adds the
    /// item only when there is none yet.
    private func save(_ token: String, account: String) throws {
        let query = baseQuery(account: account)
        let changes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            let attributes = query.merging(changes) { _, new in new }
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            // The Keychain is the source of truth; re-read it on the next access.
            _ = cache.withLock { $0.removeValue(forKey: account) }
            throw KeychainError(status: status)
        }
        cache.withLock { $0[account] = token }
    }

    private func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        _ = cache.withLock { $0.removeValue(forKey: account) }
    }
}

nonisolated private struct KeychainTokenProvider: AccessTokenProviding {
    let store: KeychainTokenStore
    let account: String

    func accessToken() -> String? {
        store.token(account: account)
    }
}
