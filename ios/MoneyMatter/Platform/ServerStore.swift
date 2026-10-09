import Foundation
import MoneyMatterKit

/// Remembers which server the app talks to.
protocol ServerStoring: AnyObject {
    func loadServer() -> ServerEndpoint?
    func saveServer(_ server: ServerEndpoint)
    func clearServer()
}

final class UserDefaultsServerStore: ServerStoring {
    private let defaults: UserDefaults
    private let key = "serverOrigin"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadServer() -> ServerEndpoint? {
        guard let origin = defaults.string(forKey: key) else { return nil }
        return try? ServerEndpoint(validating: origin)
    }

    func saveServer(_ server: ServerEndpoint) {
        defaults.set(server.originString, forKey: key)
    }

    func clearServer() {
        defaults.removeObject(forKey: key)
    }
}
