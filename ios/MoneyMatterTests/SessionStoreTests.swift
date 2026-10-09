import Foundation
import MoneyMatterKit
import Testing
@testable import MoneyMatter

@Suite("SessionStore")
struct SessionStoreTests {
    private let server = SessionHarness.server

    // MARK: Restore

    @Test("Without a saved server, launch asks for one")
    func restoreWithoutServer() async {
        let harness = SessionHarness()
        harness.tokens.tokens["old.example.com"] = "left.from.previous.install"

        await harness.store.restore()

        #expect(harness.store.state == .needsServer)
        #expect(harness.connection.endpoint == nil)
        // The Keychain outlives a reinstall; orphaned tokens are dropped.
        #expect(harness.tokens.tokens.isEmpty)
    }

    @Test("With a server but no token, launch goes to sign-in and checks sign-ups")
    func restoreWithoutToken() async {
        let harness = SessionHarness(server: server)
        harness.api.signupsOpenResult = .success(false)

        await harness.store.restore()

        #expect(harness.store.state == .signedOut)
        #expect(harness.connection.endpoint == server)
        #expect(harness.store.signupsOpen == false)
    }

    @Test("A valid token with a base currency restores the signed-in state")
    func restoreSignedIn() async {
        let harness = SessionHarness(server: server, token: "signed.saved")

        await harness.store.restore()

        #expect(harness.store.state == .signedIn(StubSessionAPI.user, baseCurrency: StubSessionAPI.euro))
        #expect(harness.store.user?.email == "pranav@example.com")
        #expect(harness.store.baseCurrency?.currencyCode == "EUR")
    }

    @Test("A user without a base currency needs onboarding")
    func restoreNeedsOnboarding() async {
        let harness = SessionHarness(server: server, token: "signed.saved")
        harness.api.baseCurrencyResult = .success(nil)

        await harness.store.restore()

        #expect(harness.store.state == .needsOnboarding(StubSessionAPI.user))
    }

    @Test("A token the server no longer recognizes is dropped")
    func restoreWithInvalidSession() async {
        let harness = SessionHarness(server: server, token: "signed.revoked")
        harness.api.sessionResult = .success(nil)

        await harness.store.restore()

        #expect(harness.store.state == .signedOut)
        #expect(harness.token() == nil)
    }

    @Test("A 401 during launch drops the token and returns to sign-in")
    func restoreUnauthenticated() async {
        let harness = SessionHarness(server: server, token: "signed.expired")
        harness.api.userResult = .failure(.unauthenticated(message: nil))

        await harness.store.restore()

        #expect(harness.store.state == .signedOut)
        #expect(harness.token() == nil)
        #expect(harness.sessionEndedCount() == 1)
    }

    @Test("A network failure at launch keeps the token and offers a retry")
    func restoreOffline() async {
        let harness = SessionHarness(server: server, token: "signed.saved")
        harness.api.sessionResult = .failure(.network(URLError(.notConnectedToInternet)))

        await harness.store.restore()

        #expect(harness.store.state == .launching)
        #expect(harness.store.launchError == .network(URLError(.notConnectedToInternet)))
        #expect(harness.token() == "signed.saved")

        harness.api.sessionResult = .success(StubSessionAPI.validSession)
        await harness.store.retryLaunch()

        #expect(harness.store.launchError == nil)
        #expect(harness.store.state == .signedIn(StubSessionAPI.user, baseCurrency: StubSessionAPI.euro))
    }

    // MARK: Server

    @Test("Connecting to a server validates it, saves it, and goes to sign-in")
    func connectToServer() async throws {
        let harness = SessionHarness()
        await harness.store.restore()

        try await harness.store.connect(toServer: "budget.example.com")

        #expect(harness.store.state == .signedOut)
        #expect(harness.servers.server == server)
        #expect(harness.store.signupsOpen == true)
    }

