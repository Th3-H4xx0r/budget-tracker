import Foundation

/// Sign-in calls that return the signed bearer token, read from `set-auth-token`.
extension APIClient {
    public func signIn(email: String, password: String) async throws -> String {
        let response = try await response(for: Endpoints.signInEmail(email: email, password: password))
        return try Self.bearerToken(from: response)
    }

    /// Signs up with the sign-up callback on the server's own origin, as the web client does.
    public func signUp(name: String, email: String, password: String) async throws -> SignUpResult {
        let callbackURL = server.origin.appending(path: "auth/callback")
        let response = try await response(
            for: Endpoints.signUpEmail(name: name, email: email, password: password, callbackURL: callbackURL)
        )
        guard response.value != nil else { return .verificationRequired }
        return .signedIn(token: try Self.bearerToken(from: response))
    }

    public func exchangeOAuthCode(_ code: String, codeVerifier: String) async throws -> String {
        try await send(Endpoints.exchangeOAuthCode(code, codeVerifier: codeVerifier))
    }

    /// Runs the passkey ceremony on a throwaway cookie jar: fetch options (which sets the
    /// challenge cookie), let `assert` produce the platform assertion, then verify it.
    public func signInWithPasskey(
        assert: @Sendable (PasskeyRequestOptions) async throws -> PasskeyAssertion
    ) async throws -> String {
        let ceremony = withEphemeralCookieJar()
        defer { ceremony.finishAndInvalidate() }
        let options = try await ceremony.send(Endpoints.passkeyAuthenticationOptions())
        let assertion = try await assert(options)
        let response = try await ceremony.response(for: Endpoints.verifyPasskeyAuthentication(assertion))
        return try Self.bearerToken(from: response)
    }

    static func bearerToken<Value>(from response: APIResponse<Value>) throws -> String {
        guard let token = response.header(AuthHeaders.setAuthToken), !token.isEmpty else {
            throw APIError.decoding("The server didn't return a session token. It may not support native sign-in.")
        }
        return token
    }
}
