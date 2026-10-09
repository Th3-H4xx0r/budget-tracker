import MoneyMatterKit
import SwiftUI

/// Add a bank connection: pick a provider, enter its credentials, then choose which bank
/// accounts to import. Enable Banking instead picks a country and bank and runs the bank's
/// consent page.
struct BankConnectSheet: View {
    /// Called with the new connection's id once it exists.
    var onConnected: (String) -> Void = { _ in }

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var providers: LoadState<[BankProviderInfo]> = .idle

    var body: some View {
        NavigationStack {
            List {
                switch providers {
                case .idle, .loading:
                    ForEach(0..<4, id: \.self) { _ in
                        Label("Provider name", systemImage: "building.columns")
                    }
                    .redactedWhileLoading(true)
                case .failed(let error):
                    InlineRetryView(ErrorMessage.message(for: error)) { await load() }
                case .loaded(let list):
                    Section {
                        ForEach(list.filter { $0.type != .unknown }) { provider in
                            NavigationLink {
                                BankCredentialsForm(provider: provider) { connectionID in
                                    onConnected(connectionID)
                                    dismiss()
                                }
                            } label: {
                                providerRow(provider)
                            }
                        }
                    } footer: {
                        Text("Credentials are sent to your MoneyMatter server, which connects to the provider.")
                    }
                }
            }
            .navigationTitle("Connect a Bank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { if case .idle = providers { await load() } }
        }
    }

    private func providerRow(_ provider: BankProviderInfo) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                if let description = provider.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } icon: {
            Image(systemName: BankSyncText.providerSymbol(provider.type))
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        providers = .loading
        do {
            providers = .loaded(try await client.send(Endpoints.bankProviders()))
        } catch {
            providers = .failed(APIError(error))
        }
    }
}

/// The credential form for one provider.
private struct BankCredentialsForm: View {
    let provider: BankProviderInfo
    let onConnected: (String) -> Void

    @Environment(AppServices.self) private var services
    @State private var primary = ""
    @State private var secondary = ""
    @State private var isWorking = false
    @State private var errorAlert: ErrorAlert?
    @State private var claimedConnectionID: String?
    @State private var enableBankingCountries: [String]?

