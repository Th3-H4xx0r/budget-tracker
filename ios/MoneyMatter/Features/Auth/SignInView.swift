import MoneyMatterKit
import SwiftUI

/// Email and password, plus passkey (only for the Associated Domains host), Google, and GitHub.
struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = SignInViewModel()
    @State private var showsSignUp = false
    @State private var confirmsChangeServer = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AuthHeader(
                    title: "Sign In",
                    subtitle: Text("Sign in to see your accounts, transactions, and budget on \(session.server?.host ?? "your server").")
                )

                VStack(spacing: 12) {
                    AuthFieldGroup {
                        TextField("Email", text: $model.email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .password }
                        SecureField("Password", text: $model.password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
                            .onSubmit { Task { await model.signIn(session: session) } }
                    }

                    if let message = model.errorMessage {
                        FormMessage(text: message)
                    }

                    Button {
                        Task { await model.signIn(session: session) }
                    } label: {
                        ProgressButtonLabel(title: "Sign In", isWorking: model.activeMethod == .email)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!model.canSubmitEmail)
                }

                alternativeMethods

                footer
            }
            .authColumn()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsSignUp) {
            SignUpView()
        }
        .confirmationDialog("Change Server?", isPresented: $confirmsChangeServer, titleVisibility: .visible) {
            Button("Change Server") {
                Task { await session.changeServer() }
            }
        } message: {
            Text("You'll choose a different MoneyMatter server.")
        }
        .sensoryFeedback(.error, trigger: model.errorMessage) { _, new in new != nil }
        .onAppear { model.prefill(email: session.prefilledEmail) }
        .task { await session.refreshSignupsOpen() }
    }

    private var alternativeMethods: some View {
        VStack(spacing: 12) {
            HStack {
                VStack { Divider() }
                Text("or")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                VStack { Divider() }
            }

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    if session.supportsPasskeys {
                        Button {
                            Task { await model.signInWithPasskey(session: session) }
                        } label: {
                            ProgressButtonLabel(title: "Sign In with Passkey", systemImage: "person.badge.key.fill", isWorking: model.activeMethod == .passkey)
                        }
                    }
                    Button {
                        Task { await model.signIn(with: .google, session: session) }
                    } label: {
                        ProgressButtonLabel(title: "Continue with Google", systemImage: "globe", isWorking: model.activeMethod == .oauth(.google))
                    }
                    Button {
                        Task { await model.signIn(with: .github, session: session) }
                    } label: {
                        ProgressButtonLabel(
                            title: "Continue with GitHub",
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            isWorking: model.activeMethod == .oauth(.github)
                        )
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(model.isWorking)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if session.signupsOpen != false {
                Button("Create an Account") {
                    showsSignUp = true
                }
                .disabled(model.isWorking)
            }
            Button("Change Server") {
                confirmsChangeServer = true
            }
            .font(.footnote)
            .disabled(model.isWorking)
        }
        .frame(minHeight: 44)
    }
}
