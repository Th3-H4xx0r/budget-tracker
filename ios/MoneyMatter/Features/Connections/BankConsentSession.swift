import AuthenticationServices
import MoneyMatterKit
import SwiftUI

/// Runs an Enable Banking consent in `ASWebAuthenticationSession`. The bank redirects to
/// `https://<server>/bank-callback`, which the session intercepts and hands back, so the
/// app completes the connection itself, as the web callback page does.
final class BankConsentSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// Opens `authURL` and returns the callback URL, or throws `AuthenticationCancelled`.
    func run(authURL: URL, server: ServerEndpoint) async throws -> URL {
        session?.cancel()
        return try await withCheckedThrowingContinuation { continuation in
            let callback = ASWebAuthenticationSession.Callback.https(host: server.host, path: "/bank-callback")
            let session = ASWebAuthenticationSession(url: authURL, callback: callback) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthenticationCancelled())
                } else {
                    continuation.resume(throwing: error ?? URLError(.unknown))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() {
                continuation.resume(throwing: URLError(.cannotLoadFromNetwork))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        PresentationAnchor.current()
    }
}

enum BankConsentError: LocalizedError {
    case denied(String?)
    case missingParameters
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .denied(let message): message ?? String(localized: "The bank didn't authorize the connection.")
        case .missingParameters: String(localized: "The bank returned without an authorization code.")
        case .invalidURL: String(localized: "The server returned an invalid authorization link.")
        }
    }
}

enum BankConsentFlow {
    /// Opens the consent page and completes the connection with the callback's `code` and
    /// `state`. Returns `false` when the person cancels.
    static func authorize(connectionID: String, authURL: String, client: APIClient) async throws -> Bool {
        guard let url = URL(string: authURL) else { throw BankConsentError.invalidURL }
        let callbackURL: URL
        do {
            callbackURL = try await BankConsentSession().run(authURL: url, server: client.server)
        } catch is AuthenticationCancelled {
            return false
        }
        switch EnableBankingCallbackResult(callbackURL: callbackURL) {
        case .authorized(let code, let state):
            _ = try await client.send(Endpoints.completeEnableBankingConsent(
                EnableBankingOAuthCallbackRequest(connectionId: connectionID, code: code, state: state)
            ))
            return true
        case .denied(let message):
            throw BankConsentError.denied(message)
        case .missingParameters:
            throw BankConsentError.missingParameters
        }
    }
}

extension ErrorAlert {
    /// Alerts for consent failures, which aren't `APIError`s.
    static func bankConsent(_ error: any Error) -> ErrorAlert? {
        if let consent = error as? BankConsentError {
            return ErrorAlert(title: String(localized: "Couldn't Connect"), message: consent.errorDescription ?? "")
        }
        return ErrorAlert(error)
    }
}
