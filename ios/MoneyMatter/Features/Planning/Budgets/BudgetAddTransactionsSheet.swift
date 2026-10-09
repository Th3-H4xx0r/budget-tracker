import MoneyMatterKit
import SwiftUI

/// Picks transactions that aren't in the budget yet and adds them to a manual budget.
struct BudgetAddTransactionsSheet: View {
    let budgetID: String
    var onAdded: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var state: LoadState<[Transaction]> = .idle
    @State private var selection = Set<String>()
    @State private var searchText = ""
    @State private var hasMore = false
    @State private var isLoadingMore = false
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    private static let pageSize = 50

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add Transactions")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: Text("Search notes"))
                .task(id: searchText) {
                    if !searchText.isEmpty {
                        try? await Task.sleep(for: .milliseconds(350))
                        if Task.isCancelled { return }
                    }
                    await load(reset: true)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button {
                                Task { await add() }
                            } label: {
                                if selection.isEmpty {
                                    Text("Add")
                                } else {
                                    Text("Add \(selection.count)")
                                }
                            }
                            .disabled(selection.isEmpty)
                        }
                    }
                }
                .errorAlert($alert)
        }
        .interactiveDismissDisabled(isSaving || !selection.isEmpty)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            List { TransactionRowsPlaceholder() }
        case .failed(let error):
            LoadFailedView(error: error) { await load(reset: true) }
        case .loaded(let transactions):
            if transactions.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No Transactions to Add",
                        systemImage: "tray",
                        description: Text("Every transaction is already in this budget.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                List(selection: $selection) {
                    ForEach(transactions) { transaction in
                        ResolvedTransactionRow(transaction: transaction, showsDate: true)
                            .tag(transaction.id)
                    }
                    if hasMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .task { await load(reset: false) }
                        .selectionDisabled()
                    }
                }
                .environment(\.editMode, .constant(.active))
            }
        }
    }

    private func load(reset: Bool) async {
        guard let client = services.client else { return }
        if reset {
            if state.value == nil { state = .loading }
        } else {
            guard !isLoadingMore else { return }
            isLoadingMore = true
        }
        defer { isLoadingMore = false }
        let existing = reset ? [] : (state.value ?? [])
        var query = TransactionListQuery(limit: Self.pageSize, offset: existing.count)
        query.order = .descending
        query.excludedBudgetIds = [budgetID]
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty { query.noteSearch = [term] }
        do {
            let page = try await client.send(Endpoints.transactions(query))
            state = .loaded(existing + page)
            hasMore = page.count == Self.pageSize
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(error) }
            hasMore = false
        }
    }

    private func add() async {
        guard let client = services.client, !selection.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.send(
                Endpoints.addTransactionsToPlanningBudget(id: budgetID, transactionIds: Array(selection))
            )
            onAdded()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
