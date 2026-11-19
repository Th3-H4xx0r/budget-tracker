import Foundation
import Security
import Synchronization

/// Persists the Cloudflare Access token for each server.
public protocol CloudflareAccessStoring: AnyObject, Sendable {
    func credentials(for server: ServerEndpoint) -> CloudflareAccessCredentials?
    func save(_ credentials: CloudflareAccessCredentials, for server: ServerEndpoint) throws
    /// Throws `CloudflareAccessKeychainError` when the item couldn't be removed, in which case
    /// the token is still stored.
    func delete(for server: ServerEndpoint) throws
    /// Removes every server's token. Best effort.
    func deleteAll()
    /// Reads the store on every call, so updates apply without rebuilding clients.
    func provider(for server: ServerEndpoint) -> any CloudflareAccessProviding
}

extension CloudflareAccessStoring {
    public func provider(for server: ServerEndpoint) -> any CloudflareAccessProviding {
        CloudflareAccessStoreProvider(store: self, server: server)
    }
}

/// Reads one server's token from a store each time it's asked.
public struct CloudflareAccessStoreProvider: CloudflareAccessProviding {
    let store: any CloudflareAccessStoring
    let server: ServerEndpoint

    public func cloudflareAccessCredentials() -> CloudflareAccessCredentials? {
        store.credentials(for: server)
    }
}

public struct CloudflareAccessKeychainError: Error, Equatable {
    public let status: OSStatus
}

/// The token lives only in the Keychain: a generic password under the app's service
/// (suffixed `.cloudflare-access`) with the server host as the account, as JSON, readable
/// after first unlock on this device only.
///
/// Items live in the shared access group so the widget extension and background refresh can
/// send the token too. Reads come from any thread, so values (including "no token") are cached
/// behind a lock. A read caches its result only if no save or delete touched the account since
/// the read began.
public final class KeychainCloudflareAccessStore: CloudflareAccessStoring {
    private struct State {
        var cache: [String: CloudflareAccessCredentials?] = [:]
        var generations: [String: Int] = [:]
        var epoch = 0

        func generation(of account: String) -> [Int] { [epoch, generations[account, default: 0]] }

        mutating func invalidate(_ account: String) {
            generations[account, default: 0] += 1
            cache[account] = nil
        }
    }

    private let service: String
    private let accessGroup: String
    private let state = Mutex<State>(State())

    public init(
        service: String = "\(SharedContainer.keychainService).cloudflare-access",
        accessGroup: String = SharedContainer.keychainAccessGroup
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func credentials(for server: ServerEndpoint) -> CloudflareAccessCredentials? {
        let account = server.hostAndPort
        let (cached, generation) = state.withLock { ($0.cache[account], $0.generation(of: account)) }
        if let cached { return cached }

        var query = sharedQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecMissingEntitlement {
            var fallback = baseQuery(account: account)
            fallback[kSecReturnData as String] = true
            fallback[kSecMatchLimit as String] = kSecMatchLimitOne
            status = SecItemCopyMatching(fallback as CFDictionary, &result)
        }
        var credentials: CloudflareAccessCredentials?
        if status == errSecSuccess {
            credentials = (result as? Data).flatMap { try? JSONDecoder().decode(CloudflareAccessCredentials.self, from: $0) }
        }
        // Transient failures (e.g. a locked device) aren't cached, so the next read retries.
        guard status == errSecItemNotFound || credentials != nil else { return nil }
        state.withLock {
            if $0.generation(of: account) == generation { $0.cache[account] = .some(credentials) }
        }
        return credentials
    }

    public func save(_ credentials: CloudflareAccessCredentials, for server: ServerEndpoint) throws {
        let account = server.hostAndPort
        state.withLock { $0.invalidate(account) }
        let status = write(credentials, account: account)
        state.withLock {
            // The Keychain is the source of truth after a failed write; re-read it on the next access.
            $0.invalidate(account)
            if status == errSecSuccess { $0.cache[account] = .some(credentials) }
        }
        guard status == errSecSuccess else { throw CloudflareAccessKeychainError(status: status) }
    }

    public func delete(for server: ServerEndpoint) throws {
        let account = server.hostAndPort
        state.withLock { $0.invalidate(account) }
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        let removed = status == errSecSuccess || status == errSecItemNotFound
        state.withLock {
            $0.invalidate(account)
            if removed { $0.cache[account] = .some(nil) }
        }
        guard removed else { throw CloudflareAccessKeychainError(status: status) }
    }

    public func deleteAll() {
        state.withLock { $0.epoch += 1; $0.cache.removeAll() }
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
        state.withLock { $0.epoch += 1; $0.cache.removeAll() }
    }

    // MARK: Keychain access

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

    /// Writes into the shared group. Unsigned builds (e.g. simulator builds with code signing
    /// off) lack the `keychain-access-groups` entitlement and get `errSecMissingEntitlement`;
    /// those fall back to the app's default group.
    private func write(_ credentials: CloudflareAccessCredentials, account: String) -> OSStatus {
        guard let data = try? JSONEncoder().encode(credentials) else { return errSecParam }
        let changes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = upsert(query: sharedQuery(account: account), changes: changes)
        guard status == errSecMissingEntitlement else { return status }
        return upsert(query: baseQuery(account: account), changes: changes)
    }

    /// Updates in place, so a failed write never loses the token already stored; adds the
    /// item only when there is none yet.
    private func upsert(query: [String: Any], changes: [String: Any]) -> OSStatus {
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            let attributes = query.merging(changes) { _, new in new }
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        return status
    }
}
