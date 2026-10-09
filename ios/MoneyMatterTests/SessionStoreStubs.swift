import Foundation
import MoneyMatterKit
@testable import MoneyMatter

struct StubError: Error, Equatable {}

/// A scripted session API. Each result defaults to success; tests override what they need.
final class StubSessionAPI: AuthServicing, UserServicing {
    var signupsOpenResult: Result<Bool, APIError> = .success(true)
    var appSupportResult: Result<Void, APIError> = .success(())
    var sessionResult: Result<AuthSession?, APIError> = .success(StubSessionAPI.validSession)
    var signInResult: Result<String, APIError> = .success("signed.email")
    var signUpResult: Result<SignUpResult, APIError> = .success(.signedIn(token: "signed.signup"))
    var exchangeResult: Result<String, APIError> = .success("signed.oauth")
    var passkeyResult: Result<String, APIError> = .success("signed.passkey")
    var userResult: Result<User, APIError> = .success(StubSessionAPI.user)
    var baseCurrencyResult: Result<UserCurrency?, APIError> = .success(StubSessionAPI.euro)
    var setBaseCurrencyResult: Result<UserCurrency, APIError> = .success(StubSessionAPI.euro)
    /// Applied after `setBaseCurrency` is called, e.g. to model another device having set it.
    var baseCurrencyAfterSet: UserCurrency??

    private(set) var signOutCount = 0
    private(set) var signInCalls: [(email: String, password: String)] = []
    private(set) var exchangeCalls: [(code: String, verifier: String)] = []
    private(set) var setBaseCurrencyCalls: [String] = []

    static let user = User(id: 42, username: "pranav", firstName: "Pranav", lastName: "Krishna", email: "pranav@example.com")
    static let euro = UserCurrency(id: "uc-1", userId: 42, currencyCode: "EUR", isDefaultCurrency: true, currency: Currency(code: "EUR", currency: "Euro"))
    static let validSession: AuthSession = {
        let json = #"{"session":{"id":"s1","expiresAt":"2026-10-16T08:00:00.000Z"},"user":{"id":"ba-1","email":"pranav@example.com"}}"#
        return try! JSONCoding.makeDecoder().decode(AuthSession.self, from: Data(json.utf8))
    }()

    func signupsOpen() async throws -> Bool { try signupsOpenResult.get() }
    func checkAppSupport() async throws { try appSupportResult.get() }
    func currentSession() async throws -> AuthSession? { try sessionResult.get() }

    func signIn(email: String, password: String) async throws -> String {
        signInCalls.append((email, password))
        return try signInResult.get()
    }

    func signUp(name: String, email: String, password: String) async throws -> SignUpResult {
        try signUpResult.get()
    }

    func oauthStartURL(provider: OAuthProvider, codeChallenge: String) -> URL {
        URL(string: "https://budget.example.com/api/v1/auth/native/oauth/start?provider=\(provider.rawValue)&code_challenge=\(codeChallenge)")!
    }

    func exchangeOAuthCode(_ code: String, codeVerifier: String) async throws -> String {
        exchangeCalls.append((code, codeVerifier))
        return try exchangeResult.get()
    }

    func signInWithPasskey(assert: @Sendable (PasskeyRequestOptions) async throws -> PasskeyAssertion) async throws -> String {
        _ = try await assert(PasskeyRequestOptions(challenge: Data([1, 2, 3]), rpId: nil))
        return try passkeyResult.get()
    }

    func signOut() async throws { signOutCount += 1 }

    func currentUser() async throws -> User { try userResult.get() }
    func baseCurrency() async throws -> UserCurrency? { try baseCurrencyResult.get() }

    func setBaseCurrency(code: String) async throws -> UserCurrency {
        setBaseCurrencyCalls.append(code)
        if let baseCurrencyAfterSet { baseCurrencyResult = .success(baseCurrencyAfterSet) }
        return try setBaseCurrencyResult.get()
    }

    func userCurrencies() async throws -> [UserCurrency] { [Self.euro] }
    func allCurrencies() async throws -> [Currency] { [Currency(code: "EUR", currency: "Euro")] }
    func addUserCurrencies(codes: [String]) async throws -> AddedUserCurrencies { throw StubError() }
}

