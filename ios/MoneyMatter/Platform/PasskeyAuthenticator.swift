import AuthenticationServices
import Foundation
import MoneyMatterKit

/// Produces a platform passkey assertion for a server's challenge.
protocol PasskeyAuthenticating: AnyObject, Sendable {
    func assertion(for options: PasskeyRequestOptions, relyingParty: String) async throws -> PasskeyAssertion
}

enum PasskeyError: Error, Equatable {
    case unexpectedCredential
}

/// Runs an `ASAuthorizationController` assertion for an existing passkey. The relying party
/// must appear in the app's Associated Domains (`webcredentials:`).
final class PasskeyAuthenticator: NSObject, PasskeyAuthenticating,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<PasskeyAssertion, any Error>?
    private var controller: ASAuthorizationController?

    func assertion(for options: PasskeyRequestOptions, relyingParty: String) async throws -> PasskeyAssertion {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
        let request = provider.createCredentialAssertionRequest(challenge: options.challenge)
        request.allowedCredentials = options.allowedCredentialIDs.map {
            ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
        }
        if let preference = options.userVerification {
            request.userVerificationPreference = ASAuthorizationPublicKeyCredentialUserVerificationPreference(rawValue: preference)
        }

        // Only one request at a time: a new one cancels the one still on screen.
        cancelPending()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                self.controller = controller
                controller.performRequests()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelPending() }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === self.controller else { return }
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            finish(.failure(PasskeyError.unexpectedCredential))
            return
        }
        finish(.success(PasskeyAssertion(
            credentialID: credential.credentialID,
            clientDataJSON: credential.rawClientDataJSON,
            authenticatorData: credential.rawAuthenticatorData ?? Data(),
            signature: credential.signature ?? Data(),
            userHandle: credential.userID
        )))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        guard controller === self.controller else { return }
        if let authorizationError = error as? ASAuthorizationError, authorizationError.code == .canceled {
            finish(.failure(AuthenticationCancelled()))
        } else {
            finish(.failure(error))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        PresentationAnchor.current()
    }

    private func cancelPending() {
        let pending = controller
        finish(.failure(AuthenticationCancelled()))
        pending?.cancel()
    }

    /// Resumes the waiting caller once; later callbacks from the same controller are ignored.
    private func finish(_ result: Result<PasskeyAssertion, any Error>) {
        controller = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
