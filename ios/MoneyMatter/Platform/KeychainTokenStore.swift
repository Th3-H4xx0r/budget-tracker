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
/// Items live in the shared access group (`SharedContainer.keychainAccessGroup`) so the
/// widget extension can read the token and call the API itself. An item stored outside the
/// group (by builds without the shared group) is moved into it on first read.
///
/// Reads come from any thread (`APIClient` asks for the token on every request), so the
/// store is nonisolated and caches values behind a lock.
nonisolated final class KeychainTokenStore: TokenStoring, Sendable {
    private let service: String
    private let accessGroup: String
    private let cache = Mutex<[String: String]>([:])

    init(service: String = AppConfig.keychainService, accessGroup: String = SharedContainer.keychainAccessGroup) {
        self.service = service
        self.accessGroup = accessGroup
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

    /// Matches the item in every access group the app can see; used for deletes and to find
    /// items stored outside the shared group.
    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func sharedQuery(account: String) -> [String: Any] {
        var query = baseQuery(account: account)
        query[kSecAttrAccessGroup as String] = accessGroup
        return query
    }

    fileprivate func token(account: String) -> String? {
        if let cached = cache.withLock({ $0[account] }) { return cached }

        guard let token = readToken(sharedQuery(account: account)) ?? migrateLegacyToken(account: account) else {
            return nil
        }
        cache.withLock { $0[account] = token }
        return token
    }

    private func readToken(_ base: [String: Any]) -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Copies a token found outside the shared group into it, then deletes the original.
    /// Returns the token even when the copy fails, so the session survives either way.
    private func migrateLegacyToken(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let data = item[kSecValueData as String] as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }

        let legacyGroup = item[kSecAttrAccessGroup as String] as? String
        guard legacyGroup != accessGroup,
              upsert(query: sharedQuery(account: account), changes: Self.changes(token: token)) == errSecSuccess
        else { return token }
        if let legacyGroup {
            var legacy = baseQuery(account: account)
            legacy[kSecAttrAccessGroup as String] = legacyGroup
            SecItemDelete(legacy as CFDictionary)
        }
        return token
    }

    /// Updates in place, so a failed write never loses the token already stored; adds the
    /// item only when there is none yet.
    private func save(_ token: String, account: String) throws {
        let status = write(token, account: account)
        guard status == errSecSuccess else {
            // The Keychain is the source of truth; re-read it on the next access.
            _ = cache.withLock { $0.removeValue(forKey: account) }
            throw KeychainError(status: status)
        }
        cache.withLock { $0[account] = token }
    }

    /// Writes into the shared group. Unsigned builds (e.g. simulator builds with code signing
    /// off) lack the `keychain-access-groups` entitlement and get `errSecMissingEntitlement`;
    /// those fall back to the app's default group.
    private func write(_ token: String, account: String) -> OSStatus {
        let changes = Self.changes(token: token)
        let status = upsert(query: sharedQuery(account: account), changes: changes)
        guard status == errSecMissingEntitlement else { return status }
        return upsert(query: baseQuery(account: account), changes: changes)
    }

    private static func changes(token: String) -> [String: Any] {
        [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }

    private func upsert(query: [String: Any], changes: [String: Any]) -> OSStatus {
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            let attributes = query.merging(changes) { _, new in new }
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        return status
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
