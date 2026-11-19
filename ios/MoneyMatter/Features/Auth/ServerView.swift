import MoneyMatterKit
import SwiftUI

/// Picks the server. The address is checked with `GET /auth/signups-open` before it's saved.
struct ServerView: View {
    @Environment(SessionStore.self) private var session
    @State private var address = AppConfig.defaultServerAddress
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var showsCloudflareAccess = false
    @State private var showsScanner = false
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

                    cloudflareAccessFields

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
            .sheet(isPresented: $showsScanner) {
                CloudflareAccessScanner(expectedServer: nil) { payload in
                    address = payload.server.originString
                    clientId = payload.credentials.clientId
                    clientSecret = payload.credentials.clientSecret
                    showsCloudflareAccess = true
                }
            }
            .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
        }
    }

    private var cloudflareAccessFields: some View {
        DisclosureGroup("Cloudflare Access", isExpanded: $showsCloudflareAccess) {
            VStack(spacing: 12) {
                AuthFieldCard {
                    AuthFieldRow(systemImage: "person.badge.key", isActive: false) {
                        TextField("Client ID", text: $clientId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    AuthFieldRow(systemImage: "lock.shield", isActive: false) {
                        SecureField("Client Secret", text: $clientSecret)
                    }
                }

                Button("Scan QR Code", systemImage: "qrcode.viewfinder") {
                    showsScanner = true
                }
                .buttonStyle(.glass)

                Text("Only needed if your server is behind Cloudflare Access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
        }
        .disabled(isConnecting)
    }

    private func connect() async {
        guard !isConnecting else { return }
        let credentials = CloudflareAccessCredentials(clientId: clientId, clientSecret: clientSecret)
        let isBlank = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if credentials == nil, !(isBlank(clientId) && isBlank(clientSecret)) {
            showsCloudflareAccess = true
            errorMessage = String(localized: "Fill in both the Client ID and the Client Secret.")
            return
        }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            try await session.connect(toServer: address, cloudflareAccess: credentials)
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
            case .cloudflareBlocked:
                return String(localized: "Cloudflare blocked this request. Check the Cloudflare Access token.")
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