    @Test("A malformed address is rejected before any request")
    func connectToInvalidServer() async {
        let harness = SessionHarness()
        await harness.store.restore()

        await #expect(throws: ServerURLError.insecureScheme) {
            try await harness.store.connect(toServer: "http://budget.example.com")
        }
        #expect(harness.store.state == .needsServer)
        #expect(harness.connection.connectCalls.isEmpty)
    }

    @Test("An unreachable server isn't saved and the previous connection is restored")
    func connectToUnreachableServer() async {
        let harness = SessionHarness()
        await harness.store.restore()
        harness.api.signupsOpenResult = .failure(.network(URLError(.cannotFindHost)))

        await #expect(throws: APIError.self) {
            try await harness.store.connect(toServer: "budget.example.com")
        }
        #expect(harness.store.state == .needsServer)
        #expect(harness.servers.server == nil)
        #expect(harness.connection.endpoint == nil)
    }

    @Test("An older server without the app's routes isn't saved and explains it needs updating")
    func connectToOutdatedServer() async {
        let harness = SessionHarness()
        await harness.store.restore()
        harness.api.appSupportResult = .failure(.serverOutdated)

        await #expect(throws: APIError.serverOutdated) {
            try await harness.store.connect(toServer: "budget.example.com")
        }
        #expect(harness.store.state == .needsServer)
        #expect(harness.servers.server == nil)
        #expect(harness.connection.endpoint == nil)
        #expect(ServerView.message(for: APIError.serverOutdated) == ErrorMessage.message(for: .serverOutdated))
        #expect(ErrorMessage.message(for: .serverOutdated).contains("older version of MoneyMatter"))
    }

    @Test("Changing the server revokes the token and forgets the server")
    func changeServer() async {
        let harness = SessionHarness(server: server, token: "signed.saved")
        await harness.store.restore()

        await harness.store.changeServer()

        #expect(harness.store.state == .needsServer)
        #expect(harness.api.signOutCount == 1)
        #expect(harness.token() == nil)
        #expect(harness.servers.server == nil)
        #expect(harness.connection.endpoint == nil)
    }

    // MARK: Sign in

    @Test("Email sign-in stores the token and lands signed in")
    func emailSignIn() async throws {
        let harness = SessionHarness(server: server)
        await harness.store.restore()

        try await harness.store.signIn(email: "pranav@example.com", password: "hunter22")

        #expect(harness.token() == "signed.email")
        #expect(harness.store.state == .signedIn(StubSessionAPI.user, baseCurrency: StubSessionAPI.euro))
        #expect(harness.api.signInCalls.first?.email == "pranav@example.com")
    }

    @Test("A rejected sign-in stores nothing and stays signed out")
    func emailSignInRejected() async {
        let harness = SessionHarness(server: server)
        await harness.store.restore()
        harness.api.signInResult = .failure(.unauthenticated(message: "Invalid email or password"))

        await #expect(throws: APIError.self) {
            try await harness.store.signIn(email: "pranav@example.com", password: "wrong")
        }
        #expect(harness.store.state == .signedOut)
        #expect(harness.token() == nil)
    }

    @Test("Sign-in on a server without the bearer plugin says the server needs updating")
    func emailSignInOnOutdatedServer() async {
        let harness = SessionHarness(server: server)
        await harness.store.restore()
        harness.api.signInResult = .failure(.serverOutdated)

        let error = await #expect(throws: APIError.serverOutdated) {
            try await harness.store.signIn(email: "pranav@example.com", password: "hunter22")
        }
        #expect(harness.store.state == .signedOut)
        #expect(harness.token() == nil)
        let message = error.flatMap { SignInViewModel.message(for: $0, method: .email) }
        #expect(message == ErrorMessage.message(for: .serverOutdated))
    }

    @Test("If loading the account fails after sign-in, the new token is discarded")
    func signInThenLoadFails() async {
        let harness = SessionHarness(server: server)
        await harness.store.restore()
        harness.api.userResult = .failure(.server(statusCode: 500, code: "UNEXPECTED", message: nil))

        await #expect(throws: APIError.self) {
            try await harness.store.signIn(email: "pranav@example.com", password: "hunter22")
        }
        #expect(harness.store.state == .signedOut)
        #expect(harness.token() == nil)
        // The server session behind the discarded token is revoked.
        #expect(harness.api.signOutCount == 1)
    }

    @Test("Sign-up that needs email verification stays signed out and remembers the email")
    func signUpNeedsVerification() async throws {
        let harness = SessionHarness(server: server)
        await harness.store.restore()
        harness.api.signUpResult = .success(.verificationRequired)

        let result = try await harness.store.signUp(name: "New", email: "new@example.com", password: "secret123")

        #expect(result == .verificationRequired)
        #expect(harness.store.state == .signedOut)
        #expect(harness.store.prefilledEmail == "new@example.com")
        #expect(harness.token() == nil)
    }

    @Test("Sign-up that starts a session goes straight to onboarding")
    func signUpSignedIn() async throws {
        let harness = SessionHarness(server: server)
        await harness.store.restore()
        harness.api.baseCurrencyResult = .success(nil)

        _ = try await harness.store.signUp(name: "New", email: "new@example.com", password: "secret123")

        #expect(harness.token() == "signed.signup")
        #expect(harness.store.state == .needsOnboarding(StubSessionAPI.user))
    }

    @Test("OAuth sends a PKCE challenge and exchanges the code with the matching verifier")
    func oauthSignIn() async throws {
        let harness = SessionHarness(server: server)
        await harness.store.restore()

        try await harness.store.signIn(with: .github)

        let opened = try #require(harness.web.openedURLs.first)
        let challenge = URLComponents(url: opened, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "code_challenge" }?.value
        let exchange = try #require(harness.api.exchangeCalls.first)
        #expect(harness.web.callbackSchemes == ["moneymatter"])
        #expect(exchange.code == "one-time")
        #expect(PKCE.challenge(for: exchange.verifier) == challenge)
        #expect(harness.token() == "signed.oauth")
        #expect(harness.store.state == .signedIn(StubSessionAPI.user, baseCurrency: StubSessionAPI.euro))
    }

    @Test("An OAuth error callback throws without exchanging")
    func oauthRejected() async {
        let harness = SessionHarness(server: server)
        await harness.store.restore()
        harness.web.callback = .success(URL(string: "moneymatter://auth-callback?error=access_denied")!)

        await #expect(throws: SignInFailure.oauthRejected(code: "access_denied")) {
            try await harness.store.signIn(with: .google)
        }
        #expect(harness.api.exchangeCalls.isEmpty)
        #expect(harness.store.state == .signedOut)
    }

    @Test("Passkeys are offered only for the Associated Domains host")
    func passkeyAvailability() async {
        let other = SessionHarness(server: server)
        await other.store.restore()
        #expect(other.store.supportsPasskeys == false)
        await #expect(throws: SignInFailure.passkeysUnavailable) {
            try await other.store.signInWithPasskey()
        }

        let associated = SessionHarness(server: SessionHarness.passkeyServer)
        await associated.store.restore()
        #expect(associated.store.supportsPasskeys)
    }

    @Test("Passkey sign-in asserts for the server host and signs in")
    func passkeySignIn() async throws {
        let harness = SessionHarness(server: SessionHarness.passkeyServer)
        await harness.store.restore()

        try await harness.store.signInWithPasskey()

        #expect(harness.passkeys.relyingParties == ["budget.pkrishna.dev"])
        #expect(harness.token(for: SessionHarness.passkeyServer) == "signed.passkey")
        #expect(harness.store.state == .signedIn(StubSessionAPI.user, baseCurrency: StubSessionAPI.euro))
    }

    // MARK: Onboarding

    @Test("Choosing a base currency completes onboarding")
    func completeOnboarding() async throws {
        let harness = SessionHarness(server: server, token: "signed.saved")
        harness.api.baseCurrencyResult = .success(nil)
        await harness.store.restore()

        try await harness.store.completeOnboarding(currencyCode: "EUR")

        #expect(harness.api.setBaseCurrencyCalls == ["EUR"])
        #expect(harness.store.state == .signedIn(StubSessionAPI.user, baseCurrency: StubSessionAPI.euro))
    }

    @Test("A 422 because the base currency is already set reloads and continues")
    func onboardingAlreadySet() async throws {
        let harness = SessionHarness(server: server, token: "signed.saved")
        harness.api.baseCurrencyResult = .success(nil)
        await harness.store.restore()
        harness.api.setBaseCurrencyResult = .failure(.validation(message: "Base currency already set", issues: [], code: "VALIDATION_ERROR"))
        harness.api.baseCurrencyAfterSet = .some(StubSessionAPI.euro)

        try await harness.store.completeOnboarding(currencyCode: "EUR")

        #expect(harness.store.state == .signedIn(StubSessionAPI.user, baseCurrency: StubSessionAPI.euro))
    }

    @Test("A failed base-currency save keeps the user in onboarding")
    func onboardingFails() async {
        let harness = SessionHarness(server: server, token: "signed.saved")
        harness.api.baseCurrencyResult = .success(nil)
        await harness.store.restore()
        harness.api.setBaseCurrencyResult = .failure(.validation(message: "Base currency already set", issues: [], code: "VALIDATION_ERROR"))

        await #expect(throws: APIError.self) {
            try await harness.store.completeOnboarding(currencyCode: "EUR")
        }
        #expect(harness.store.state == .needsOnboarding(StubSessionAPI.user))
    }

    // MARK: Session end

    @Test("A 401 from any request ends the session and prefills the email")
    func unauthenticatedResponse() async {
        let harness = SessionHarness(server: server, token: "signed.saved")
        await harness.store.restore()

        harness.connection.simulateUnauthenticatedResponse(token: "signed.saved")

        #expect(harness.store.state == .signedOut)
        #expect(harness.store.prefilledEmail == "pranav@example.com")
        #expect(harness.token() == nil)
        #expect(harness.sessionEndedCount() == 1)
    }

    @Test("A 401 while signed out changes nothing")
    func unauthenticatedWhileSignedOut() async {
        let harness = SessionHarness(server: server)
        await harness.store.restore()

        harness.connection.simulateUnauthenticatedResponse(token: "anything")

        #expect(harness.store.state == .signedOut)
        #expect(harness.sessionEndedCount() == 0)
    }

    @Test("A late 401 for a token that was already replaced is ignored")
    func staleUnauthenticatedResponse() async throws {
        let harness = SessionHarness(server: server)
        await harness.store.restore()
        try await harness.store.signIn(email: "pranav@example.com", password: "hunter22")

        harness.connection.simulateUnauthenticatedResponse(token: "signed.previous-session")

        #expect(harness.store.state == .signedIn(StubSessionAPI.user, baseCurrency: StubSessionAPI.euro))
        #expect(harness.token() == "signed.email")
    }

    @Test("Sign out revokes the token on the server, then clears it")
    func signOut() async {
        let harness = SessionHarness(server: server, token: "signed.saved")
        await harness.store.restore()

        await harness.store.signOut()

        #expect(harness.api.signOutCount == 1)
        #expect(harness.token() == nil)
        #expect(harness.store.state == .signedOut)
        #expect(harness.store.prefilledEmail == nil)
        #expect(harness.servers.server == server)
        #expect(harness.sessionEndedCount() == 1)
    }
}
