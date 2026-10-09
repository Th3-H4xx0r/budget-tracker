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

    /// The form carries its own large title, so the bar title shows only for the message states.
    private var showsForm: Bool {
        session.signupsOpen != false && !model.needsEmailVerification
    }

    var body: some View {
        Group {
            if session.signupsOpen == false {
                ContentUnavailableView(
                    "Sign-Ups Are Closed",
                    systemImage: "person.crop.circle.badge.xmark",
                    description: Text("This server isn't accepting new accounts. Ask the person who runs it for access.")
                )
                .background { AuthBackground() }
            } else if model.needsEmailVerification {
                ContentUnavailableView {
                    Label("Check Your Email", systemImage: "envelope.badge")
                } description: {
                    Text("Check your email to verify your account, then sign in.")
                } actions: {
                    Button("Back to Sign In") { dismiss() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
                .background { AuthBackground() }
            } else {
                form
            }
        }
        .navigationTitle(showsForm ? Text(verbatim: "") : Text("Create Account"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var form: some View {
        AuthScreen {
            AuthHeader(
                title: Text("Create Your Account"),
                subtitle: Text("Your budget, accounts, and transactions are stored on \(session.server?.host ?? "your server")."),
                systemImage: "person.fill.badge.plus"
            )

            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    AuthFieldCard {
                        AuthFieldRow(systemImage: "person", isActive: focusedField == .name) {
                            TextField("Name", text: $model.name, prompt: Text("Name"))
                                .textContentType(.name)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .name)
                                .onSubmit { focusedField = .email }
                        }
                        AuthFieldRow(systemImage: "envelope", isActive: focusedField == .email) {
                            TextField("Email", text: $model.email, prompt: Text("Email"))
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .focused($focusedField, equals: .email)
                                .onSubmit { focusedField = .password }
                        }
                        AuthFieldRow(systemImage: "lock", isActive: focusedField == .password) {
                            PasswordField(title: "Password", text: $model.password, focus: $focusedField, focusValue: .password)
                                .textContentType(.newPassword)
                                .submitLabel(.go)
                                .onSubmit { Task { await model.signUp(session: session) } }
                        }
                    }

                    PasswordStrengthHint(
                        password: model.password,
                        minimumLength: SignUpViewModel.minimumPasswordLength,
                        isTooShort: model.isPasswordTooShort
                    )
                    .padding(.horizontal, 4)
                }

                if let message = model.errorMessage {
                    AuthBanner(message: message)
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
            .animation(.snappy, value: model.errorMessage)

            AuthFooterLink(prompt: "Already have an account?", action: "Sign in") {
                dismiss()
            }
            .disabled(model.isWorking)
        }
        .sensoryFeedback(.error, trigger: model.errorMessage) { _, new in new != nil }
    }
}
