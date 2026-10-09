import MoneyMatterKit
import SwiftUI

/// Picks the server. The address is checked with `GET /auth/signups-open` before it's saved.
struct ServerView: View {
    @Environment(SessionStore.self) private var session
    @State private var address = AppConfig.defaultServerAddress
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            AuthScreen {
                AuthHeader(
                    title: Text(verbatim: "MoneyMatter"),
                    subtitle: Text("Enter the address of the MoneyMatter server that holds your budget.")
                )

                VStack(spacing: 16) {
                    AuthFieldCard {
                        AuthFieldRow(systemImage: "link", isActive: isFieldFocused) {
                            TextField("Server Address", text: $address, prompt: Text(verbatim: "budget.example.com"))
                                .textContentType(.URL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.go)
                                .focused($isFieldFocused)
                                .onSubmit { Task { await connect() } }
                        }
                    }

                    if let errorMessage {
                        AuthBanner(message: errorMessage)
                    }

                    Button {
                        Task { await connect() }
                    } label: {
                        ProgressButtonLabel(title: "Connect", isWorking: isConnecting, spinnerTint: DS.Palette.onAccent)
                    }
                    .dsGlassProminentButton()
                    .controlSize(.large)
                    .disabled(isConnecting || address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .animation(.snappy, value: errorMessage)

                VStack(spacing: 6) {
                    Text("MoneyMatter is self-hosted, so your data stays on a server you or your household runs.")
                    Text("Use https:// for servers on the internet. http:// works only for localhost and .local addresses.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
        }
    }

    private func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            try await session.connect(toServer: address)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    static func message(for error: any Error) -> String {
        switch error {
        case ServerURLError.invalid:
            return String(localized: "Enter a server address, like budget.example.com.")
        case ServerURLError.insecureScheme:
            return String(localized: "Use https:// for this server. Plain http:// works only for localhost and .local addresses.")
        case let apiError as APIError:
            switch apiError {
            case .network:
                return String(localized: "Can't reach this server. Check the address and your connection.")
            case .notFound, .decoding:
                return String(localized: "This address doesn't look like a MoneyMatter server.")
            default:
                return ErrorMessage.message(for: apiError)
            }
        default:
            return ErrorMessage.inline(for: error)
        }
    }
}

#Preview {
    ServerView()
        .environment(AppDependencies.live().session)
}
