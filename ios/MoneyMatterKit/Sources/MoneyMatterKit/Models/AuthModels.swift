import Foundation

/// better-auth's user record (distinct from the app `User`).
public struct AuthUser: Sendable, Hashable, Decodable {
    public let id: String
    public let email: String?
    public let name: String?
    public let emailVerified: Bool?
    public let image: String?
}

/// `GET /auth/get-session`. The endpoint returns `null` when the token isn't valid.
public struct AuthSession: Sendable, Hashable, Decodable {
    public struct Session: Sendable, Hashable, Decodable {
        public let id: String?
        public let expiresAt: Date?
    }

    public let session: Session
    public let user: AuthUser
}

/// `GET /auth/signups-open`.
struct SignupsOpenResponse: Decodable {
    let signupsOpen: Bool
}

/// The body of email sign-in and passkey verification. The bearer token comes from the
/// `set-auth-token` header, not from here.
struct AuthUserResponse: Decodable {
    let user: AuthUser?
}

/// `POST /auth/sign-up/email`. `token` is null when the server requires email verification.
struct SignUpResponse: Decodable {
    let token: String?
    let user: AuthUser?
}

/// `POST /auth/native/oauth/exchange`.
struct TokenResponse: Decodable {
    let token: String
}

/// What a sign-up produced.
public enum SignUpResult: Sendable, Equatable {
    case signedIn(token: String)
    /// The server sent a verification email; the user signs in after confirming it.
    case verificationRequired
}

/// Header name the bearer plugin uses to return the signed session token.
public enum AuthHeaders {
    public static let setAuthToken = "set-auth-token"
}

/// The `moneymatter://auth-callback?...` redirect that ends the native OAuth flow.
public enum OAuthCallback: Sendable, Equatable {
    case code(String)
    case error(String)

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        if let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            self = .code(code)
        } else if let error = items.first(where: { $0.name == "error" })?.value {
            self = .error(error)
        } else {
            return nil
        }
    }
}
