import Foundation
import Testing
@testable import MoneyMatterKit

/// Shared helpers for the Connections suites.
enum ConnectionsTestSupport {
    static let server = try! ServerEndpoint(validating: "https://budget.example.com")

    static func decode<Value>(_ endpoint: Endpoint<Value>, _ json: String) throws -> Value {
        try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
    }

    static func request<Response>(_ endpoint: Endpoint<Response>) throws -> URLRequest {
        try APIClient(server: server).makeRequest(for: endpoint).0
    }

    static func body<Response>(_ endpoint: Endpoint<Response>) throws -> [String: Any] {
        let data = try #require(try request(endpoint).httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@Suite("Bank connections")
struct BankConnectionsKitTests {
    private typealias Support = ConnectionsTestSupport

    @Test("Providers decode, with unknown types kept as .unknown")
    func providers() throws {
        let json = """
        {"status":"success","response":{"providers":[
          {"type":"monobank","name":"Monobank","description":"Ukrainian bank","features":{"supportsManualSync":true}},
          {"type":"plaid","name":"Plaid","description":"New"}
        ]}}
        """
        let providers = try Support.decode(Endpoints.bankProviders(), json)
        #expect(providers.map(\.type) == [.monobank, .unknown])
        #expect(providers[0].description == "Ukrainian bank")
    }

    @Test("Connections list decodes nullable dates and bank names")
    func connections() throws {
        let json = """
        {"status":"success","response":{"connections":[
          {"id":"0b8c-1","providerType":"enable-banking","providerName":"My Revolut","isActive":true,
           "lastSyncAt":"2026-10-09T08:15:00.000Z","accountsCount":3,"createdAt":"2026-09-01T00:00:00.000Z","bankName":"Revolut"},
          {"id":"0b8c-2","providerType":"monobank","providerName":"Mono","isActive":false,
           "lastSyncAt":null,"accountsCount":0,"createdAt":"2026-09-01T00:00:00.000Z","bankName":null}
        ]}}
        """
        let list = try Support.decode(Endpoints.bankConnections(), json)
        #expect(list.count == 2)
        #expect(list[0].providerType == .enableBanking)
        #expect(list[0].lastSyncAt == Date.iso("2026-10-09T08:15:00.000Z"))
        #expect(list[0].bankName == "Revolut")
        #expect(list[1].lastSyncAt == nil)
        #expect(list[1].isActive == false)
    }

    @Test("Connection details decode accounts, consent, and currency fallback")
    func details() throws {
        let json = """
        {"status":"success","response":{"connection":{
          "id":"c1","providerType":"enable-banking","providerName":"Revolut","isActive":true,
          "lastSyncAt":null,"createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z",
          "provider":{"name":"Enable Banking","description":"PSD2","features":{"requiresReauth":true}},
          "accounts":[{"id":"42","name":"EUR main","externalId":"ext-1","currentBalance":1234.56,
            "currencyCode":"EUR","type":"current","currencyFallback":{"providerCurrency":"XXX","assignedCurrency":"EUR"}}],
          "consent":{"validFrom":"2026-09-01T00:00:00.000Z","validUntil":"2026-12-01T00:00:00.000Z",
            "daysRemaining":53,"isExpired":false,"isExpiringSoon":false},
          "deactivationReason":null
        }}}
        """
        let detail = try Support.decode(Endpoints.bankConnection(id: "c1"), json)
        #expect(detail.accounts.first?.currentBalance == Decimal(string: "1234.56"))
        #expect(detail.accounts.first?.currencyFallback?.assignedCurrency == "EUR")
        #expect(detail.consent?.daysRemaining == 53)
        #expect(detail.consent?.validUntil == Date.iso("2026-12-01T00:00:00.000Z"))
        #expect(detail.provider?.name == "Enable Banking")
        #expect(detail.needsReconnect == false)
    }

    @Test("Available accounts flag the no-currency code")
    func availableAccounts() throws {
        let json = """
        {"status":"success","response":{"accounts":[
          {"externalId":"a","name":"Checking","type":"checking","balance":10.5,"currency":"USD","metadata":{}},
          {"externalId":"b","name":"Mystery","type":"other","balance":0,"currency":"XXX"}
        ]}}
        """
        let accounts = try Support.decode(Endpoints.bankAvailableAccounts(connectionID: "c1"), json)
        #expect(accounts.map(\.needsCurrencyChoice) == [false, true])
        #expect(accounts[0].balance == Decimal(string: "10.5"))
    }

    @Test("Sync status decodes the epoch-millisecond last sync and summaries")
    func syncStatus() throws {
        let json = """
        {"status":"success","response":{
          "lastSyncAt":1760000000000,
          "accounts":[{"accountId":"42","accountName":"EUR main","providerType":"monobank","status":"syncing",
            "startedAt":"2026-10-09T08:15:00.000Z","completedAt":null,"error":null},
            {"accountId":"43","accountName":"Card","providerType":"monobank","status":"exploded",
            "startedAt":null,"completedAt":null,"error":"Boom"}],
          "connectionsNeedingReauth":[{"connectionId":"c2","providerType":"enable-banking","providerName":"Bank",
            "bankName":null,"accountsCount":2,"deactivatedAt":null}],
          "connectionStatuses":[{"connectionId":"c1","isActive":true,"consentExpired":false,
            "consentExpiringSoon":true,"daysRemaining":5}],
          "summary":{"total":2,"syncing":1,"queued":0,"completed":0,"failed":0,"idle":1}
        }}
        """
        let status = try Support.decode(Endpoints.bankSyncStatus(), json)
        #expect(status.lastSyncAt == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(status.isInProgress)
        #expect(status.status(forAccountID: "42")?.status == .syncing)
        #expect(status.status(forAccountID: "43")?.status == .unknown)
        #expect(status.connectionsNeedingReauth.first?.accountsCount == 2)
        #expect(status.connectionStatus(forConnectionID: "c1")?.daysRemaining == 5)
    }

    @Test("Sync status tolerates a null last sync and missing lists")
    func syncStatusEmpty() throws {
        let json = #"{"status":"success","response":{"lastSyncAt":null}}"#
        let status = try Support.decode(Endpoints.bankSyncStatus(), json)
        #expect(status.lastSyncAt == nil)
        #expect(status.accounts.isEmpty)
        #expect(status.summary == .empty)
        #expect(!status.isInProgress)
    }

    @Test("Trigger and check results decode")
    func triggerAndCheck() throws {
        let trigger = try Support.decode(
            Endpoints.triggerBankSync(),
            #"{"status":"success","response":{"totalAccounts":4,"queuedAccounts":3}}"#
        )
        #expect(trigger.queuedAccounts == 3)
        let check = try Support.decode(Endpoints.checkBankSync(), #"{"status":"success","response":{"syncTriggered":false}}"#)
        #expect(check.syncTriggered == false)
        #expect(try Support.request(Endpoints.triggerBankSync()).httpMethod == "POST")
    }

    @Test("Connect sends credentials keyed per provider")
    func connectBodies() throws {
        let mono = try Support.body(Endpoints.connectBankProvider(.monobank, BankConnectRequest(credentials: BankProviderCredentials.monobank(token: "tok"))))
        #expect((mono["credentials"] as? [String: Any])?["apiToken"] as? String == "tok")
        #expect(mono["providerName"] == nil)
        let request = try Support.request(Endpoints.connectBankProvider(.enableBanking, BankConnectRequest(credentials: [:])))
        #expect(request.url?.path() == "/api/v1/bank-data-providers/enable-banking/connect")

        let walutomat = BankProviderCredentials.walutomat(apiKey: "k", privateKey: "p")
        #expect(walutomat == ["apiKey": .string("k"), "privateKey": .string("p")])
        #expect(BankProviderCredentials.simpleFIN(setupToken: "s") == ["setupToken": .string("s")])
        #expect(BankProviderCredentials.lunchFlow(apiKey: "l") == ["apiKey": .string("l")])
    }

    @Test("Reconnect credentials are re-keyed per provider")
    func reconnectCredentials() {
        #expect(BankProviderCredentials.reconnect(providerType: .monobank, apiKey: "a") == ["apiToken": .string("a")])
        #expect(BankProviderCredentials.reconnect(providerType: .simplefin, apiKey: "a") == ["setupToken": .string("a")])
        #expect(BankProviderCredentials.reconnect(providerType: .lunchflow, apiKey: "a") == ["apiKey": .string("a")])
        #expect(BankProviderCredentials.reconnect(providerType: .walutomat, apiKey: "a", privateKey: "b")
            == ["apiKey": .string("a"), "privateKey": .string("b")])
    }

    @Test("Enable Banking connect passes the bank and its consent validity")
    func enableBankingCredentials() throws {
        let banksJSON = """
        {"status":"success","response":{"banks":[{"name":"Revolut","country":"LT","bic":"REVOLT21","logo":"x",
          "beta":false,"maximum_consent_validity":7776000,"psu_types":["personal"],"auth_methods":[],"required_psu_headers":[]}]}}
        """
        let banks = try Support.decode(
            Endpoints.enableBankingBanks(country: "LT", EnableBankingCredentialsRequest(appId: "app", privateKey: "key")),
            banksJSON
        )
        let bank = try #require(banks.first)
        #expect(bank.maximumConsentValidity == 7_776_000)

        let body = try Support.body(Endpoints.connectBankProvider(
            .enableBanking,
            BankConnectRequest(credentials: BankProviderCredentials.enableBanking(appId: "app", privateKey: "key", bank: bank))
        ))
        let credentials = try #require(body["credentials"] as? [String: Any])
        #expect(credentials["bankName"] as? String == "Revolut")
        #expect(credentials["bankCountry"] as? String == "LT")
        #expect(credentials["maxConsentValidity"] as? Int == 7_776_000)

        let request = try Support.request(Endpoints.enableBankingBanks(country: "LT", EnableBankingCredentialsRequest(appId: "app", privateKey: "key")))
        #expect(request.url?.query() == "country=LT")
        #expect(request.httpMethod == "POST")
    }

    @Test("Countries decode from the countries envelope")
    func countries() throws {
        let countries = try Support.decode(
            Endpoints.enableBankingCountries(EnableBankingCredentialsRequest(appId: "a", privateKey: "b")),
            #"{"status":"success","response":{"countries":["FI","LT"]}}"#
        )
        #expect(countries == ["FI", "LT"])
    }

    @Test("Bank callback URLs are read like the web callback page")
    func callbackParsing() throws {
        let ok = try #require(URL(string: "https://budget.example.com/bank-callback?code=abc&state=xyz"))
        #expect(EnableBankingCallbackResult(callbackURL: ok) == .authorized(code: "abc", state: "xyz"))

        let denied = try #require(URL(string: "https://budget.example.com/bank-callback?error=access_denied&error_description=User%20cancelled"))
        #expect(EnableBankingCallbackResult(callbackURL: denied) == .denied(message: "User cancelled"))

        let bare = try #require(URL(string: "https://budget.example.com/bank-callback?code=abc"))
        #expect(EnableBankingCallbackResult(callbackURL: bare) == .missingParameters)
    }

    @Test("Completing consent posts connection id, code, and state")
    func completeConsent() throws {
        let body = try Support.body(Endpoints.completeEnableBankingConsent(
            EnableBankingOAuthCallbackRequest(connectionId: "c1", code: "abc", state: "xyz")
        ))
        #expect(body["connectionId"] as? String == "c1")
        #expect(body["code"] as? String == "abc")
        #expect(body["state"] as? String == "xyz")
    }

    @Test("Disconnect sends removeAssociatedAccounts only when on")
    func disconnectQuery() throws {
        let keep = try Support.request(Endpoints.disconnectBankConnection(id: "c1", removeAssociatedAccounts: false))
        #expect(keep.url?.query() == nil)
        #expect(keep.httpMethod == "DELETE")
        let remove = try Support.request(Endpoints.disconnectBankConnection(id: "c1", removeAssociatedAccounts: true))
        #expect(remove.url?.query() == "removeAssociatedAccounts=true")
    }

    @Test("Rename and select-accounts bodies omit empty fields")
    func updateBodies() throws {
        let rename = try Support.body(Endpoints.updateBankConnection(id: "c1", BankConnectionUpdateRequest(providerName: "Main")))
        #expect(rename["providerName"] as? String == "Main")
        #expect(rename["credentials"] == nil)

        let select = try Support.body(Endpoints.syncSelectedBankAccounts(
            connectionID: "c1",
            BankSyncSelectedAccountsRequest(accountExternalIds: ["a", "b"], currencyOverrides: [:])
        ))
        #expect(select["accountExternalIds"] as? [String] == ["a", "b"])
        #expect(select["currencyOverrides"] == nil)

        let withOverride = try Support.body(Endpoints.syncSelectedBankAccounts(
            connectionID: "c1",
            BankSyncSelectedAccountsRequest(accountExternalIds: ["b"], currencyOverrides: ["b": "USD"])
        ))
        #expect((withOverride["currencyOverrides"] as? [String: String]) == ["b": "USD"])
    }
}
