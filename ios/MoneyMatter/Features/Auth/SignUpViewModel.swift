import Foundation
import MoneyMatterKit
import Observation

/// State for the sign-up form.
@Observable
final class SignUpViewModel {
    static let minimumPasswordLength = 8

    var name = ""
    var email = ""
    var password = ""
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    /// The server sent a verification email; the person signs in after confirming it.
    private(set) var needsEmailVerification = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isPasswordTooShort: Bool {
        !password.isEmpty && password.count < Self.minimumPasswordLength
    }

    var canSubmit: Bool {
        !isWorking && !trimmedName.isEmpty && trimmedEmail.contains("@") && password.count >= Self.minimumPasswordLength
    }

    func signUp(session: SessionStore) async {
        guard canSubmit else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await session.signUp(name: trimmedName, email: trimmedEmail, password: password)
            if result == .verificationRequired {
                needsEmailVerification = true
                password = ""
            }
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            errorMessage = apiError.serverMessage ?? ErrorMessage.message(for: apiError)
        }
    }
}
