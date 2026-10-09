import Foundation
import MoneyMatterKit
import Observation

/// Why a sign-in attempt stopped before reaching the server's answer.
enum SignInFailure: Error, Equatable {
    case noServer
    /// The provider or backend redirected back with `?error=<code>`.
    case oauthRejected(code: String)
    case unexpectedCallback
    case passkeysUnavailable
}

/// The single source of auth state.
///
/// - Launch restores the server from `UserDefaults` and the token from the Keychain, then
///   checks `GET /auth/get-session` and `GET /user/currencies/base`.
/// - A 401 from any request that carried the token ends the session and returns to sign-in
///   with the email prefilled.
/// - Changing the server signs out.
@Observable
final class SessionStore {
    enum State: Equatable {
        /// Restoring the saved session; `launchError` is set if that failed.
        case launching
        case needsServer
        case signedOut
        case needsOnboarding(User)
        case signedIn(User, baseCurrency: UserCurrency)
    }

    private(set) var state: State = .launching
    /// Why launch couldn't confirm the saved session (usually no network).
    private(set) var launchError: APIError?
    /// Whether the server accepts sign-ups; `nil` until known.
    private(set) var signupsOpen: Bool?
    /// Prefilled on the sign-in form after the session expires.
    private(set) var prefilledEmail: String?

    /// Called when a session ends, so session-scoped caches can clear.
    @ObservationIgnored var onSessionEnded: (() -> Void)?

    @ObservationIgnored private let connection: any SessionConnecting
    @ObservationIgnored private let serverStore: any ServerStoring
    @ObservationIgnored private let tokenStore: any TokenStoring
    @ObservationIgnored private let webAuthenticator: any WebAuthenticating
    @ObservationIgnored private let passkeyAuthenticator: any PasskeyAuthenticating
    @ObservationIgnored private let passkeyHosts: Set<String>

    init(
        connection: any SessionConnecting,
        serverStore: any ServerStoring,
        tokenStore: any TokenStoring,
        webAuthenticator: any WebAuthenticating,
        passkeyAuthenticator: any PasskeyAuthenticating,
        passkeyHosts: Set<String> = AppConfig.passkeyHosts
    ) {
        self.connection = connection
        self.serverStore = serverStore
        self.tokenStore = tokenStore
        self.webAuthenticator = webAuthenticator
        self.passkeyAuthenticator = passkeyAuthenticator
        self.passkeyHosts = passkeyHosts
        connection.onUnauthenticated = { [weak self] server, rejectedToken in
            self?.handleUnauthenticated(server: server, rejectedToken: rejectedToken)
        }
    }

    // MARK: Derived state

    var server: ServerEndpoint? { connection.endpoint }

    var user: User? {
        switch state {
        case .needsOnboarding(let user), .signedIn(let user, _): user
        case .launching, .needsServer, .signedOut: nil
        }
    }

    var baseCurrency: UserCurrency? {
        if case .signedIn(_, let baseCurrency) = state { return baseCurrency }
        return nil
    }

    /// Passkeys only work for hosts in the app's Associated Domains.
    var supportsPasskeys: Bool {
        server.map { passkeyHosts.contains($0.host) } ?? false
    }

    // MARK: Launch

    func restore() async {
        launchError = nil
        guard let server = serverStore.loadServer() else {
            // The Keychain outlives a reinstall but UserDefaults doesn't; drop orphaned tokens.
            tokenStore.deleteAllTokens()
            state = .needsServer
            return
        }
        connection.connect(to: server)

        guard tokenStore.token(for: server) != nil else {
            state = .signedOut
            await refreshSignupsOpen()
            return
        }

        do {
            try await loadAccount()
        } catch let error as APIError where error.isUnauthenticated {
            expireSession()
            await refreshSignupsOpen()
        } catch {
            let apiError = APIError(error)
            // A cancelled launch check (the view went away) isn't a connection problem.
            if !apiError.isCancellation { launchError = apiError }
        }
    }

    // MARK: Server

    /// Validates the address by calling `GET /auth/signups-open` and checking the server is new
    /// enough for the app, then saves it. Throws `ServerURLError` for a malformed address,
    /// `APIError.serverOutdated` for an older server, `APIError` if the server doesn't answer.
    func connect(toServer address: String) async throws {
        let server = try ServerEndpoint(validating: address)
        let previous = connection.endpoint
        connection.connect(to: server)
        do {
            guard let api = connection.sessionAPI else { throw SignInFailure.noServer }
            let open = try await api.signupsOpen()
            try await api.checkAppSupport()
            signupsOpen = open
        } catch {
            connection.connect(to: previous)
            throw error
        }
        serverStore.saveServer(server)
        prefilledEmail = nil
        state = .signedOut
    }

    /// Signs out (revoking the token) and forgets the server.
    func changeServer() async {
        await endSession(revoke: true)
        serverStore.clearServer()
        connection.connect(to: nil)
        signupsOpen = nil
        prefilledEmail = nil
        state = .needsServer
    }

    func refreshSignupsOpen() async {
        guard let api = connection.sessionAPI else { return }
        if let open = try? await api.signupsOpen() {
            signupsOpen = open
        }
    }

