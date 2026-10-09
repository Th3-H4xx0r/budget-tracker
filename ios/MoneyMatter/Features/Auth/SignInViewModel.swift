import Foundation
import MoneyMatterKit
import Observation

/// State for the sign-in form. One method runs at a time.
@Observable
final class SignInViewModel {
    enum Method: Equatable {
        case email
        case passkey
        case oauth(OAuthProvider)
    }

    var email = ""
    var password = ""
    private(set) var activeMethod: Method?
    private(set) var errorMessage: String?

    var isWorking: Bool { activeMethod != nil }

    var canSubmitEmail: Bool {
        !isWorking && trimmedEmail.contains("@") && !password.isEmpty
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prefill(email prefilled: String?) {
        if let prefilled, email.isEmpty { email = prefilled }
    }

    func signIn(session: SessionStore) async {
        guard canSubmitEmail else { return }
        await run(.email) { try await session.signIn(email: trimmedEmail, password: password) }
    }

    func signInWithPasskey(session: SessionStore) async {
        await run(.passkey) { try await session.signInWithPasskey() }
    }

    func signIn(with provider: OAuthProvider, session: SessionStore) async {
        await run(.oauth(provider)) { try await session.signIn(with: provider) }
    }

    private func run(_ method: Method, _ work: () async throws -> Void) async {
        guard activeMethod == nil else { return }
        activeMethod = method
        errorMessage = nil
        defer { activeMethod = nil }
        do {
            try await work()
            password = ""
        } catch {
            errorMessage = Self.message(for: error, method: method)
        }
    }

    /// `nil` when the person cancelled, which needs no message.
    static func message(for error: any Error, method: Method) -> String? {
        switch error {
        case is AuthenticationCancelled:
            return nil
        case SignInFailure.oauthRejected:
            return String(localized: "Sign-in was cancelled or denied. Try again, or use another method.")
        case SignInFailure.unexpectedCallback:
            return String(localized: "Sign-in didn't finish. Try again.")
        case SignInFailure.passkeysUnavailable:
            return String(localized: "Passkeys aren't available for this server.")
        case SignInFailure.noServer:
            return String(localized: "Choose a server first.")
        default:
            let apiError = APIError(error)
            if apiError.isCancellation { return nil }
            if case .unauthenticated(let message) = apiError {
                if method == .email { return String(localized: "Incorrect email or password.") }
                return message ?? String(localized: "Sign-in expired. Try again.")
            }
            return apiError.serverMessage ?? ErrorMessage.message(for: apiError)
        }
    }
}
