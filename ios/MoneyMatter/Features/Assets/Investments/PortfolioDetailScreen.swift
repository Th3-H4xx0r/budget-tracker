import MoneyMatterKit
import SwiftUI

/// One portfolio: its value and returns, holdings, recent buys and sells, and links to
/// cash management and CSV import.
struct PortfolioDetailScreen: View {
    let onChange: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var portfolio: Portfolio
    @State private var summary: LoadState<PortfolioSummary> = .idle
    @State private var holdings: LoadState<[PortfolioHolding]> = .idle
    @State private var recent: LoadState<[InvestmentTransaction]> = .idle
    @State private var filter = ""
    @State private var isAddingSymbols = false
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var pendingHoldingDelete: PortfolioHolding?
    @State private var editingTransaction: InvestmentTransaction?
    @State private var pendingTransactionDelete: InvestmentTransaction?
    @State private var alert: ErrorAlert?

    init(portfolio: Portfolio, onChange: @escaping () -> Void) {
        _portfolio = State(initialValue: portfolio)
        self.onChange = onChange
    }

    var body: some View {
        List {
            summarySection
            holdingsSection
            Section {
                NavigationLink {
                    PortfolioCashScreen(portfolioID: portfolio.id, portfolioName: portfolio.name)
                } label: {
                    Label("Cash & Transfers", systemImage: "dollarsign.circle")
                }
                NavigationLink {
                    InvestmentImportScreen(portfolioID: portfolio.id)
                } label: {
                    Label("Import Transactions", systemImage: "square.and.arrow.down")
                }
            }
            recentSection
        }
        .navigationTitle(portfolio.name)
        .searchable(text: $filter, prompt: Text("Filter holdings"))
        .refreshable { await loadAll() }
        .task {
            if summary.value == nil { await loadAll() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingSymbols = true
                } label: {
                    Label("Add Symbols", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    isEditing = true
                } label: {
                    Label("Edit Portfolio", systemImage: "pencil")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete Portfolio", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $isAddingSymbols, onDismiss: { Task { await loadAll() } }) {
            InvestmentSecuritySearchSheet(portfolioID: portfolio.id)
        }
        .sheet(isPresented: $isEditing) {
            PortfolioFormSheet(portfolio: portfolio) {
                Task {
                    await reloadPortfolio()
                    onChange()
                }
            }
        }
        .sheet(item: $editingTransaction) { transaction in
            InvestmentTransactionFormSheet(
                portfolioID: portfolio.id,
                securityID: transaction.securityId,
                securityCurrencyCode: transaction.currencyCode,
                symbol: transaction.security?.displaySymbol ?? "",
                initialCategory: transaction.category,
                existing: transaction
            ) {
                Task { await loadAll() }
            }
        }
        .confirmationDialog(
            "Delete Portfolio?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Move to Recently Deleted", role: .destructive) {
                Task { await deletePortfolio() }
            }
        } message: {
            Text("The portfolio stays in Recently Deleted for 30 days, where you can restore it.")
        }
        .confirmationDialog(
            "Delete Holding?",
            isPresented: Binding(get: { pendingHoldingDelete != nil }, set: { if !$0 { pendingHoldingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingHoldingDelete
        ) { holding in
            Button("Delete Holding", role: .destructive) {
                Task { await deleteHolding(holding) }
            }
        } message: { _ in
            Text("The holding and all its transactions are deleted, and their cash impact is reversed.")
        }
        .confirmationDialog(
            "Delete Transaction?",
            isPresented: Binding(get: { pendingTransactionDelete != nil }, set: { if !$0 { pendingTransactionDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingTransactionDelete
        ) { transaction in
            Button("Delete Transaction", role: .destructive) {
                Task { await deleteTransaction(transaction) }
            }
        }
        .errorAlert($alert)
    }

    // MARK: Sections

    @ViewBuilder private var summarySection: some View {
        Section {
            switch summary {
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await loadSummary() }
            case .loaded(let value):
                PortfolioSummaryCard(summary: value)
            case .idle, .loading:
                PortfolioSummaryCard(summary: nil)
                    .redactedWhileLoading(true)
            }
        } header: {
            Text("Balance")
        }
    }

    @ViewBuilder private var holdingsSection: some View {
        Section {
            switch holdings {
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await loadHoldings() }
            case .loaded(let all) where all.isEmpty:
                ContentUnavailableView {
                    Label("No Holdings", systemImage: "chart.pie")
                } description: {
                    Text("Add stocks or crypto to start tracking this portfolio.")
                } actions: {
                    Button("Add Symbols") { isAddingSymbols = true }
                        .buttonStyle(.borderedProminent)
                }
            case .loaded(let all):
                let visible = filteredHoldings(all)
                if visible.isEmpty {
                    Text("No holdings match “\(filter)”.")
                        .foregroundStyle(.secondary)
                }
                ForEach(visible) { holding in
                    NavigationLink {
                        HoldingDetailScreen(portfolio: portfolio, holding: holding) {
                            Task { await loadAll() }
                        }
                    } label: {
                        PortfolioHoldingRow(holding: holding)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingHoldingDelete = holding
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingHoldingDelete = holding
                        } label: {
                            Label("Delete Holding", systemImage: "trash")
                        }
                    }
                }
            case .idle, .loading:
                ForEach(0..<3, id: \.self) { _ in
                    PortfolioHoldingRow(holding: nil)
                }
                .redactedWhileLoading(true)
            }
        } header: {
            if let count = holdings.value?.count, count > 0 {
                Text("Holdings (\(count))")
            } else {
                Text("Holdings")
            }
        }
    }

    @ViewBuilder private var recentSection: some View {
        Section {
            switch recent {
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await loadRecent() }
            case .loaded(let transactions) where transactions.isEmpty:
                Text("No buys or sells yet.")
                    .foregroundStyle(.secondary)
            case .loaded(let transactions):
                ForEach(transactions) { transaction in
                    Button {
                        editingTransaction = transaction
                    } label: {
                        InvestmentTransactionListRow(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingTransactionDelete = transaction
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            case .idle, .loading:
                ForEach(0..<3, id: \.self) { _ in
                    Text(verbatim: "Buy · AAPL · 10 shares")
                }
                .redactedWhileLoading(true)
            }
        } header: {
            Text("Recent Buys & Sells")
        }
    }

    private func filteredHoldings(_ all: [PortfolioHolding]) -> [PortfolioHolding] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { holding in
            let symbol = holding.security?.symbol ?? ""
            let name = holding.security?.name ?? ""
            return symbol.localizedCaseInsensitiveContains(query) || name.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: Loading

    private func loadAll() async {
        async let summaryLoad: Void = loadSummary()
        async let holdingsLoad: Void = loadHoldings()
        async let recentLoad: Void = loadRecent()
        _ = await (summaryLoad, holdingsLoad, recentLoad)
    }

    private func reloadPortfolio() async {
        if let updated = try? await services.investmentsSend(Endpoints.portfolio(id: portfolio.id)) {
            portfolio = updated
        }
        await loadSummary()
    }

    private func loadSummary() async {
        if summary.value == nil { summary = .loading }
        do {
            summary = .loaded(try await services.investmentsSend(Endpoints.portfolioSummary(id: portfolio.id)))
        } catch {
            if summary.value == nil { summary = .failed(APIError(error)) }
        }
    }

    private func loadHoldings() async {
        if holdings.value == nil { holdings = .loading }
        do {
            let loaded = try await services.investmentsSend(Endpoints.holdings(portfolioID: portfolio.id))
            holdings = .loaded(loaded.sorted { ($0.security?.displaySymbol ?? "") < ($1.security?.displaySymbol ?? "") })
        } catch {
            if holdings.value == nil { holdings = .failed(APIError(error)) }
        }
    }

    private func loadRecent() async {
        if recent.value == nil { recent = .loading }
        do {
            let page = try await services.investmentsSend(
                Endpoints.investmentTransactions(portfolioID: portfolio.id, limit: 10)
            )
            recent = .loaded(page.transactions.filter { $0.category == .buy || $0.category == .sell })
        } catch {
            if recent.value == nil { recent = .failed(APIError(error)) }
        }
    }

    // MARK: Mutations

    private func deletePortfolio() async {
        do {
            _ = try await services.investmentsSend(Endpoints.portfolioDelete(id: portfolio.id))
            onChange()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func deleteHolding(_ holding: PortfolioHolding) async {
        do {
            _ = try await services.investmentsSend(
                Endpoints.holdingDelete(HoldingDeleteRequest(portfolioId: portfolio.id, securityId: holding.securityId))
            )
            await loadAll()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func deleteTransaction(_ transaction: InvestmentTransaction) async {
        do {
            _ = try await services.investmentsSend(Endpoints.investmentTransactionDelete(id: transaction.id))
            await loadAll()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// Total value, cost basis, unrealized, realized and total return, plus cash.
private struct PortfolioSummaryCard: View {
    let summary: PortfolioSummary?

    var body: some View {
        let currency = summary?.currencyCode ?? "USD"
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total Value")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: MoneyFormat.string(summary?.totalPortfolioValue ?? 0, currencyCode: currency))
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Holdings value").foregroundStyle(.secondary)
                    Text(verbatim: MoneyFormat.string(summary?.totalCurrentValue ?? 0, currencyCode: currency))
                        .monospacedDigit()
                }
                GridRow {
                    Text("Cost basis").foregroundStyle(.secondary)
                    Text(verbatim: MoneyFormat.string(summary?.totalCostBasis ?? 0, currencyCode: currency))
                        .monospacedDigit()
                }
                GridRow {
                    Text("Unrealized").foregroundStyle(.secondary)
                    PortfolioGainText(
                        value: summary?.unrealizedGainValue ?? 0,
                        percent: summary?.unrealizedGainPercent,
                        currencyCode: currency
                    )
                }
                GridRow {
                    Text("Realized").foregroundStyle(.secondary)
                    PortfolioGainText(
                        value: summary?.realizedGainValue ?? 0,
                        percent: summary?.realizedGainPercent,
                        currencyCode: currency
                    )
                }
                GridRow {
                    Text("Total return").foregroundStyle(.secondary)
                    PortfolioGainText(
                        value: summary?.totalReturnValue ?? 0,
                        percent: summary?.totalReturnPercent,
                        currencyCode: currency
                    )
                }
                if let summary {
                    GridRow {
                        Text("Available cash").foregroundStyle(.secondary)
                        Text(verbatim: MoneyFormat.string(
                            summary.availableCashInBaseCurrency,
                            currencyCode: summary.baseCurrencyCode
                        ))
                        .monospacedDigit()
                    }
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

private struct PortfolioHoldingRow: View {
    let holding: PortfolioHolding?

    var body: some View {
        let currency = holding?.displayCurrencyCode ?? holding?.currencyCode ?? "USD"
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: holding?.security?.displaySymbol ?? "SYMBOL")
                    .font(.body.weight(.semibold))
                Text(verbatim: holding?.security?.name ?? "Security name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(PortfolioNumberFormat.quantity(holding?.quantity ?? 0)) units")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: MoneyFormat.string(
                    holding?.displayMarketValue ?? holding?.marketValue ?? 0,
                    currencyCode: currency
                ))
                .monospacedDigit()
                if let gain = holding?.displayUnrealizedGainValue ?? holding?.unrealizedGainValue {
                    PortfolioGainText(value: gain, percent: holding?.unrealizedGainPercent, currencyCode: currency)
                        .font(.caption)
                }
            }
        }
        .opacity(holding?.excluded == true ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}