    var body: some View {
        Form {
            fields
            if let link = provider.documentationUrl.flatMap(URL.init(string:)) {
                Section {
                    Link(destination: link) {
                        Label("Where do I find these?", systemImage: "questionmark.circle")
                    }
                }
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isWorking {
                    ProgressView()
                } else {
                    Button(provider.type == .enableBanking ? "Next" : "Connect") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .navigationDestination(item: $claimedConnectionID) { connectionID in
            BankAccountPickerForm(
                connectionID: connectionID,
                preselectAll: true,
                onFinished: { onConnected(connectionID) }
            )
        }
        .navigationDestination(isPresented: Binding(
            get: { enableBankingCountries != nil },
            set: { if !$0 { enableBankingCountries = nil } }
        )) {
            EnableBankingCountryList(
                countries: enableBankingCountries ?? [],
                credentials: EnableBankingCredentialsRequest(appId: primary.e1Trimmed, privateKey: secondary.e1Trimmed),
                onConnected: onConnected
            )
        }
        .errorAlert($errorAlert)
        .disabled(isWorking)
    }

    @ViewBuilder
    private var fields: some View {
        switch provider.type {
        case .monobank:
            Section {
                SecureField("API token", text: $primary)
            } footer: {
                Text("Get a personal token at api.monobank.ua.")
            }
        case .lunchflow:
            Section {
                SecureField("API key", text: $primary)
            } footer: {
                Text("Create an API key in your LunchFlow dashboard.")
            }
        case .walutomat:
            Section {
                SecureField("API key", text: $primary)
                TextField("Private key (PEM)", text: $secondary, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.footnote.monospaced())
            } footer: {
                Text("Generate an API key and its RSA private key in Walutomat settings.")
            }
        case .simplefin:
            Section {
                SecureField("Setup token", text: $primary)
            } footer: {
                Text("Paste the setup token from SimpleFIN Bridge. It can be claimed once.")
            }
        case .enableBanking:
            Section {
                TextField("Application ID", text: $primary)
                TextField("Private key (PEM)", text: $secondary, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.footnote.monospaced())
            } footer: {
                Text("Use the application ID and private key from the Enable Banking control panel.")
            }
        case .unknown:
            EmptyView()
        }
    }

    private var canSubmit: Bool {
        switch provider.type {
        case .walutomat, .enableBanking: !primary.e1Trimmed.isEmpty && !secondary.e1Trimmed.isEmpty
        default: !primary.e1Trimmed.isEmpty
        }
    }

    private func submit() async {
        guard let client = services.client, canSubmit else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            switch provider.type {
            case .enableBanking:
                enableBankingCountries = try await client.send(Endpoints.enableBankingCountries(
                    EnableBankingCredentialsRequest(appId: primary.e1Trimmed, privateKey: secondary.e1Trimmed)
                ))
            default:
                let credentials: BankCredentials = switch provider.type {
                case .monobank: BankProviderCredentials.monobank(token: primary.e1Trimmed)
                case .walutomat: BankProviderCredentials.walutomat(apiKey: primary.e1Trimmed, privateKey: secondary.e1Trimmed)
                case .simplefin: BankProviderCredentials.simpleFIN(setupToken: primary.e1Trimmed)
                default: BankProviderCredentials.lunchFlow(apiKey: primary.e1Trimmed)
                }
                let result = try await client.send(Endpoints.connectBankProvider(
                    provider.type,
                    BankConnectRequest(credentials: credentials)
                ))
                claimedConnectionID = result.connectionId
            }
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

/// Enable Banking step 2: the country.
private struct EnableBankingCountryList: View {
    let countries: [String]
    let credentials: EnableBankingCredentialsRequest
    let onConnected: (String) -> Void
    @State private var query = ""

    var body: some View {
        List(filtered, id: \.self) { code in
            NavigationLink {
                EnableBankingBankList(country: code, credentials: credentials, onConnected: onConnected)
            } label: {
                LabeledContent(Locale.current.localizedString(forRegionCode: code) ?? code, value: code)
            }
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: Text("Search countries"))
        .navigationTitle("Country")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filtered: [String] {
        let sorted = countries.sorted {
            (Locale.current.localizedString(forRegionCode: $0) ?? $0) < (Locale.current.localizedString(forRegionCode: $1) ?? $1)
        }
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.localizedCaseInsensitiveContains(query)
                || (Locale.current.localizedString(forRegionCode: $0) ?? "").localizedCaseInsensitiveContains(query)
        }
    }
}

/// Enable Banking step 3: the bank, then its consent page.
private struct EnableBankingBankList: View {
    let country: String
    let credentials: EnableBankingCredentialsRequest
    let onConnected: (String) -> Void

    @Environment(AppServices.self) private var services
    @State private var banks: LoadState<[EnableBankingBank]> = .idle
    @State private var query = ""
    @State private var connectingBankID: String?
    @State private var errorAlert: ErrorAlert?
    @State private var authorizedConnectionID: String?

    var body: some View {
        List {
            switch banks {
            case .idle, .loading:
                ForEach(0..<6, id: \.self) { _ in Text(verbatim: "Placeholder bank name") }
                    .redactedWhileLoading(true)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await load() }
            case .loaded:
                ForEach(filtered) { bank in
                    Button {
                        Task { await connect(bank) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bank.name)
                                    .foregroundStyle(.primary)
                                if let bic = bank.bic, !bic.isEmpty {
                                    Text("BIC \(bic)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if bank.beta {
                                Text("Beta")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.yellow.opacity(0.25), in: .capsule)
                            }
                            if connectingBankID == bank.id {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(connectingBankID != nil)
                }
            }
        }
        .overlay {
            if case .loaded(let list) = banks {
                if list.isEmpty {
                    ContentUnavailableView("No Banks", systemImage: "building.columns", description: Text("Enable Banking lists no banks for this country."))
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .searchable(text: $query, prompt: Text("Search banks"))
        .navigationTitle(Locale.current.localizedString(forRegionCode: country) ?? country)
        .navigationBarTitleDisplayMode(.inline)
        .task { if case .idle = banks { await load() } }
        .navigationDestination(item: $authorizedConnectionID) { connectionID in
            BankAccountPickerForm(connectionID: connectionID, preselectAll: true) {
                onConnected(connectionID)
            }
        }
        .errorAlert($errorAlert)
    }

    private var filtered: [EnableBankingBank] {
        guard case .loaded(let list) = banks else { return [] }
        let sorted = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(query) || ($0.bic ?? "").localizedCaseInsensitiveContains(query) }
    }

    private func load() async {
        guard let client = services.client else { return }
        banks = .loading
        do {
            banks = .loaded(try await client.send(Endpoints.enableBankingBanks(country: country, credentials)))
        } catch {
            banks = .failed(APIError(error))
        }
    }

    private func connect(_ bank: EnableBankingBank) async {
        guard let client = services.client else { return }
        connectingBankID = bank.id
        defer { connectingBankID = nil }
        do {
            let result = try await client.send(Endpoints.connectBankProvider(
                .enableBanking,
                BankConnectRequest(credentials: BankProviderCredentials.enableBanking(
                    appId: credentials.appId,
                    privateKey: credentials.privateKey,
                    bank: bank
                ))
            ))
            guard let authURL = result.authUrl else {
                authorizedConnectionID = result.connectionId
                return
            }
            if try await BankConsentFlow.authorize(connectionID: result.connectionId, authURL: authURL, client: client) {
                await BankSyncMonitor.shared.refresh(client: client)
                authorizedConnectionID = result.connectionId
            }
        } catch {
            errorAlert = ErrorAlert.bankConsent(error)
        }
    }
}

/// Choose bank accounts to import into a connection. Accounts the provider lists without a
/// currency need one picked first; it can't be changed later.
struct BankAccountPickerForm: View {
    let connectionID: String
    var excludedExternalIDs: Set<String> = []
    var preselectAll = false
    let onFinished: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var accounts: LoadState<[BankAvailableAccount]> = .idle
    @State private var selection: Set<String> = []
    @State private var currencyOverrides: [String: String] = [:]
    @State private var isImporting = false
    @State private var errorAlert: ErrorAlert?

    var body: some View {
        Form {
            switch accounts {
            case .idle, .loading:
                Section {
                    ForEach(0..<3, id: \.self) { _ in
                        LabeledContent("Account name", value: "0,000.00")
                    }
                }
                .redactedWhileLoading(true)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await load() }
            case .loaded(let list):
                if list.isEmpty {
                    ContentUnavailableView {
                        Label("No Accounts to Add", systemImage: "checkmark.circle")
                    } description: {
                        Text("Every account at this bank is already connected.")
                    } actions: {
                        Button("Done") { onFinished() }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Section {
                        ForEach(list) { account in
                            accountRow(account)
                        }
                    } header: {
                        Text("Bank Accounts")
                    } footer: {
                        Text("Each selected account becomes a MoneyMatter account that syncs from the bank.")
                    }
                }
            }
        }
        .navigationTitle("Choose Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isImporting)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isImporting {
                    ProgressView()
                } else {
                    Button("Import") { Task { await importSelected() } }
                        .disabled(!canImport)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Skip") { onFinished() }
                    .disabled(isImporting)
            }
        }
        .task { if case .idle = accounts { await load() } }
        .errorAlert($errorAlert)
    }

    @ViewBuilder
    private func accountRow(_ account: BankAvailableAccount) -> some View {
        let isSelected = selection.contains(account.externalId)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if isSelected { selection.remove(account.externalId) } else { selection.insert(account.externalId) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .imageScale(.large)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .foregroundStyle(.primary)
                        if let type = account.type, !type.isEmpty {
                            Text(type.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if account.needsCurrencyChoice {
                        Text(account.balance, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        AmountText(account.balance, currencyCode: account.currency, digits: referenceData.digits(for: account.currency))
                    }
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            if account.needsCurrencyChoice, isSelected {
                Picker("Currency", selection: Binding(
                    get: { currencyOverrides[account.externalId] },
                    set: { currencyOverrides[account.externalId] = $0 }
                )) {
                    Text("Choose").tag(String?.none)
                    ForEach(referenceData.userCurrencies) { currency in
                        Text(verbatim: currency.currencyCode).tag(String?.some(currency.currencyCode))
                    }
                }
                Text("The bank didn't report a currency. It can't be changed after import.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canImport: Bool {
        guard case .loaded(let list) = accounts, !selection.isEmpty else { return false }
        return list.allSatisfy { account in
            !selection.contains(account.externalId) || !account.needsCurrencyChoice || currencyOverrides[account.externalId] != nil
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        accounts = .loading
        do {
            let list = try await client.send(Endpoints.bankAvailableAccounts(connectionID: connectionID))
                .filter { !excludedExternalIDs.contains($0.externalId) }
            accounts = .loaded(list)
            if preselectAll { selection = Set(list.map(\.externalId)) }
        } catch {
            accounts = .failed(APIError(error))
        }
    }

    private func importSelected() async {
        guard let client = services.client, case .loaded(let list) = accounts else { return }
        isImporting = true
        defer { isImporting = false }
        let overrides = currencyOverrides.filter { id, _ in
            selection.contains(id) && list.contains { $0.externalId == id && $0.needsCurrencyChoice }
        }
        do {
            _ = try await client.send(Endpoints.syncSelectedBankAccounts(
                connectionID: connectionID,
                BankSyncSelectedAccountsRequest(accountExternalIds: Array(selection), currencyOverrides: overrides)
            ))
            await referenceData.refreshAccounts()
            await BankSyncMonitor.shared.refresh(client: client)
            TransactionChangeFeed.shared.publish(.invalidated)
            onFinished()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

extension String {
    fileprivate var e1Trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