    // MARK: Sign in

    func signIn(email: String, password: String) async throws {
        let api = try requireAPI()
        let token = try await api.signIn(email: email, password: password)
        try await completeSignIn(token: token)
    }

    func signUp(name: String, email: String, password: String) async throws -> SignUpResult {
        let api = try requireAPI()
        let result = try await api.signUp(name: name, email: email, password: password)
        if case .signedIn(let token) = result {
            do {
                try await completeSignIn(token: token)
            } catch {
                // The account exists even though this session couldn't start; sign-in will work.
                prefilledEmail = email
                throw error
            }
        } else {
            prefilledEmail = email
        }
        return result
    }

    /// Google or GitHub through `ASWebAuthenticationSession` with PKCE, then the code exchange.
    func signIn(with provider: OAuthProvider) async throws {
        let api = try requireAPI()
        let pkce = PKCE.generate()
        let startURL = api.oauthStartURL(provider: provider, codeChallenge: pkce.challenge)
        let callbackURL = try await webAuthenticator.authenticate(url: startURL, callbackScheme: AppConfig.oauthCallbackScheme)

        switch OAuthCallback(url: callbackURL) {
        case .code(let code):
            let token = try await api.exchangeOAuthCode(code, codeVerifier: pkce.verifier)
            try await completeSignIn(token: token)
        case .error(let code):
            throw SignInFailure.oauthRejected(code: code)
        case nil:
            throw SignInFailure.unexpectedCallback
        }
    }

    func signInWithPasskey() async throws {
        let api = try requireAPI()
        guard let server, supportsPasskeys else { throw SignInFailure.passkeysUnavailable }
        let authenticator = passkeyAuthenticator
        let host = server.host
        let token = try await api.signInWithPasskey { options in
            try await authenticator.assertion(for: options, relyingParty: options.rpId ?? host)
        }
        try await completeSignIn(token: token)
    }

    // MARK: Onboarding

    func completeOnboarding(currencyCode: String) async throws {
        guard case .needsOnboarding(let user) = state else { return }
        let api = try requireAPI()
        do {
            let base = try await api.setBaseCurrency(code: currencyCode)
            state = .signedIn(user, baseCurrency: base)
        } catch let error as APIError {
            // A 422 can mean another device or an earlier attempt already set it; reload to see.
            guard case .validation = error else { throw error }
            try await loadAccount()
            if case .needsOnboarding = state { throw error }
        }
    }

    // MARK: Sign out

    /// Revokes the token on the server (best effort), then clears it from the Keychain.
    func signOut() async {
        await endSession(revoke: true)
        prefilledEmail = nil
        state = connection.endpoint == nil ? .needsServer : .signedOut
    }

    /// Retries the launch check after a failure.
    func retryLaunch() async {
        state = .launching
        await restore()
    }

    // MARK: Private

    private func requireAPI() throws -> any SessionAPI {
        guard let api = connection.sessionAPI else { throw SignInFailure.noServer }
        return api
    }

    private func completeSignIn(token: String) async throws {
        guard let server = connection.endpoint else { throw SignInFailure.noServer }
        do {
            try tokenStore.saveToken(token, for: server)
            try await loadAccount()
            prefilledEmail = nil
        } catch {
            // Revoke rather than strand a live server session behind a discarded token.
            try? await connection.sessionAPI?.signOut()
            tokenStore.deleteToken(for: server)
            throw error
        }
    }

    /// Confirms the token and loads the user and base currency.
    private func loadAccount() async throws {
        let api = try requireAPI()
        guard try await api.currentSession() != nil else {
            throw APIError.unauthenticated(message: nil)
        }
        async let user = api.currentUser()
        async let baseCurrency = api.baseCurrency()
        let (loadedUser, loadedBase) = try await (user, baseCurrency)
        launchError = nil
        if let loadedBase {
            state = .signedIn(loadedUser, baseCurrency: loadedBase)
        } else {
            state = .needsOnboarding(loadedUser)
        }
    }

    /// Ends the session only if the rejected token is still the current one for the current
    /// server; a late 401 for a token that was already replaced is ignored.
    private func handleUnauthenticated(server: ServerEndpoint, rejectedToken: String) {
        guard server == connection.endpoint, tokenStore.token(for: server) == rejectedToken else { return }
        switch state {
        case .needsOnboarding, .signedIn, .launching:
            expireSession()
        case .needsServer, .signedOut:
            break
        }
    }

    /// The token stopped working: drop it locally and go back to sign-in.
    private func expireSession() {
        let email = user?.email
        if let server = connection.endpoint {
            tokenStore.deleteToken(for: server)
        }
        prefilledEmail = email ?? prefilledEmail
        launchError = nil
        state = connection.endpoint == nil ? .needsServer : .signedOut
        onSessionEnded?()
    }

    private func endSession(revoke: Bool) async {
        guard let server = connection.endpoint else {
            onSessionEnded?()
            return
        }
        if revoke, tokenStore.token(for: server) != nil, let api = connection.sessionAPI {
            try? await api.signOut()
        }
        tokenStore.deleteToken(for: server)
        onSessionEnded?()
    }
}
