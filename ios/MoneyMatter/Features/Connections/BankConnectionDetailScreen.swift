import MoneyMatterKit
import SwiftUI

/// One bank connection: status and consent, linked accounts with their sync state, and
/// rename, connect accounts, reconnect, and disconnect.
struct BankConnectionDetailScreen: View {
    let connectionID: String

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var detail: LoadState<BankConnectionDetail> = .idle
    @State private var monitor = BankSyncMonitor.shared
    @State private var isWorking = false
    @State private var errorAlert: ErrorAlert?
    @State private var isRenamePresented = false
    @State private var draftName = ""
    @State private var isConnectAccountsPresented = false
    @State private var isCredentialsPresented = false
    @State private var isDisconnectPresented = false

    var body: some View {
        Group {
            switch detail {
            case .idle, .loading:
                List {
                    Section {
                        LabeledContent("Provider", value: "Placeholder")
                        LabeledContent("Status", value: "Active")
                        LabeledContent("Last synced", value: "Today")
                    }
                    Section("Accounts") {
                        LabeledContent("Account name", value: "0,000.00")
                    }
                }
                .redactedWhileLoading(true)
            case .failed(let error):
                LoadFailedView(error: error) { await load() }
            case .loaded(let connection):
                content(connection)
            }
        }
        .navigationTitle(detail.value?.providerName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { if case .idle = detail { await load() } }
        .errorAlert($errorAlert)
    }

    private func content(_ connection: BankConnectionDetail) -> some View {
        List {
            if connection.needsReconnect || connection.deactivationReason != nil {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reconnect to resume syncing")
                                .font(.headline)
                            Text(connection.consent?.isExpired == true
                                 ? "The bank consent for this connection has expired."
                                 : "The bank rejected this connection's credentials.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Button("Reconnect") { Task { await reconnect(connection) } }
                }
            }

            Section {
                LabeledContent("Provider", value: connection.provider?.name ?? BankSyncText.providerName(connection.providerType))
                LabeledContent("Status") {
                    BankConsentBadge(isActive: connection.isActive, status: monitor.status?.connectionStatus(forConnectionID: connection.id))
                }
                if let last = connection.lastSyncAt {
                    LabeledContent("Last synced", value: last.formatted(.relative(presentation: .named)))
                }
                if let until = connection.consent?.validUntil {
                    LabeledContent("Consent valid until", value: until.formatted(date: .abbreviated, time: .omitted))
                }
                if let created = connection.createdAt {
                    LabeledContent("Connected", value: created.formatted(date: .abbreviated, time: .omitted))
                }
            }

            Section {
                if connection.accounts.isEmpty {
                    Text("No accounts imported from this connection yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(connection.accounts) { account in
                    accountRow(account)
                }
                Button("Connect Accounts", systemImage: "plus.circle") {
                    isConnectAccountsPresented = true
                }
                .disabled(!connection.isActive)
            } header: {
                Text("Accounts")
            }

            Section {
                Button("Rename", systemImage: "pencil") {
                    draftName = connection.providerName
                    isRenamePresented = true
                }
                Button(
                    connection.providerType == .enableBanking ? "Renew Bank Consent" : "Update Credentials",
                    systemImage: "arrow.clockwise"
                ) {
                    Task { await reconnect(connection) }
                }
                Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                    isDisconnectPresented = true
                }
            }
            .disabled(isWorking)
        }
        .refreshable { await load() }
        .alert("Rename Connection", isPresented: $isRenamePresented) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await rename() } }
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .confirmationDialog(
            "Disconnect \(connection.providerName)?",
            isPresented: $isDisconnectPresented,
            titleVisibility: .visible
        ) {
            Button("Disconnect and Keep Accounts", role: .destructive) {
                Task { await disconnect(removeAccounts: false) }
            }
            Button("Disconnect and Delete Accounts", role: .destructive) {
                Task { await disconnect(removeAccounts: true) }
            }
        } message: {
            Text("Kept accounts stop syncing and become manual accounts. Deleting removes them and all their transactions.")
        }
        .sheet(isPresented: $isConnectAccountsPresented) {
            NavigationStack {
                BankAccountPickerForm(
                    connectionID: connection.id,
                    excludedExternalIDs: Set(connection.accounts.map(\.externalId))
                ) {
                    isConnectAccountsPresented = false
                    Task { await load() }
                }
            }
        }
        .sheet(isPresented: $isCredentialsPresented) {
            BankUpdateCredentialsSheet(connectionID: connection.id, providerType: connection.providerType) {
                Task {
                    await load()
                    await monitor.refresh(client: services.client)
                }
            }
        }
    }

    private func accountRow(_ account: BankConnectionDetail.Account) -> some View {
        NavigationLink {
            AccountDetailScreen(accountID: account.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                    if let sync = monitor.status?.status(forAccountID: account.id) {
                        Text(syncLine(sync))
                            .font(.caption)
                            .foregroundStyle(sync.status == .failed ? .red : .secondary)
                            .lineLimit(2)
                    }
                    if let fallback = account.currencyFallback {
                        Text("Bank reported \(fallback.providerCurrency); imported as \(fallback.assignedCurrency).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                AmountText(account.currentBalance, currencyCode: account.currencyCode, digits: referenceData.digits(for: account.currencyCode))
            }
        }
    }

    private func syncLine(_ sync: BankSyncStatus.AccountStatus) -> String {
        if sync.status == .failed, let error = sync.error { return error }
        if sync.status == .completed, let completed = sync.completedAt {
            return String(localized: "Synced \(completed.formatted(.relative(presentation: .named)))")
        }
        return BankSyncText.state(sync.status)
    }

    private func load() async {
        guard let client = services.client else { return }
        if detail.value == nil { detail = .loading }
        do {
            detail = .loaded(try await client.send(Endpoints.bankConnection(id: connectionID)))
        } catch {
            if detail.value == nil { detail = .failed(APIError(error)) } else { errorAlert = ErrorAlert(error) }
        }
    }

    private func rename() async {
        guard let client = services.client else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.send(Endpoints.updateBankConnection(id: connectionID, BankConnectionUpdateRequest(providerName: name)))
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    /// Enable Banking renews consent through the bank; other providers take new credentials.
    private func reconnect(_ connection: BankConnectionDetail) async {
        guard connection.providerType == .enableBanking else {
            isCredentialsPresented = true
            return
        }
        guard let client = services.client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await client.send(Endpoints.reauthorizeBankConnection(id: connectionID))
            guard let authURL = result.authUrl else { return }
            if try await BankConsentFlow.authorize(connectionID: connectionID, authURL: authURL, client: client) {
                await load()
                await monitor.refresh(client: client)
                await referenceData.refreshAccounts()
            }
        } catch {
            errorAlert = ErrorAlert.bankConsent(error)
        }
    }

    private func disconnect(removeAccounts: Bool) async {
        guard let client = services.client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.send(Endpoints.disconnectBankConnection(id: connectionID, removeAssociatedAccounts: removeAccounts))
            await referenceData.refreshAccounts()
            await monitor.refresh(client: client)
            if removeAccounts { TransactionChangeFeed.shared.publish(.invalidated) }
            dismiss()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

/// New credentials for a token-based provider: Monobank token, LunchFlow key, Walutomat
/// key pair, or a fresh SimpleFIN setup token.
private struct BankUpdateCredentialsSheet: View {
    let connectionID: String
    let providerType: BankProviderType
    let onSaved: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var privateKey = ""
    @State private var isSaving = false
    @State private var errorAlert: ErrorAlert?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(primaryLabel, text: $apiKey)
                    if providerType == .walutomat {
                        TextField("Private key (PEM)", text: $privateKey, axis: .vertical)
                            .lineLimit(3...8)
                            .font(.footnote.monospaced())
                    }
                } footer: {
                    Text("The connection reactivates once the provider accepts the new credentials.")
                }
            }
            .navigationTitle("Update Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .errorAlert($errorAlert)
        }
    }

    private var primaryLabel: LocalizedStringKey {
        switch providerType {
        case .monobank: "API token"
        case .simplefin: "Setup token"
        default: "API key"
        }
    }

    private var canSave: Bool {
        !apiKey.isEmpty && (providerType != .walutomat || !privateKey.isEmpty)
    }

    private func save() async {
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }
        let credentials = BankProviderCredentials.reconnect(
            providerType: providerType,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKey: privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            _ = try await client.send(Endpoints.updateBankConnection(id: connectionID, BankConnectionUpdateRequest(credentials: credentials)))
            onSaved()
            dismiss()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}
