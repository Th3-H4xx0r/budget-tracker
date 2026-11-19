import Foundation
import MoneyMatterKit
import Observation

/// The composition root: the server connection (and its `APIClient`), the session, and the
/// session-wide stores. Injected at the root with `.environment`.
@Observable
final class AppDependencies {
    let connection: ServerConnection
    let session: SessionStore
    let referenceData: ReferenceDataStore

    init(
        connection: ServerConnection,
        serverStore: any ServerStoring,
        tokenStore: any TokenStoring,
        cloudflareAccessStore: any CloudflareAccessStoring,
        webAuthenticator: any WebAuthenticating,
        passkeyAuthenticator: any PasskeyAuthenticating
    ) {
        self.connection = connection
        let referenceData = ReferenceDataStore { [weak connection] in connection?.services?.referenceData }
        self.referenceData = referenceData
        session = SessionStore(
            connection: connection,
            serverStore: serverStore,
            tokenStore: tokenStore,
            cloudflareAccessStore: cloudflareAccessStore,
            webAuthenticator: webAuthenticator,
            passkeyAuthenticator: passkeyAuthenticator
        )
        session.onSessionEnded = { [weak referenceData] in
            referenceData?.reset()
            MonthlyBudgetAlerts.sessionEnded()
        }
    }

    /// Services for the connected server; `nil` before a server is chosen.
    var services: AppServices? { connection.services }

    var apiClient: APIClient? { connection.services?.client }

    static func live() -> AppDependencies {
        let tokenStore = KeychainTokenStore()
        let cloudflareAccessStore = KeychainCloudflareAccessStore()
        let serverStore = UserDefaultsServerStore()
        #if DEBUG
        DebugLaunch.seedSession(serverStore: serverStore, tokenStore: tokenStore)
        #endif
        return AppDependencies(
            connection: .live(tokenStore: tokenStore, cloudflareAccessStore: cloudflareAccessStore),
            serverStore: serverStore,
            tokenStore: tokenStore,
            cloudflareAccessStore: cloudflareAccessStore,
            webAuthenticator: WebAuthenticator(),
            passkeyAuthenticator: PasskeyAuthenticator()
        )
    }
}
