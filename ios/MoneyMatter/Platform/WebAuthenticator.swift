import AuthenticationServices
import Foundation

/// Runs a browser sign-in and returns the callback URL.
protocol WebAuthenticating: AnyObject {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// `ASWebAuthenticationSession` with an ephemeral browser session, so no provider cookies
/// outlive the sign-in.
final class WebAuthenticator: NSObject, WebAuthenticating, ASWebAuthenticationPresentationContextProviding {
    /// Retained while the browser sheet is up.
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        // Only one sign-in at a time: a new one cancels the sheet still on screen.
        session?.cancel()

        var startedSession: ASWebAuthenticationSession?
        defer {
            if let startedSession, session === startedSession { session = nil }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { callbackURL, error in
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        continuation.resume(throwing: AuthenticationCancelled())
                    } else {
                        continuation.resume(throwing: error ?? URLError(.unknown))
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                self.session = session
                startedSession = session
                if !session.start() {
                    continuation.resume(throwing: URLError(.cannotLoadFromNetwork))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.session?.cancel() }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        PresentationAnchor.current()
    }
}
