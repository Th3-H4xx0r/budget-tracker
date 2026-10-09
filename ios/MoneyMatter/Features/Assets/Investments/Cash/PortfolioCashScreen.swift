import MoneyMatterKit
import SwiftUI

/// Cash balances, cash transactions, transfers and currency exchange for one portfolio.
/// Mirrors the web portfolio cash balances card and cash transactions list.
struct PortfolioCashScreen: View {
    let portfolioID: String
    let portfolioName: String

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData

    @State private var balances: LoadState<[PortfolioCashBalance]> = .idle
    @State private var transfers: LoadState<[PortfolioCashTransfer]> = .idle
    @State private var action: PortfolioCashAction?
    @State private var pendingDelete: PortfolioCashTransfer?
    @State private var alert: ErrorAlert?

    var body: some View {
        List {
            Section {
                balancesSection
            } header: {
                Text("Cash Balances")
            }
            Section {
                transfersSection
            } header: {
                Text("Cash Transactions")
            } footer: {
                Text("Adjustments correct the balance and don't count as contributions.")
            }
        }
        .navigationTitle("Cash")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(PortfolioCashAction.allCases) { item in
                        Button {
                            action = item
                        } label: {
                            Label { Text(item.title) } icon: { Image(systemName: item.symbol) }
                        }
                    }
                } label: {
                    Label("Add Cash Transaction", systemImage: "plus")
                }
            }
        }
        .sheet(item: $action) { item in
            PortfolioCashActionSheet(
                action: item,
                portfolioID: portfolioID,
                balances: balances.value ?? []
            ) {
                await reload()
                await referenceData.refreshAccounts()
            }
        }
        .confirmationDialog(
            "Delete this cash transaction?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { transfer in
            if transfer.transactionId != nil {
                Button("Delete with Account Transaction", role: .destructive) {
                    Task { await delete(transfer, deleteLinkedTransaction: true) }
                }
                Button("Delete, Keep Account Transaction", role: .destructive) {
                    Task { await delete(transfer, deleteLinkedTransaction: false) }
                }
            } else {
                Button("Delete", role: .destructive) {
                    Task { await delete(transfer, deleteLinkedTransaction: false) }
                }
            }
        } message: { _ in
            Text("The portfolio's cash balance is recalculated.")
        }
        .errorAlert($alert)
        .task {
            if case .idle = balances { await reload() }
        }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private var balancesSection: some View {
        switch balances {
        case .idle, .loading:
            LabeledContent("USD", value: "0,000.00")
                .redactedWhileLoading(true)
        case .failed(let error):
            InlineRetryView(ErrorMessage.message(for: error)) { await reload() }
        case .loaded(let rows) where rows.isEmpty:
            VStack(alignment: .leading, spacing: 8) {
                Text("No cash in this portfolio yet.")
                    .foregroundStyle(.secondary)
                Button("Deposit Cash") { action = .deposit }
            }
        case .loaded(let rows):
            ForEach(rows) { balance in
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        AmountText(balance.totalCash, currencyCode: balance.currencyCode)
                            .font(.body.weight(.semibold))
                        if balance.availableCash != balance.totalCash {
                            HStack(spacing: 4) {
                                Text("Available")
                                AmountText(balance.availableCash, currencyCode: balance.currencyCode)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    Text(verbatim: balance.currencyCode)
                        .font(.body.weight(.medium))
                }
            }
        }
    }

    @ViewBuilder
    private var transfersSection: some View {
        switch transfers {
        case .idle, .loading:
            Text("Loading cash transactions")
                .frame(minHeight: 44)
                .redactedWhileLoading(true)
        case .failed(let error):
            InlineRetryView(ErrorMessage.message(for: error)) { await reload() }
        case .loaded(let rows) where rows.isEmpty:
            Text("Deposits, withdrawals, transfers, and exchanges appear here.")
                .foregroundStyle(.secondary)
        case .loaded(let rows):
            ForEach(rows) { transfer in
                PortfolioCashTransferRow(
                    transfer: transfer,
                    portfolioID: portfolioID,
                    accountName: accountName(for: transfer)
                )
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = transfer }
                    Button {
                        Task { await toggleAdjustment(transfer) }
                    } label: {
                        Label(
                            transfer.isAdjustment ? "Contribution" : "Adjustment",
                            systemImage: transfer.isAdjustment ? "arrow.down.circle" : "wrench.adjustable"
                        )
                    }
                    .tint(.orange)
                }
                .contextMenu {
                    Button {
                        Task { await toggleAdjustment(transfer) }
                    } label: {
                        if transfer.isAdjustment {
                            Label("Mark as Contribution", systemImage: "arrow.down.circle")
                        } else {
                            Label("Mark as Adjustment", systemImage: "wrench.adjustable")
                        }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = transfer }
                }
            }
        }
    }

    private func accountName(for transfer: PortfolioCashTransfer) -> String? {
        referenceData.account(id: transfer.fromAccountId ?? transfer.toAccountId)?.name
    }

    private func reload() async {
        guard let client = services.client else { return }
        if balances.value == nil { balances = .loading }
        if transfers.value == nil { transfers = .loading }
        async let balanceResult = Self.capture { try await client.send(Endpoints.portfolioCashBalances(portfolioId: portfolioID)) }
        async let transferResult = Self.capture { try await client.send(Endpoints.portfolioCashTransfers(portfolioId: portfolioID)) }
        switch await balanceResult {
        case .success(let rows):
            balances = .loaded(rows.sorted { $0.currencyCode < $1.currencyCode })
        case .failure(let error):
            if balances.value == nil { balances = .failed(APIError(error)) }
        }
        switch await transferResult {
        case .success(let rows): transfers = .loaded(rows)
        case .failure(let error):
            if transfers.value == nil { transfers = .failed(APIError(error)) }
        }
    }

    nonisolated private static func capture<Value: Sendable>(_ body: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do {
            return .success(try await body())
        } catch {
            return .failure(error)
        }
    }

    private func toggleAdjustment(_ transfer: PortfolioCashTransfer) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.portfolioCashSetAdjustment(
                portfolioId: portfolioID,
                transferId: transfer.id,
                isAdjustment: !transfer.isAdjustment
            ))
            await reload()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func delete(_ transfer: PortfolioCashTransfer, deleteLinkedTransaction: Bool) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.portfolioCashTransferDelete(
                portfolioId: portfolioID,
                transferId: transfer.id,
                deleteLinkedTransaction: deleteLinkedTransaction
            ))
            await reload()
            await referenceData.refreshAccounts()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}


