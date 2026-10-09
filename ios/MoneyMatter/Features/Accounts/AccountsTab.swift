import MoneyMatterKit
import SwiftUI

/// Root of the Accounts tab: net worth, accounts by root group, other accounts, a collapsed
/// Archived section, then the Assets and Bank Connections entry points.
struct AccountsTab: View {
    private struct GroupSection: Identifiable {
        let id: String
        let name: String
        let accounts: [Account]
    }

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(SessionStore.self) private var session
    @State private var groups: [AccountGroup] = []
    @State private var groupsError: APIError?
    @State private var isCreatePresented = false
    @State private var isArchivedExpanded = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.accountsPath) {
            List {
                content
                assetsSection
                connectionsSection
            }
            .navigationTitle("Accounts")
            .toolbar {
                if referenceData.accounts.contains(where: { $0.bankDataProviderConnectionId != nil }) {
                    ToolbarItem(placement: .topBarLeading) {
                        BankSyncToolbarMenu()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Account", systemImage: "plus") {
                        isCreatePresented = true
                    }
                }
            }
            .refreshable {
                async let accounts: Void = referenceData.refresh()
                async let groups: Void = loadGroups()
                _ = await (accounts, groups)
            }
            .task {
                await loadGroups()
            }
            .onChange(of: referenceData.accounts) {
                Task { await loadGroups() }
            }
            .sheet(isPresented: $isCreatePresented) {
                AccountFormSheet(mode: .create)
            }
            .navigationDestination(for: AccountsRoute.self) { route in
                switch route {
                case .account(let id):
                    AccountDetailScreen(accountID: id)
                case .transaction(let id):
                    TransactionDetailScreen(transactionID: id)
                case .loans:
                    LoansScreen()
                case .investments:
                    PortfoliosScreen()
                case .venture:
                    VentureScreen()
                case .vehicles:
                    VehiclesScreen()
                case .bankConnections:
                    BankConnectionsScreen()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if referenceData.accounts.isEmpty {
            if !referenceData.hasLoaded, let error = referenceData.lastError {
                Section {
                    LoadFailedView(error: error) { await referenceData.refresh() }
                }
                .listRowBackground(Color.clear)
            } else if !referenceData.hasLoaded {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ContentUnavailableView {
                        Label("No Accounts", systemImage: "wallet.bifold")
                    } description: {
                        Text("Add an account to start tracking balances and transactions.")
                    } actions: {
                        Button("Add Account") { isCreatePresented = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                netWorthHeader
            }
            ForEach(groupSections) { section in
                Section(section.name) {
                    ForEach(section.accounts) { accountLink($0) }
                }
            }
            if !otherAccounts.isEmpty {
                Section(groupSections.isEmpty ? "Accounts" : "Other Accounts") {
                    ForEach(otherAccounts) { accountLink($0) }
                }
            }
            if let groupsError {
                Section {
                    InlineRetryView(ErrorMessage.message(for: groupsError)) { await loadGroups() }
                }
            }
            if !archivedAccounts.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $isArchivedExpanded) {
                        ForEach(archivedAccounts) { accountLink($0) }
                    } label: {
                        Text("Archived (\(archivedAccounts.count))")
                    }
                }
            }
        }
    }

    private var assetsSection: some View {
        Section("Assets") {
            NavigationLink(value: AccountsRoute.loans) {
                Label("Loans", systemImage: "banknote")
            }
            NavigationLink(value: AccountsRoute.investments) {
                Label("Investments", systemImage: "chart.line.uptrend.xyaxis")
            }
            NavigationLink(value: AccountsRoute.venture) {
                Label("Venture", systemImage: "briefcase")
            }
            NavigationLink(value: AccountsRoute.vehicles) {
                Label("Vehicles", systemImage: "car")
            }
        }
    }

    private var connectionsSection: some View {
        Section {
            NavigationLink(value: AccountsRoute.bankConnections) {
                Label("Bank Connections", systemImage: "building.columns")
            }
        }
    }

    private var netWorthHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Net Worth")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let code = session.baseCurrency?.currencyCode {
                AmountText(netWorth, currencyCode: code, digits: referenceData.digits(for: code))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func accountLink(_ account: Account) -> some View {
        NavigationLink(value: AccountsRoute.account(id: account.id)) {
            AccountRow(account: account, digits: referenceData.digits(for: account.currencyCode))
        }
    }

    private var netWorth: Decimal {
        referenceData.accounts.filter(\.countsTowardNetWorth).reduce(0) { $0 + $1.refCurrentBalance }
    }

    private var groupSections: [GroupSection] {
        var seen = Set<String>()
        return AccountGroup.roots(of: groups).compactMap { root in
            let accounts = root.allAccounts.compactMap { member -> Account? in
                guard let account = referenceData.account(id: member.id), !account.isArchived,
                      seen.insert(account.id).inserted else { return nil }
                return account
            }
            return accounts.isEmpty ? nil : GroupSection(id: root.id, name: root.name, accounts: accounts)
        }
    }

    private var otherAccounts: [Account] {
        let grouped = Set(groupSections.flatMap { $0.accounts.map(\.id) })
        return referenceData.activeAccounts.filter { !grouped.contains($0.id) }
    }

    private var archivedAccounts: [Account] {
        referenceData.accounts.filter(\.isArchived)
    }

    private func loadGroups() async {
        do {
            groups = try await services.accounts.accountGroups(includeArchived: false)
            groupsError = nil
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation { groupsError = apiError }
        }
    }
}
