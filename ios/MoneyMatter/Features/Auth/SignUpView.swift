import MoneyMatterKit
import SwiftUI

/// Name, email, and password. Hidden behind a closed-sign-ups message when the server
/// doesn't accept new accounts, and replaced by a check-your-email message when it requires
/// verification.
struct SignUpView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model = SignUpViewModel()
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case email
        case password
    }

    var body: some View {
        Group {
            if session.signupsOpen == false {
                ContentUnavailableView(
                    "Sign-Ups Are Closed",
                    systemImage: "person.crop.circle.badge.xmark",
                    description: Text("This server isn't accepting new accounts. Ask the person who runs it for access.")
                )
            } else if model.needsEmailVerification {
                ContentUnavailableView {
                    Label("Check Your Email", systemImage: "envelope.badge")
                } description: {
                    Text("Check your email to verify your account, then sign in.")
                } actions: {
                    Button("Back to Sign In") { dismiss() }
                        .buttonStyle(.glassProminent)
                }
            } else {
                form
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 24) {
                AuthHeader(
                    title: "Create Your Account",
                    subtitle: Text("Your budget, accounts, and transactions are stored on \(session.server?.host ?? "your server")."),
                    systemImage: "person.crop.circle.badge.plus"
                )

                VStack(spacing: 12) {
                    AuthFieldGroup {
                        TextField("Name", text: $model.name)
                            .textContentType(.name)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .name)
                            .onSubmit { focusedField = .email }
                        TextField("Email", text: $model.email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .password }
                        SecureField("Password", text: $model.password)
                            .textContentType(.newPassword)
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
                            .onSubmit { Task { await model.signUp(session: session) } }
                    }

                    if let message = model.errorMessage {
                        FormMessage(text: message)
                    } else {
                        FormMessage(
                            text: String(localized: "Use at least \(SignUpViewModel.minimumPasswordLength) characters for your password."),
                            isError: model.isPasswordTooShort
                        )
                    }

                    Button {
                        Task { await model.signUp(session: session) }
                    } label: {
                        ProgressButtonLabel(title: "Create Account", isWorking: model.isWorking)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!model.canSubmit)
                }
            }
            .authColumn()
        }
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.error, trigger: model.errorMessage) { _, new in new != nil }
    }
}