/// Hands out the stub API for whichever server is connected.
final class StubConnection: SessionConnecting {
    let api: StubSessionAPI
    private(set) var endpoint: ServerEndpoint?
    private(set) var connectCalls: [ServerEndpoint?] = []
    var onUnauthenticated: ((_ server: ServerEndpoint, _ rejectedToken: String) -> Void)?

    init(api: StubSessionAPI) {
        self.api = api
    }

    var sessionAPI: (any SessionAPI)? { endpoint == nil ? nil : api }

    func connect(to endpoint: ServerEndpoint?) {
        connectCalls.append(endpoint)
        self.endpoint = endpoint
    }

    /// What `APIClient` does when a request carrying `token` gets a 401.
    func simulateUnauthenticatedResponse(token: String, server: ServerEndpoint? = nil) {
        guard let server = server ?? endpoint else { return }
        onUnauthenticated?(server, token)
    }
}

final class InMemoryServerStore: ServerStoring {
    var server: ServerEndpoint?

    init(server: ServerEndpoint? = nil) {
        self.server = server
    }

    func loadServer() -> ServerEndpoint? { server }
    func saveServer(_ server: ServerEndpoint) { self.server = server }
    func clearServer() { server = nil }
}

final class InMemoryTokenStore: TokenStoring {
    var tokens: [String: String] = [:]

    func token(for server: ServerEndpoint) -> String? { tokens[server.hostAndPort] }
    func saveToken(_ token: String, for server: ServerEndpoint) throws { tokens[server.hostAndPort] = token }
    func deleteToken(for server: ServerEndpoint) { tokens[server.hostAndPort] = nil }
    func deleteAllTokens() { tokens.removeAll() }
}

final class StubWebAuthenticator: WebAuthenticating {
    var callback: Result<URL, any Error> = .success(URL(string: "moneymatter://auth-callback?code=one-time")!)
    private(set) var openedURLs: [URL] = []
    private(set) var callbackSchemes: [String] = []

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        openedURLs.append(url)
        callbackSchemes.append(callbackScheme)
        return try callback.get()
    }
}

final class StubPasskeyAuthenticator: PasskeyAuthenticating {
    private(set) var relyingParties: [String] = []

    func assertion(for options: PasskeyRequestOptions, relyingParty: String) async throws -> PasskeyAssertion {
        relyingParties.append(relyingParty)
        return PasskeyAssertion(credentialID: Data([1]), clientDataJSON: Data(), authenticatorData: Data(), signature: Data(), userHandle: nil)
    }
}

/// A `SessionStore` wired to stubs, with handles on each.
struct SessionHarness {
    let store: SessionStore
    let api: StubSessionAPI
    let connection: StubConnection
    let servers: InMemoryServerStore
    let tokens: InMemoryTokenStore
    let web: StubWebAuthenticator
    let passkeys: StubPasskeyAuthenticator
    /// How many times the store reported a session ending.
    let sessionEndedCount: () -> Int

    static let server = try! ServerEndpoint(validating: "https://budget.example.com")
    static let passkeyServer = try! ServerEndpoint(validating: "https://budget.pkrishna.dev")

    init(server: ServerEndpoint? = nil, token: String? = nil, passkeyHosts: Set<String> = ["budget.pkrishna.dev"]) {
        api = StubSessionAPI()
        connection = StubConnection(api: api)
        servers = InMemoryServerStore(server: server)
        tokens = InMemoryTokenStore()
        web = StubWebAuthenticator()
        passkeys = StubPasskeyAuthenticator()
        if let server, let token {
            tokens.tokens[server.hostAndPort] = token
        }
        store = SessionStore(
            connection: connection,
            serverStore: servers,
            tokenStore: tokens,
            webAuthenticator: web,
            passkeyAuthenticator: passkeys,
            passkeyHosts: passkeyHosts
        )
        let counter = Counter()
        store.onSessionEnded = { counter.value += 1 }
        sessionEndedCount = { counter.value }
    }

    func token(for server: ServerEndpoint = SessionHarness.server) -> String? {
        tokens.token(for: server)
    }
}

final class Counter {
    var value = 0
}
