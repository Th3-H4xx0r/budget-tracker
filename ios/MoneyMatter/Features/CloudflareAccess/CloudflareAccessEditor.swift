import MoneyMatterKit
import SwiftUI

/// The Cloudflare Access token for the connected server: status, the two fields, a QR scan,
/// Save, and Remove Token. `onSaved` runs after a successful save.
struct CloudflareAccessEditor: View {
    @Environment(SessionStore.self) private var session
    var onSaved: (() -> Void)?

    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var hasToken = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showsScanner = false
    @State private var confirmsRemove = false

    private var enteredCredentials: CloudflareAccessCredentials? {
        CloudflareAccessCredentials(clientId: clientId, clientSecret: clientSecret)
    }

    private var hasId: Bool { !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasSecret: Bool { !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Both fields filled, or a saved token whose secret is kept under a new (or the same) Client ID.
    private var canSave: Bool {
        enteredCredentials != nil || (hasToken && hasId && !hasSecret)
    }

    private var isPartlyFilled: Bool {
        !canSave && (hasId || hasSecret)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Text(hasToken ? "Token saved" : "No token")
                }
            }

            Section {
                TextField("Client ID", text: $clientId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(hasToken ? "Saved – enter a new secret to replace it" : "Client Secret", text: $clientSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Scan QR Code", systemImage: "qrcode.viewfinder") {
                    showsScanner = true
                }
            } footer: {
                Text("Only needed if your server is behind Cloudflare Access.")
            }

            if isPartlyFilled {
                Section {
                    ErrorRow(String(localized: "Fill in both the Client ID and the Client Secret."))
                }
            }

            if let errorMessage {
                Section { ErrorRow(errorMessage) }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text("Save")
                        if isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!canSave || isWorking)

                if hasToken {
                    Button("Remove Token", role: .destructive) { confirmsRemove = true }
                        .disabled(isWorking)
                }
            }
        }
        .navigationTitle("Cloudflare Access")
        .onAppear(perform: loadSaved)
        .onDisappear { clientSecret = "" }
        .sheet(isPresented: $showsScanner) {
            CloudflareAccessScanner(expectedServer: session.server) { payload in
                clientId = payload.credentials.clientId
                clientSecret = payload.credentials.clientSecret
            }
        }
        .confirmationDialog("Remove Token", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Remove Token", role: .destructive) {
                Task { await remove() }
            }
        } message: {
            Text("The app will stop sending the Cloudflare Access token to this server.")
        }
    }

    private func loadSaved() {
        let saved = session.cloudflareAccessCredentials
        hasToken = saved != nil
        if let saved, clientId.isEmpty, clientSecret.isEmpty {
            clientId = saved.clientId
        }
    }

    private func save() async {
        guard !isWorking else { return }
        let credentials = enteredCredentials
            ?? session.cloudflareAccessCredentials.flatMap {
                CloudflareAccessCredentials(clientId: clientId, clientSecret: $0.clientSecret)
            }
        guard let credentials else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await session.updateCloudflareAccess(credentials)
            hasToken = session.cloudflareAccessCredentials != nil
            clientSecret = ""
            onSaved?()
        } catch {
            errorMessage = ErrorMessage.inline(for: error)
        }
    }

    private func remove() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await session.updateCloudflareAccess(nil)
            hasToken = session.cloudflareAccessCredentials != nil
            clientId = ""
            clientSecret = ""
        } catch {
            errorMessage = ErrorMessage.inline(for: error)
        }
    }
}

/// The editor in its own sheet, for the launch and sign-in screens.
struct CloudflareAccessSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CloudflareAccessEditor(onSaved: { dismiss() })
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}
