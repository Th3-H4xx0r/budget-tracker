import Foundation
import MoneyMatterKit

/// better-auth calls. Sign-in methods return the signed bearer token.
protocol AuthServicing: Sendable {
    /// `GET /auth/signups-open`; also used to check that a server address is a MoneyMatter server.
    func signupsOpen() async throws -> Bool
    /// `nil` when the stored token is no longer valid.
    func currentSession() async throws -> AuthSession?
    func signIn(email: String, password: String) async throws -> String
    func signUp(name: String, email: String, password: String) async throws -> SignUpResult
    /// The page `ASWebAuthenticationSession` opens to start Google or GitHub sign-in.
    func oauthStartURL(provider: OAuthProvider, codeChallenge: String) -> URL
    func exchangeOAuthCode(_ code: String, codeVerifier: String) async throws -> String
    func signInWithPasskey(
        assert: @Sendable (PasskeyRequestOptions) async throws -> PasskeyAssertion
    ) async throws -> String
    /// Revokes the session behind the current token.
    func signOut() async throws
}

/// The user's profile and currencies.
protocol UserServicing: Sendable {
    func currentUser() async throws -> User
    /// `nil` until onboarding picks one.
    func baseCurrency() async throws -> UserCurrency?
    func setBaseCurrency(code: String) async throws -> UserCurrency
    func userCurrencies() async throws -> [UserCurrency]
    /// Every currency the server knows (`GET /models/currencies`).
    func allCurrencies() async throws -> [Currency]
    func addUserCurrencies(codes: [String]) async throws -> AddedUserCurrencies
}

/// What `SessionStore` needs from the server.
typealias SessionAPI = AuthServicing & UserServicing
