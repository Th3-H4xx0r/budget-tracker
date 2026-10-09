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
            ScrollView {
                VStack(spacing: 24) {
                    AuthHeader(
                        title: "Connect to Your Server",
                        subtitle: Text("Enter the address of the MoneyMatter server that holds your budget."),
                        systemImage: "server.rack"
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        AuthFieldGroup {
                            TextField("Server Address", text: $address, prompt: Text(verbatim: "budget.example.com"))
                                .textContentType(.URL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.go)
                                .focused($isFieldFocused)
                                .onSubmit { Task { await connect() } }
                        }
                        if let errorMessage {
                            FormMessage(text: errorMessage)
                        } else {
                            FormMessage(
                                text: String(localized: "Use https:// for servers on the internet. http:// works only for localhost and .local addresses."),
                                isError: false
                            )
                        }
                    }

                    Button {
                        Task { await connect() }
                    } label: {
                        ProgressButtonLabel(title: "Continue", isWorking: isConnecting)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(isConnecting || address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .authColumn()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
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
