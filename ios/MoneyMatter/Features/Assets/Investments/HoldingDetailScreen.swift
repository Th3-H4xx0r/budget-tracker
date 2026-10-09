import MoneyMatterKit
import SwiftUI

/// One holding: position stats and its transactions, with buy, sell, edit and delete.
struct HoldingDetailScreen: View {
    let portfolio: Portfolio
    let holding: PortfolioHolding
    let onChange: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var transactions: [InvestmentTransaction] = []
    @State private var total = 0
    @State private var loadState: LoadState<Void> = .idle
    @State private var isLoadingMore = false
    @State private var newCategory: HoldingNewTransactionDraft?
    @State private var editing: InvestmentTransaction?
    @State private var pendingDelete: InvestmentTransaction?
    @State private var isConfirmingHoldingDelete = false
    @State private var alert: ErrorAlert?

    private static let pageSize = 25

    private var symbol: String { holding.security?.displaySymbol ?? "" }
    private var securityCurrency: String { holding.security?.currencyCode ?? holding.currencyCode }

    var body: some View {
        List {
            Section {
                statsGrid
            } header: {
                if let name = holding.security?.name {
                    Text(verbatim: name)
                }
            }
            transactionsSection
        }
        .navigationTitle(symbol)
        .refreshable { await reload() }
        .task {
            if case .idle = loadState { await reload() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        newCategory = HoldingNewTransactionDraft(category: .buy)
                    } label: {
                        Label("Buy", systemImage: InvestmentTransactionCategory.buy.symbolName)
                    }
                    Button {
                        newCategory = HoldingNewTransactionDraft(category: .sell)
                    } label: {
                        Label("Sell", systemImage: InvestmentTransactionCategory.sell.symbolName)
                    }
                } label: {
                    Label("Add Transaction", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    isConfirmingHoldingDelete = true
                } label: {
                    Label("Delete Holding", systemImage: "trash")
                }
            }
        }
        .sheet(item: $newCategory) { draft in
            InvestmentTransactionFormSheet(
                portfolioID: portfolio.id,
                securityID: holding.securityId,
                securityCurrencyCode: securityCurrency,
                symbol: symbol,
                initialCategory: draft.category,
                existing: nil
            ) {
                Task { await changed() }
            }
        }
        .sheet(item: $editing) { transaction in
            InvestmentTransactionFormSheet(
                portfolioID: portfolio.id,
                securityID: holding.securityId,
                securityCurrencyCode: securityCurrency,
                symbol: symbol,
                initialCategory: transaction.category,
                existing: transaction
            ) {
                Task { await changed() }
            }
        }
        .confirmationDialog(
            "Delete Transaction?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { transaction in
            Button("Delete Transaction", role: .destructive) {
                Task { await delete(transaction) }
            }
        }
        .confirmationDialog("Delete Holding?", isPresented: $isConfirmingHoldingDelete, titleVisibility: .visible) {
            Button("Delete Holding", role: .destructive) {
                Task { await deleteHolding() }
            }
        } message: {
            Text("The holding and all its transactions are deleted, and their cash impact is reversed.")
        }
        .errorAlert($alert)
    }

    private var statsGrid: some View {
        let currency = holding.currencyCode
        let averageCost: Decimal? = holding.quantity > 0 ? holding.costBasis / holding.quantity : nil
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Quantity").foregroundStyle(.secondary)
                Text(verbatim: PortfolioNumberFormat.quantity(holding.quantity)).monospacedDigit()
            }
            if let averageCost {
                GridRow {
                    Text("Average cost").foregroundStyle(.secondary)
                    Text(verbatim: MoneyFormat.string(averageCost, currencyCode: currency)).monospacedDigit()
                }
            }
            GridRow {
                Text("Cost basis").foregroundStyle(.secondary)
                Text(verbatim: MoneyFormat.string(holding.costBasis, currencyCode: currency)).monospacedDigit()
            }
            if let price = holding.latestPrice {
                GridRow {
                    Text("Latest price").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: MoneyFormat.string(price, currencyCode: currency)).monospacedDigit()
                        if let priceDate = holding.priceDate {
                            Text(priceDate, format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let marketValue = holding.marketValue {
                GridRow {
                    Text("Market value").foregroundStyle(.secondary)
                    Text(verbatim: MoneyFormat.string(marketValue, currencyCode: currency)).monospacedDigit()
                }
            }
            if let unrealized = holding.unrealizedGainValue {
                GridRow {
                    Text("Unrealized").foregroundStyle(.secondary)
                    PortfolioGainText(value: unrealized, percent: holding.unrealizedGainPercent, currencyCode: currency)
                }
            }
            if let realized = holding.realizedGainValue {
                GridRow {
                    Text("Realized").foregroundStyle(.secondary)
                    PortfolioGainText(value: realized, percent: nil, currencyCode: currency)
                }
            }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }

    @ViewBuilder private var transactionsSection: some View {
        Section {
            switch loadState {
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await reload() }
            case .loaded where transactions.isEmpty:
                ContentUnavailableView {
                    Label("No Transactions", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Record a buy to start building this position.")
                } actions: {
                    Button("Add Buy") { newCategory = HoldingNewTransactionDraft(category: .buy) }
                        .buttonStyle(.borderedProminent)
                }
            case .loaded:
                ForEach(transactions) { transaction in
                    Button {
                        editing = transaction
                    } label: {
                        InvestmentTransactionListRow(transaction: transaction, showsSymbol: false)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = transaction
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            editing = transaction
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingDelete = transaction
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                if transactions.count < total {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        if isLoadingMore {
                            ProgressView()
                        } else {
                            Text("Load More")
                        }
                    }
                    .disabled(isLoadingMore)
                }
            case .idle, .loading:
                ForEach(0..<4, id: \.self) { _ in
                    Text(verbatim: "Buy · 10 · $100.00")
                }
                .redactedWhileLoading(true)
            }
        } header: {
            Text("Transactions")
        }
    }

    private func reload() async {
        if transactions.isEmpty { loadState = .loading }
        do {
            let page = try await services.investmentsSend(Endpoints.investmentTransactions(
                portfolioID: portfolio.id,
                securityID: holding.securityId,
                limit: Self.pageSize
            ))
            transactions = page.transactions
            total = page.total
            loadState = .loaded(())
        } catch {
            if transactions.isEmpty { loadState = .failed(APIError(error)) } else { alert = ErrorAlert(error) }
        }
    }

    private func loadMore() async {
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await services.investmentsSend(Endpoints.investmentTransactions(
                portfolioID: portfolio.id,
                securityID: holding.securityId,
                limit: Self.pageSize,
                offset: transactions.count
            ))
            let known = Set(transactions.map(\.id))
            transactions.append(contentsOf: page.transactions.filter { !known.contains($0.id) })
            total = page.total
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func changed() async {
        await reload()
        onChange()
    }

    private func delete(_ transaction: InvestmentTransaction) async {
        do {
            _ = try await services.investmentsSend(Endpoints.investmentTransactionDelete(id: transaction.id))
            await changed()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func deleteHolding() async {
        do {
            _ = try await services.investmentsSend(Endpoints.holdingDelete(
                HoldingDeleteRequest(portfolioId: portfolio.id, securityId: holding.securityId)
            ))
            onChange()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

private struct HoldingNewTransactionDraft: Identifiable {
    let category: InvestmentTransactionCategory
    var id: String { category.rawValue }
}
