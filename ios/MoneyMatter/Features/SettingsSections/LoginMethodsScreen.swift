import AuthenticationServices
import MoneyMatterKit
import SwiftUI

/// Settings > Security > Login Methods: password and linked Google or GitHub accounts, plus
/// passkeys (add natively, rename, remove). The last remaining sign-in method can't be removed.
struct LoginMethodsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session

    @State private var state: LoadState<Snapshot> = .idle
    @State private var alert: ErrorAlert?
    @State private var isWorking = false
    @State private var accountToUnlink: SettingsLinkedAccount?
    @State private var passkeyToDelete: SettingsPasskey?
    @State private var passkeyToRename: SettingsPasskey?
    @State private var renameText = ""
    @State private var needsFreshSignIn = false
    @State private var registrar = LoginMethodsPasskeyRegistrar()

    private struct Snapshot: Equatable {
        var accounts: [SettingsLinkedAccount]
        var passkeys: [SettingsPasskey]

        var hasPassword: Bool { accounts.contains { $0.provider == .credential } }

        func account(for provider: SettingsAuthProvider) -> SettingsLinkedAccount? {
            accounts.first { $0.provider == provider }
        }

        var methodCount: Int {
            let oauth = [SettingsAuthProvider.google, .github].filter { account(for: $0) != nil }.count
            return oauth + passkeys.count + (hasPassword ? 1 : 0)
        }

        var canRemoveMethod: Bool { methodCount > 1 }
    }

    var body: some View {
        content
            .navigationTitle("Login Methods")
            .task { if case .idle = state { await load() } }
            .refreshable { await load() }
            .errorAlert($alert)
            .confirmationDialog(
                "Unlink this account?",
                isPresented: Binding(get: { accountToUnlink != nil }, set: { if !$0 { accountToUnlink = nil } }),
                titleVisibility: .visible,
                presenting: accountToUnlink
            ) { account in
                Button("Unlink", role: .destructive) { Task { await unlink(account) } }
            } message: { _ in
                Text("You won't be able to sign in with this provider until you link it again on the web.")
            }
            .confirmationDialog(
                "Remove this passkey?",
                isPresented: Binding(get: { passkeyToDelete != nil }, set: { if !$0 { passkeyToDelete = nil } }),
                titleVisibility: .visible,
                presenting: passkeyToDelete
            ) { passkey in
                Button("Remove Passkey", role: .destructive) { Task { await delete(passkey) } }
            } message: { _ in
                Text("You won't be able to sign in with this passkey anymore. It stays in your password manager until you delete it there.")
            }
            .alert(
                "Rename Passkey",
                isPresented: Binding(get: { passkeyToRename != nil }, set: { if !$0 { passkeyToRename = nil } }),
                presenting: passkeyToRename
            ) { passkey in
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { Task { await rename(passkey) } }
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .alert("Sign In Again", isPresented: $needsFreshSignIn) {
                Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("For your security, adding a passkey needs a sign-in from the last 24 hours. Sign out, sign back in, and try again.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let snapshot):
            form(snapshot)
        case .idle, .loading:
            form(Snapshot(
                accounts: [SettingsLinkedAccount(id: "p", providerId: "credential", accountId: "p")],
                passkeys: [SettingsPasskey(id: "k", name: "iPhone", createdAt: .now)]
            ))
            .redactedWhileLoading(true)
        }
    }

    private func form(_ snapshot: Snapshot) -> some View {
        Form {
            Section {
                NavigationLink { PasswordScreen() } label: {
                    LabeledContent {
                        Text(snapshot.hasPassword ? "Set" : "Not Set")
                    } label: {
                        Label("Password", systemImage: "lock")
                    }
                }
                providerRow(.google, title: "Google", symbol: "g.circle", snapshot: snapshot)
                providerRow(.github, title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", snapshot: snapshot)
            } header: {
                Text("Sign-in Methods")
            } footer: {
                Text("To link a new Google or GitHub account, use MoneyMatter on the web. You need at least one way to sign in.")
            }

            Section {
                if snapshot.passkeys.isEmpty {
                    ContentUnavailableView {
                        Label("No Passkeys", systemImage: "person.badge.key")
                    } description: {
                        Text("Passkeys let you sign in with Face ID or Touch ID instead of a password.")
                    }
                }
                ForEach(snapshot.passkeys) { passkey in
                    passkeyRow(passkey, canRemove: snapshot.canRemoveMethod)
                }
                if session.supportsPasskeys {
                    Button {
                        Task { await addPasskey() }
                    } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Label("Add Passkey", systemImage: "plus")
                        }
                    }
                    .disabled(isWorking)
                }
            } header: {
                Text("Passkeys")
            } footer: {
                if !session.supportsPasskeys {
                    Text("This server isn't set up for passkeys in the app. You can add them on the web.")
                }
            }
        }
    }

    private func providerRow(
        _ provider: SettingsAuthProvider,
        title: LocalizedStringKey,
        symbol: String,
        snapshot: Snapshot
    ) -> some View {
        let account = snapshot.account(for: provider)
        return HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if let account {
                Text("Linked")
                    .foregroundStyle(.secondary)
                Menu {
                    Button("Unlink", systemImage: "link.badge.minus", role: .destructive) {
                        accountToUnlink = account
                    }
                    .disabled(!snapshot.canRemoveMethod || isWorking)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text("Options for \(Text(title))"))
            } else {
                Text("Not Linked")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func passkeyRow(_ passkey: SettingsPasskey, canRemove: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(passkey.name.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Passkey"), systemImage: "person.badge.key")
            if let created = passkey.createdAt {
                Text("Added \(created.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            if canRemove {
                Button("Remove", systemImage: "trash", role: .destructive) { passkeyToDelete = passkey }
            }
            Button("Rename", systemImage: "pencil") { startRename(passkey) }
                .tint(.blue)
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { startRename(passkey) }
            Button("Remove", systemImage: "trash", role: .destructive) { passkeyToDelete = passkey }
                .disabled(!canRemove)
        }
    }

    private func startRename(_ passkey: SettingsPasskey) {
        renameText = passkey.name ?? ""
        passkeyToRename = passkey
    }

    // MARK: Actions

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let client = try settingsSectionsClient(services)
            async let accounts = client.send(Endpoints.settingsLinkedAccounts())
            async let passkeys = client.send(Endpoints.settingsPasskeys())
            state = .loaded(Snapshot(accounts: try await accounts, passkeys: try await passkeys))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(error) }
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await action()
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func unlink(_ account: SettingsLinkedAccount) async {
        await perform {
            let client = try settingsSectionsClient(services)
            _ = try await client.send(Endpoints.settingsUnlinkAccount(providerId: account.providerId, accountId: account.accountId))
        }
    }

    private func delete(_ passkey: SettingsPasskey) async {
        await perform {
            let client = try settingsSectionsClient(services)
            _ = try await client.send(Endpoints.settingsDeletePasskey(id: passkey.id))
        }
    }

    private func rename(_ passkey: SettingsPasskey) async {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await perform {
            let client = try settingsSectionsClient(services)
            _ = try await client.send(Endpoints.settingsRenamePasskey(id: passkey.id, name: name))
        }
    }

    private func addPasskey() async {
        guard let server = session.server, session.supportsPasskeys else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let client = try settingsSectionsClient(services)
            let registrar = registrar
            let host = server.host
            let name = UIDevice.current.name
            _ = try await client.registerSettingsPasskey(name: name) { options in
                try await registrar.register(options: options, relyingParty: options.rpId ?? host)
            }
            await load()
        } catch let error as APIError {
            if case .server(_, let code, _) = error, code == SettingsSecurityErrorCode.sessionNotFresh {
                needsFreshSignIn = true
            } else {
                alert = ErrorAlert(error)
            }
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// Runs an `ASAuthorizationController` registration for a new platform passkey. The relying party
/// must appear in the app's Associated Domains (`webcredentials:`).
final class LoginMethodsPasskeyRegistrar: NSObject,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<SettingsPasskeyRegistration, any Error>?
    private var controller: ASAuthorizationController?

    func register(options: SettingsPasskeyCreationOptions, relyingParty: String) async throws -> SettingsPasskeyRegistration {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
        let request = provider.createCredentialRegistrationRequest(
            challenge: options.challenge,
            name: options.userName,
            userID: options.userID
        )
        if let preference = options.userVerification {
            request.userVerificationPreference = ASAuthorizationPublicKeyCredentialUserVerificationPreference(rawValue: preference)
        }
        request.excludedCredentials = options.excludedCredentialIDs.map {
            ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
        }

        cancelPending()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                self.controller = controller
                controller.performRequests()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelPending() }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === self.controller else { return }
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let attestation = credential.rawAttestationObject else {
            finish(.failure(APIError.decoding("The passkey provider didn't return an attestation.")))
            return
        }
        finish(.success(SettingsPasskeyRegistration(
            credentialID: credential.credentialID,
            clientDataJSON: credential.rawClientDataJSON,
            attestationObject: attestation
        )))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        guard controller === self.controller else { return }
        if let authorizationError = error as? ASAuthorizationError, authorizationError.code == .canceled {
            finish(.failure(AuthenticationCancelled()))
        } else {
            finish(.failure(error))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        PresentationAnchor.current()
    }

    private func cancelPending() {
        let pending = controller
        finish(.failure(AuthenticationCancelled()))
        pending?.cancel()
    }

    private func finish(_ result: Result<SettingsPasskeyRegistration, any Error>) {
        controller = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
