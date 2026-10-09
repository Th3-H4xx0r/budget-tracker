import MoneyMatterKit
import SwiftUI

/// Picks another transaction: the original of a refund, or the opposite leg for linking two
/// rows as a transfer. Shows server suggestions first, then a searchable list.
struct TransactionPickScreen: View {
    enum Purpose {
        /// The refund is `transactionId` when saved; otherwise the form's type, amount, and account.
        case refundOriginal(transactionId: String?, type: TransactionType, amount: Decimal?, accountId: String?)
        /// A refund of `transaction`: a row of the opposite type.
        case refundFor(Transaction)
        /// The opposite leg for `transaction`: the other direction, on another account.
        case transferCounterpart(Transaction)
    }

    let purpose: Purpose
    let onPick: (Transaction) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var suggestions: [Transaction] = []
    @State private var results: LoadState<[Transaction]> = .idle
    @State private var searchText = ""

    var body: some View {
        List {
            if !suggestions.isEmpty, searchText.isEmpty {
                Section("Suggested") {
                    ForEach(suggestions) { row($0) }
                }
            }
            switch results {
            case .idle, .loading:
                Section { TransactionRowsPlaceholder(count: 5) }
            case .failed(let error):
                Section {
                    InlineRetryView(ErrorMessage.message(for: error)) { await search() }
                }
            case .loaded(let rows):
                let shown = rows.filter { row in !suggestions.contains { $0.id == row.id } || !searchText.isEmpty }
                if shown.isEmpty, suggestions.isEmpty || !searchText.isEmpty {
                    Section {
                        if searchText.isEmpty {
                            ContentUnavailableView(
                                "No Transactions",
                                systemImage: "list.bullet.rectangle.portrait",
                                description: Text(emptyDescription)
                            )
                        } else {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                    .listRowBackground(Color.clear)
                } else if !shown.isEmpty {
                    Section(searchText.isEmpty ? "Recent" : "Results") {
                        ForEach(shown) { row($0) }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search notes")
        .task { await loadSuggestions() }
        .task(id: searchText) {
            if !searchText.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private var title: LocalizedStringKey {
        switch purpose {
        case .refundOriginal: "Refund Of"
        case .refundFor: "Refunded By"
        case .transferCounterpart: "Link Transfer"
        }
    }

    private var emptyDescription: LocalizedStringKey {
        switch purpose {
        case .refundOriginal: "There are no transactions of the opposite type to refund."
        case .refundFor: "There are no transactions of the opposite type that could be the refund."
        case .transferCounterpart: "There are no transactions of the opposite type on other accounts."
        }
    }

    private func row(_ transaction: Transaction) -> some View {
        Button {
            onPick(transaction)
            dismiss()
        } label: {
            ResolvedTransactionRow(transaction: transaction, showsDate: true)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The direction the picked row must have.
    private var searchedType: TransactionType {
        switch purpose {
        case .refundOriginal(_, let type, _, _): type == .income ? .expense : .income
        case .refundFor(let transaction), .transferCounterpart(let transaction):
            transaction.transactionType == .income ? .expense : .income
        }
    }

    private var excludedId: String? {
        switch purpose {
        case .refundOriginal(let id, _, _, _): id
        case .refundFor(let transaction), .transferCounterpart(let transaction): transaction.id
        }
    }

    private func loadSuggestions() async {
        guard let client = services.client else { return }
        let endpoint: Endpoint<[Transaction]>
        switch purpose {
        case .transferCounterpart:
            return
        case .refundFor(let transaction):
            endpoint = Endpoints.refundRecommendations(transactionId: transaction.id)
        case .refundOriginal(let id, let type, let amount, let accountId):
            if let id {
                endpoint = Endpoints.refundRecommendations(transactionId: id)
            } else if let amount, amount > 0, let accountId {
                endpoint = Endpoints.refundRecommendations(transactionType: type, originAmount: amount, accountId: accountId)
            } else {
                return
            }
        }
        suggestions = ((try? await client.send(endpoint)) ?? []).filter { $0.id != excludedId }
    }

    private func search() async {
        if results.value == nil { results = .loading }
        var query = TransactionListQuery(limit: 40, offset: 0)
        query.sortBy = .time
        query.order = .descending
        query.transactionType = searchedType
        query.transferFilter = .exclude
        if case .transferCounterpart(let transaction) = purpose {
            query.excludeAccountIds = [transaction.accountId]
        }
        let term = searchText.trimmingCharacters(in: .whitespaces)
        if !term.isEmpty { query.noteSearch = [term] }
        do {
            let rows = try await services.transactions.transactions(query)
            results = .loaded(rows.filter { $0.id != excludedId && !$0.isPlanned })
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            results = .failed(apiError)
        }
    }
}