/// The cash actions available on a portfolio.
enum PortfolioCashAction: String, CaseIterable, Identifiable {
    case deposit
    case withdraw
    case fromAccount
    case toAccount
    case toPortfolio
    case exchange

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .deposit: "Deposit Cash"
        case .withdraw: "Withdraw Cash"
        case .fromAccount: "Transfer from Account"
        case .toAccount: "Transfer to Account"
        case .toPortfolio: "Transfer to Portfolio"
        case .exchange: "Exchange Currency"
        }
    }

    var symbol: String {
        switch self {
        case .deposit: "arrow.down.circle"
        case .withdraw: "arrow.up.circle"
        case .fromAccount: "arrow.down.left.circle"
        case .toAccount: "arrow.up.right.circle"
        case .toPortfolio: "arrow.turn.up.right"
        case .exchange: "arrow.left.arrow.right.circle"
        }
    }
}

/// One cash movement: what kind, the counterparty, the amount, and the date.
private struct PortfolioCashTransferRow: View {
    let transfer: PortfolioCashTransfer
    let portfolioID: String
    let accountName: String?

    var body: some View {
        let kind = transfer.kind(for: portfolioID)
        let isInflow = transfer.isInflow(for: portfolioID)
        HStack(spacing: 12) {
            Image(systemName: symbol(kind))
                .foregroundStyle(isInflow ? Color.green : Color.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title(kind))
                        .font(.subheadline.weight(.medium))
                    if transfer.isAdjustment {
                        Text("Adjustment")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15), in: .capsule)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 4) {
                    Text(transfer.date.startDate().formatted(date: .abbreviated, time: .omitted))
                    if let accountName {
                        Text(verbatim: "· \(accountName)")
                    }
                    if let note = transfer.transferDescription, !note.isEmpty {
                        Text(verbatim: "· \(note)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(
                    transfer.amount,
                    currencyCode: transfer.currencyCode,
                    style: isInflow ? .income : .expense,
                    showsPlusSign: isInflow
                )
                .font(.subheadline.weight(.semibold))
                if kind == .exchange, let toAmount = transfer.toAmount, let toCode = transfer.toCurrencyCode {
                    AmountText(toAmount, currencyCode: toCode, style: .income, showsPlusSign: true)
                        .font(.caption)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func title(_ kind: PortfolioCashTransfer.Kind) -> LocalizedStringResource {
        switch kind {
        case .deposit: "Deposit"
        case .withdrawal: "Withdrawal"
        case .fromAccount: "From Account"
        case .toAccount: "To Account"
        case .fromPortfolio: "From Portfolio"
        case .toPortfolio: "To Portfolio"
        case .exchange: "Currency Exchange"
        }
    }

    private func symbol(_ kind: PortfolioCashTransfer.Kind) -> String {
        switch kind {
        case .deposit: "arrow.down.circle"
        case .withdrawal: "arrow.up.circle"
        case .fromAccount, .fromPortfolio: "arrow.down.left.circle"
        case .toAccount, .toPortfolio: "arrow.up.right.circle"
        case .exchange: "arrow.left.arrow.right.circle"
        }
    }
}
