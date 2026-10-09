import Foundation

/// One typed factory per API call the app makes. Paths are relative to `/api/v1`.
public enum Endpoints {}

// MARK: - Auth (better-auth routes use bare bodies)

extension Endpoints {
    struct EmailSignInBody: Encodable, Sendable {
        let email: String
        let password: String
    }

    struct EmailSignUpBody: Encodable, Sendable {
        let name: String
        let email: String
        let password: String
        let callbackURL: String
    }

    struct OAuthExchangeBody: Encodable, Sendable {
        let code: String
        let codeVerifier: String
    }

    struct EmptyBody: Encodable, Sendable {}

    /// `POST /auth/sign-in/email`. The token is in the `set-auth-token` header.
    public static func signInEmail(email: String, password: String) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/auth/sign-in/email", body: EmailSignInBody(email: email, password: password), format: .bare)
    }

    /// `POST /auth/sign-up/email`. A null body `token` means email verification is required.
    /// `callbackURL` must be one of the server's trusted origins.
    public static func signUpEmail(name: String, email: String, password: String, callbackURL: URL) -> Endpoint<String?> {
        Endpoint<SignUpResponse>(
            .post,
            "/auth/sign-up/email",
            body: EmailSignUpBody(name: name, email: email, password: password, callbackURL: callbackURL.absoluteString),
            format: .bare
        )
        .map(\.token)
    }

    /// `GET /auth/get-session`: `nil` when the token isn't valid.
    public static func session() -> Endpoint<AuthSession?> {
        Endpoint(.get, "/auth/get-session", format: .bare)
    }

    /// `POST /auth/sign-out`: revokes the session behind the bearer token.
    public static func signOut() -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/auth/sign-out", body: EmptyBody(), format: .bare)
    }

    /// `GET /auth/signups-open` (no auth).
    public static func signupsOpen() -> Endpoint<Bool> {
        Endpoint<SignupsOpenResponse>(.get, "/auth/signups-open").map(\.signupsOpen)
    }

    /// The URL to open in `ASWebAuthenticationSession` to start a native OAuth sign-in.
    public static func nativeOAuthStartURL(server: ServerEndpoint, provider: OAuthProvider, codeChallenge: String) -> URL {
        var builder = QueryBuilder()
        builder.add("provider", provider.rawValue)
        builder.add("code_challenge", codeChallenge)
        let url = server.apiBaseURL.appending(path: "/auth/native/oauth/start")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = QueryBuilder.percentEncodedQuery(builder.items)
        return components?.url ?? url
    }

    /// `POST /auth/native/oauth/exchange`: trades the one-time code for the bearer token.
    public static func exchangeOAuthCode(_ code: String, codeVerifier: String) -> Endpoint<String> {
        Endpoint<TokenResponse>(
            .post,
            "/auth/native/oauth/exchange",
            body: OAuthExchangeBody(code: code, codeVerifier: codeVerifier),
            format: .envelopeOrBare
        )
        .map(\.token)
    }

    /// `GET /auth/passkey/generate-authenticate-options`. Sets the challenge cookie, so it
    /// must go through a client from `withEphemeralCookieJar()`.
    public static func passkeyAuthenticationOptions() -> Endpoint<PasskeyRequestOptions> {
        Endpoint(.get, "/auth/passkey/generate-authenticate-options", format: .bare)
    }

    /// `POST /auth/passkey/verify-authentication`. The token is in the `set-auth-token` header.
    public static func verifyPasskeyAuthentication(_ assertion: PasskeyAssertion) -> Endpoint<EmptyResponse> {
        Endpoint(
            .post,
            "/auth/passkey/verify-authentication",
            body: PasskeyVerificationRequest(assertion: assertion),
            format: .bare
        )
    }
}
