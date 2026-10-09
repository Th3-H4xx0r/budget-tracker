import MoneyMatterKit
import SwiftUI

/// Email and password, plus passkey (only for the Associated Domains host), Google, and GitHub.
struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model = SignInViewModel()
    @State private var showsSignUp = false
    @State private var confirmsChangeServer = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        AuthScreen {
            header
            credentials
            alternativeMethods
            footer
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
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

    private var header: some View {
        AuthHeader(
            title: Text(verbatim: "MoneyMatter"),
            subtitle: Text("Sign in to see your accounts, transactions, and budget.")
        ) {
            if let server = session.server {
                ServerChip(host: server.hostAndPort) {
                    confirmsChangeServer = true
                }
                .disabled(model.isWorking)
            }
        }
    }

    private var credentials: some View {
        VStack(spacing: 16) {
            AuthFieldCard {
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
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { Task { await model.signIn(session: session) } }
                }
            }

            if let message = model.errorMessage {
                AuthBanner(message: message)
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
        .animation(.snappy, value: model.errorMessage)
    }

    private var alternativeMethods: some View {
        VStack(spacing: 16) {
            AuthSeparator(title: "or continue with")

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    if session.supportsPasskeys {
                        Button {
                            Task { await model.signInWithPasskey(session: session) }
                        } label: {
                            ProgressButtonLabel(
                                title: "Sign In with Passkey",
                                systemImage: "person.badge.key.fill",
                                isWorking: model.activeMethod == .passkey
                            )
                        }
                    }

                    // Stacked at accessibility text sizes so neither provider name truncates.
                    let providerLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 12))
                        : AnyLayout(HStackLayout(spacing: 12))
                    providerLayout {
                        Button {
                            Task { await model.signIn(with: .google, session: session) }
                        } label: {
                            ProgressButtonLabel(
                                title: "Google",
                                image: Image("GoogleLogo").renderingMode(.original),
                                isWorking: model.activeMethod == .oauth(.google)
                            )
                        }
                        .accessibilityLabel(Text("Continue with Google"))

                        Button {
                            Task { await model.signIn(with: .github, session: session) }
                        } label: {
                            ProgressButtonLabel(
                                title: "GitHub",
                                image: Image("GitHubLogo").renderingMode(.template),
                                isWorking: model.activeMethod == .oauth(.github)
                            )
                        }
                        .accessibilityLabel(Text("Continue with GitHub"))
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(model.isWorking)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if session.signupsOpen != false {
            AuthFooterLink(prompt: "Don't have an account?", action: "Create one") {
                showsSignUp = true
            }
            .disabled(model.isWorking)
        }
    }
}
