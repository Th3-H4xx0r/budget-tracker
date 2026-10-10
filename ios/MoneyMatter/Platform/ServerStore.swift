import Foundation
import MoneyMatterKit

/// Remembers which server the app talks to.
protocol ServerStoring: AnyObject {
    func loadServer() -> ServerEndpoint?
    func saveServer(_ server: ServerEndpoint)
    func clearServer()
}

/// Stores the server origin in the App Group defaults so the widget extension can reach the
/// same server. A value left in `legacyDefaults` (the app's own defaults) is moved over on
/// first load.
final class UserDefaultsServerStore: ServerStoring {
    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults?
    private let key = SharedContainer.serverOriginKey

    init(defaults: UserDefaults = SharedContainer.defaults, legacyDefaults: UserDefaults? = .standard) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults === defaults ? nil : legacyDefaults
    }

    func loadServer() -> ServerEndpoint? {
        if defaults.string(forKey: key) == nil, let legacy = legacyDefaults?.string(forKey: key) {
            defaults.set(legacy, forKey: key)
            legacyDefaults?.removeObject(forKey: key)
        }
        guard let origin = defaults.string(forKey: key) else { return nil }
        return try? ServerEndpoint(validating: origin)
    }

    func saveServer(_ server: ServerEndpoint) {
        defaults.set(server.originString, forKey: key)
    }

    func clearServer() {
        defaults.removeObject(forKey: key)
        legacyDefaults?.removeObject(forKey: key)
    }
}
