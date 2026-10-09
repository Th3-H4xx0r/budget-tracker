import Foundation
import MoneyMatterKit
import Observation

/// What `SessionStore` needs from the connection: the current server and its session API.
protocol SessionConnecting: AnyObject {
    var endpoint: ServerEndpoint? { get }
    var sessionAPI: (any SessionAPI)? { get }
    /// Called on the main actor when a request gets a 401, with the server it went to and the
    /// token it carried.
    var onUnauthenticated: ((_ server: ServerEndpoint, _ rejectedToken: String) -> Void)? { get set }
    func connect(to endpoint: ServerEndpoint?)
}

/// Owns the services for the server the user picked, rebuilding them when it changes.
@Observable
final class ServerConnection: SessionConnecting {
    typealias ServicesFactory = (
        _ endpoint: ServerEndpoint,
        _ onUnauthenticated: @escaping @Sendable (_ rejectedToken: String) -> Void
    ) -> AppServices

    private(set) var endpoint: ServerEndpoint?
    private(set) var services: AppServices?
    @ObservationIgnored var onUnauthenticated: ((_ server: ServerEndpoint, _ rejectedToken: String) -> Void)?
    @ObservationIgnored private let makeServices: ServicesFactory

    init(makeServices: @escaping ServicesFactory) {
        self.makeServices = makeServices
    }

    var sessionAPI: (any SessionAPI)? { services?.identity }

    func connect(to endpoint: ServerEndpoint?) {
        if endpoint == self.endpoint, (services != nil) == (endpoint != nil) { return }
        self.endpoint = endpoint
        services = endpoint.map { endpoint in
            makeServices(endpoint) { [weak self] rejectedToken in
                Task { @MainActor in self?.onUnauthenticated?(endpoint, rejectedToken) }
            }
        }
    }

    /// Live services: one cookie-less `APIClient` reading the token from the Keychain.
    static func live(tokenStore: KeychainTokenStore) -> ServerConnection {
        ServerConnection { endpoint, onUnauthenticated in
            let client = APIClient(
                server: endpoint,
                tokenProvider: tokenStore.tokenProvider(for: endpoint),
                onUnauthenticated: onUnauthenticated
            )
            return AppServices(client: client)
        }
    }
}
