import Foundation

// Bank data provider endpoints. Request and response shapes follow
// `packages/frontend/src/api/bank-data-providers.ts` and the backend controllers.

private struct BankProvidersEnvelope: Decodable, Sendable { let providers: [BankProviderInfo] }
private struct BankConnectionsEnvelope: Decodable, Sendable { let connections: [BankConnectionSummary] }
private struct BankConnectionDetailEnvelope: Decodable, Sendable { let connection: BankConnectionDetail }
private struct BankAvailableAccountsEnvelope: Decodable, Sendable { let accounts: [BankAvailableAccount] }
private struct EnableBankingCountriesEnvelope: Decodable, Sendable { let countries: [String] }
private struct EnableBankingBanksEnvelope: Decodable, Sendable { let banks: [EnableBankingBank] }

extension Endpoints {
    /// `GET /bank-data-providers`.
    public static func bankProviders() -> Endpoint<[BankProviderInfo]> {
        Endpoint<BankProvidersEnvelope>(.get, "/bank-data-providers").map(\.providers)
    }

    /// `GET /bank-data-providers/connections`.
    public static func bankConnections() -> Endpoint<[BankConnectionSummary]> {
        Endpoint<BankConnectionsEnvelope>(.get, "/bank-data-providers/connections").map(\.connections)
    }

    /// `GET /bank-data-providers/connections/:id`.
    public static func bankConnection(id: String) -> Endpoint<BankConnectionDetail> {
        Endpoint<BankConnectionDetailEnvelope>(.get, "/bank-data-providers/connections/\(id)").map(\.connection)
    }

    /// `POST /bank-data-providers/:type/connect`.
    public static func connectBankProvider(_ type: BankProviderType, _ request: BankConnectRequest) -> Endpoint<BankConnectResult> {
        Endpoint(.post, "/bank-data-providers/\(type.rawValue)/connect", body: request)
    }

    /// `DELETE /bank-data-providers/connections/:id`. The flag is sent only when on.
    public static func disconnectBankConnection(id: String, removeAssociatedAccounts: Bool) -> Endpoint<BankMessageResult> {
        var query = QueryBuilder()
        query.addFlag("removeAssociatedAccounts", removeAssociatedAccounts)
        return Endpoint(.delete, "/bank-data-providers/connections/\(id)", query: query.items)
    }

    /// `POST /bank-data-providers/connections/:id/reauthorize`: a fresh consent URL.
    public static func reauthorizeBankConnection(id: String) -> Endpoint<BankReauthorizeResult> {
        Endpoint(.post, "/bank-data-providers/connections/\(id)/reauthorize")
    }

    /// `PATCH /bank-data-providers/connections/:id`: rename, or replace credentials.
    public static func updateBankConnection(id: String, _ request: BankConnectionUpdateRequest) -> Endpoint<BankMessageResult> {
        Endpoint(.patch, "/bank-data-providers/connections/\(id)", body: request)
    }

    /// `GET /bank-data-providers/connections/:id/available-accounts`.
    public static func bankAvailableAccounts(connectionID: String) -> Endpoint<[BankAvailableAccount]> {
        Endpoint<BankAvailableAccountsEnvelope>(.get, "/bank-data-providers/connections/\(connectionID)/available-accounts")
            .map(\.accounts)
    }

    /// `POST /bank-data-providers/connections/:id/sync-selected-accounts`: links the chosen
    /// bank accounts and starts their first sync.
    public static func syncSelectedBankAccounts(
        connectionID: String,
        _ request: BankSyncSelectedAccountsRequest
    ) -> Endpoint<BankMessageResult> {
        Endpoint(.post, "/bank-data-providers/connections/\(connectionID)/sync-selected-accounts", body: request)
    }

    /// `POST /bank-data-providers/enablebanking/countries`.
    public static func enableBankingCountries(_ request: EnableBankingCredentialsRequest) -> Endpoint<[String]> {
        Endpoint<EnableBankingCountriesEnvelope>(.post, "/bank-data-providers/enablebanking/countries", body: request)
            .map(\.countries)
    }

    /// `POST /bank-data-providers/enablebanking/banks?country=`.
    public static func enableBankingBanks(country: String, _ request: EnableBankingCredentialsRequest) -> Endpoint<[EnableBankingBank]> {
        var query = QueryBuilder()
        query.add("country", country)
        return Endpoint<EnableBankingBanksEnvelope>(.post, "/bank-data-providers/enablebanking/banks", query: query.items, body: request)
            .map(\.banks)
    }

    /// `POST /bank-data-providers/enablebanking/oauth-callback`: finishes the consent flow.
    public static func completeEnableBankingConsent(_ request: EnableBankingOAuthCallbackRequest) -> Endpoint<BankMessageResult> {
        Endpoint(.post, "/bank-data-providers/enablebanking/oauth-callback", body: request)
    }

    /// `GET /bank-data-providers/sync/status`.
    public static func bankSyncStatus() -> Endpoint<BankSyncStatus> {
        Endpoint(.get, "/bank-data-providers/sync/status")
    }

    /// `POST /bank-data-providers/sync/trigger`: syncs every bank-connected account now.
    public static func triggerBankSync() -> Endpoint<BankSyncTriggerResult> {
        Endpoint(.post, "/bank-data-providers/sync/trigger")
    }

    /// `GET /bank-data-providers/sync/check`: auto-syncs when the last sync is stale.
    public static func checkBankSync() -> Endpoint<BankSyncCheckResult> {
        Endpoint(.get, "/bank-data-providers/sync/check")
    }
}
