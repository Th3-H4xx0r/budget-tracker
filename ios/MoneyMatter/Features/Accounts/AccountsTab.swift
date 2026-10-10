import MoneyMatterKit
import SwiftUI

/// Root of the Accounts tab: net worth with its history chart, accounts by root group, other accounts, a collapsed
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
    @State private var syncMonitor = BankSyncMonitor.shared
    @State private var history = NetWorthHistoryModel()
    /// The scrubbed day of the net worth chart, shown in the hero.
    @State private var scrubbed: NetWorthChartPoint?

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
                    Button("Add account", systemImage: "plus") {
                        isCreatePresented = true
                    }
                }
            }
            .refreshable {
                async let accounts: Void = referenceData.refresh()
                async let groups: Void = loadGroups()
                async let historyLoad: Void = history.load(stats: services.stats)
                _ = await (accounts, groups, historyLoad)
            }
            .task {
                async let groups: Void = loadGroups()
                async let historyLoad: Void = history.loadIfNeeded(stats: services.stats)
                _ = await (groups, historyLoad)
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
                    HeroValueHeader("$0,000.00", status: String(localized: "Net worth"))
                }
                .accountsHeroRow()
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
                Section {
                    ForEach(0..<3, id: \.self) { _ in
                        EntityRow("Account name", subtitle: "Category") {
                            IconTile(text: "AA")
                        } trailing: {
                            EntityRowValue("$0,000.00")
                        }
                    }
                }
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
            } else {
                Section {
                    ContentUnavailableView {
                        Label("No accounts", systemImage: "wallet.bifold")
                    } description: {
                        Text("Add an account to start tracking balances and transactions.")
                    } actions: {
                        Button("Add account") { isCreatePresented = true }
                            .dsProminentButton()
                    }
                }
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    netWorthHeader
                    NetWorthHistoryChart(
                        state: history.state,
                        range: history.range,
                        scrubbed: $scrubbed,
                        currencyCode: session.baseCurrency?.currencyCode ?? "",
                        setRange: { range in
                            scrubbed = nil
                            Task { await history.setRange(range, stats: services.stats) }
                        },
                        retry: { await history.load(stats: services.stats) }
                    )
                }
            }
            .accountsHeroRow()
            ForEach(groupSections) { section in
                Section(section.name) {
                    ForEach(section.accounts) { accountLink($0) }
                }
            }
            if !otherAccounts.isEmpty {
                Section(groupSections.isEmpty ? "Accounts" : "Other accounts") {
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
        Section {
            NavigationLink(value: AccountsRoute.loans) {
                EntityRow(String(localized: "Loans"), systemImage: "banknote", tint: DS.Palette.warning)
            }
            NavigationLink(value: AccountsRoute.investments) {
                EntityRow(String(localized: "Investments"), systemImage: "chart.line.uptrend.xyaxis", tint: DS.Palette.up)
            }
            NavigationLink(value: AccountsRoute.venture) {
                EntityRow(String(localized: "Venture"), systemImage: "briefcase", tint: DS.Palette.accent)
            }
            NavigationLink(value: AccountsRoute.vehicles) {
                EntityRow(String(localized: "Vehicles"), systemImage: "car", tint: DS.Palette.info)
            }
        } header: {
            DSGroupHeader(String(localized: "Assets"))
        }
    }

    private var connectionsSection: some View {
        Section {
            NavigationLink(value: AccountsRoute.bankConnections) {
                EntityRow(String(localized: "Bank connections"), systemImage: "building.columns", tint: DS.Palette.teal) {
                    if !syncMonitor.connectionIDsNeedingAttention.isEmpty {
                        StatusBadge(label: String(localized: "Needs attention"), color: DS.Palette.warning)
                    } else if let failed = syncMonitor.status?.summary.failed, failed > 0 {
                        StatusBadge(label: String(localized: "Sync failed"), color: DS.Palette.danger)
                    }
                }
            }
        }
    }

    /// Net worth with its change over the chart's range. Scrubbing shows the scrubbed day's
    /// balance, its change from the range's start and its date instead.
    private var netWorthHeader: some View {
        let code = session.baseCurrency?.currencyCode ?? ""
        let digits = referenceData.digits(for: code)
        let trend = history.state.value
        let shown = scrubbed?.amount ?? netWorth
        let delta: Decimal? = if let scrubbed {
            trend?.baseline.map { scrubbed.amount - $0 }
        } else {
            trend?.change
        }
        let value = code.isEmpty ? "" : MoneyFormat.string(shown, currencyCode: code, digits: digits)
        return HeroValueHeader(
            value,
            numericValue: NSDecimalNumber(decimal: shown).doubleValue,
            valueAnimation: scrubbed == nil ? .snappy : nil,
            change: code.isEmpty ? nil : delta.map { changeText(delta: $0, baseline: trend?.baseline ?? 0, currencyCode: code) },
            direction: ChangeDirection(delta),
            changeLabel: scrubbed == nil ? history.range.summaryLabel : nil,
            status: scrubbed.map { $0.date.formatted(date: .abbreviated, time: .omitted) }
                ?? (hasBankAccounts ? BankSyncText.summary(syncMonitor.status, isSyncing: syncMonitor.isSyncing) : String(localized: "Net worth")),
            statusColor: scrubbed == nil && hasBankAccounts ? syncColor : nil,
            statusPulsing: scrubbed == nil && syncMonitor.isSyncing
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Net worth"))
        .accessibilityValue(Text(verbatim: value))
    }

    private func changeText(delta: Decimal, baseline: Decimal, currencyCode: String) -> String {
        let amount = MoneyFormat.string(abs(delta), currencyCode: currencyCode, digits: referenceData.digits(for: currencyCode))
        let sign = delta >= 0 ? "+" : "\u{2212}"
        guard baseline != 0 else { return sign + amount }
        let percent = (delta / abs(baseline)).doubleValue
        return "\(sign)\(amount) (\(percent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))))"
    }

    private var hasBankAccounts: Bool {
        referenceData.accounts.contains(where: { $0.bankDataProviderConnectionId != nil })
    }

    private var syncColor: Color {
        if syncMonitor.isSyncing { return DS.Palette.accent }
        if !syncMonitor.connectionIDsNeedingAttention.isEmpty || (syncMonitor.status?.summary.failed ?? 0) > 0 {
            return DS.Palette.warning
        }
        return DS.Palette.success
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
