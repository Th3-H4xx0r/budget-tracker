import MoneyMatterKit
import SwiftUI

/// Settings > Security > Password: change the password, or set one on an account that only
/// signs in with Google, GitHub, or a passkey.
struct PasswordScreen: View {
    @Environment(AppServices.self) private var services

    @State private var state: LoadState<Bool> = .idle
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: LocalizedStringKey?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case current, new, confirm }

    private static let minimumLength = 8

    var body: some View {
        content
            .navigationTitle("Password")
            .task { if case .idle = state { await load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let hasPassword):
            form(hasPassword: hasPassword)
        case .idle, .loading:
            form(hasPassword: true)
                .redactedWhileLoading(true)
        }
    }

    private func form(hasPassword: Bool) -> some View {
        Form {
            Section {
                if hasPassword {
                    SecureField("Current Password", text: $currentPassword)
                        .textContentType(.password)
                        .focused($focusedField, equals: .current)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .new }
                }
                SecureField("New Password", text: $newPassword)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .new)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .confirm }
                SecureField("Confirm New Password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .confirm)
                    .submitLabel(.done)
                    .onSubmit { if canSubmit(hasPassword: hasPassword) { Task { await submit(hasPassword: hasPassword) } } }
            } header: {
                Text(hasPassword ? "Change Password" : "Set a Password")
            } footer: {
                if !hasPassword {
                    Text("You sign in with Google, GitHub, or a passkey. Add a password to also sign in with your email.")
                }
            }

            if !newPassword.isEmpty {
                Section {
                    strengthView
                    if newPassword.count < Self.minimumLength {
                        Label("Use at least 8 characters.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                    if !confirmPassword.isEmpty && confirmPassword != newPassword {
                        Label("Passwords don't match.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
                .font(.subheadline)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if let successMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }

            Section {
                Button {
                    Task { await submit(hasPassword: hasPassword) }
                } label: {
                    HStack {
                        Text(hasPassword ? "Change Password" : "Set Password")
                        if isSubmitting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!canSubmit(hasPassword: hasPassword) || isSubmitting)
            }
        }
    }

    private var strengthView: some View {
        let score = Self.strength(of: newPassword)
        return VStack(alignment: .leading, spacing: 6) {
            Gauge(value: Double(score), in: 0...4) {
                EmptyView()
            }
            .gaugeStyle(.linearCapacity)
            .tint(strengthColor(score))
            .accessibilityHidden(true)
            Text("Strength: \(Text(strengthLabel(score)))")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Mirrors the web meter: length 8 and 12, mixed case, a digit, and a symbol each add a point (max 4).
    static func strength(of password: String) -> Int {
        guard !password.isEmpty else { return 0 }
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.contains(where: \.isLowercase) && password.contains(where: \.isUppercase) { score += 1 }
        if password.contains(where: \.isNumber) { score += 1 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { score += 1 }
        return min(score, 4)
    }

    private func strengthLabel(_ score: Int) -> LocalizedStringKey {
        switch score {
        case 0: "Very Weak"
        case 1: "Weak"
        case 2: "Fair"
        case 3: "Strong"
        default: "Very Strong"
        }
    }

    private func strengthColor(_ score: Int) -> Color {
        switch score {
        case 0, 1: .red
        case 2: .yellow
        default: .green
        }
    }

    private func canSubmit(hasPassword: Bool) -> Bool {
        (!hasPassword || !currentPassword.isEmpty)
            && newPassword.count >= Self.minimumLength
            && newPassword == confirmPassword
    }

    // MARK: Actions

    private func load() async {
        state = .loading
        do {
            let client = try settingsSectionsClient(services)
            let accounts = try await client.send(Endpoints.settingsLinkedAccounts())
            state = .loaded(accounts.contains { $0.provider == .credential })
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation { state = .failed(apiError) }
        }
    }

    private func submit(hasPassword: Bool) async {
        guard canSubmit(hasPassword: hasPassword) else { return }
        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }
        do {
            let client = try settingsSectionsClient(services)
            if hasPassword {
                _ = try await client.send(Endpoints.settingsChangePassword(currentPassword: currentPassword, newPassword: newPassword))
                successMessage = "Password changed."
            } else {
                _ = try await client.send(Endpoints.settingsSetPassword(newPassword: newPassword))
                successMessage = "Password set. You can now sign in with your email."
                state = .loaded(true)
            }
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            focusedField = nil
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if case .server(_, let code, _) = apiError, code == SettingsSecurityErrorCode.passwordAlreadySet {
                state = .loaded(true)
            }
            if case .validation(_, _, let code) = apiError, code == SettingsSecurityErrorCode.passwordAlreadySet {
                state = .loaded(true)
            }
            errorMessage = ErrorMessage.message(for: apiError)
        }
    }
}
