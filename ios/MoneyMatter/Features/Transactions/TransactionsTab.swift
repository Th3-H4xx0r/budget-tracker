import MoneyMatterKit
import SwiftUI

/// Root of the Transactions tab: the searchable, filterable list, the Review button with the
/// unreviewed count, and the new-transaction sheet.
struct TransactionsTab: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @State private var model = TransactionListModel()
    @State private var searchText = ""
    @State private var isFilterPresented = false
    @State private var isCreatePresented = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.transactionsPath) {
            TransactionListView(model: model)
                .navigationTitle("Transactions")
                .searchable(text: $searchText, prompt: "Search notes")
                .task(id: searchText) {
                    guard searchText != model.searchText else { return }
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await model.update(searchText: searchText, using: services.transactions)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ReviewToolbarButton()
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        filterButton
                        Button("Add Transaction", systemImage: "plus") {
                            isCreatePresented = true
                        }
                    }
                }
                .sheet(isPresented: $isFilterPresented) {
                    TransactionFilterSheet(filter: model.filter) { filter in
                        Task { await model.update(filter: filter, using: services.transactions) }
                    }
                }
                .sheet(isPresented: $isCreatePresented) {
                    TransactionEditorSheet(mode: .create(accountId: nil))
                }
                .navigationDestination(for: TransactionsRoute.self) { route in
                    switch route {
                    case .transaction(let id):
                        TransactionDetailScreen(transactionID: id)
                    case .reviewPage(let status):
                        ReviewPageScreen(initialStatus: status)
                    }
                }
        }
    }

    private var filterButton: some View {
        Button {
            isFilterPresented = true
        } label: {
            Image(systemName: model.filter.activeCount > 0
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
                .overlay(alignment: .topTrailing) {
                    ToolbarCountBadge(count: model.filter.activeCount)
                }
        }
        .accessibilityLabel("Filters")
        .accessibilityValue(model.filter.activeCount > 0 ? Text("\(model.filter.activeCount) active") : Text(""))
    }
}

/// A small red count capsule for toolbar icons. Hidden at zero.
struct ToolbarCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(verbatim: count > 99 ? "99+" : "\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 16, minHeight: 16)
                .background(.red, in: .capsule)
                .offset(x: 8, y: -8)
                .accessibilityHidden(true)
        }
    }
}
