import MoneyMatterKit
import SwiftUI

/// Root of the Transactions tab: the searchable, filterable list, the Review button with the
/// unreviewed count, the new-transaction sheet, and the More menu (Review, Groups, Automations,
/// Optimizations).
struct TransactionsTab: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var model = TransactionListModel()
    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<String> = []
    @State private var isConfirmingBulkDelete = false
    @State private var isPickingBulkCategory = false
    @State private var isPickingBulkGroup = false
    @State private var isTemplatesPresented = false
    @State private var isBulkWorking = false
    @State private var bulkErrorAlert: ErrorAlert?
    @State private var searchText = ""
    @State private var isFilterPresented = false
    @State private var isCreatePresented = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.transactionsPath) {
            TransactionListView(model: model, selection: $selection)
                .environment(\.editMode, $editMode)
                .navigationTitle(isSelecting ? selectionTitle : String(localized: "Transactions"))
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
                        if isSelecting {
                            Button("Done") { endSelecting() }
                                .fontWeight(.semibold)
                        } else {
                            filterButton
                            Button("Add Transaction", systemImage: "plus") {
                                isCreatePresented = true
                            }
                            moreMenu
                        }
                    }
                    if isSelecting {
                        ToolbarItemGroup(placement: .bottomBar) {
                            bulkActions
                        }
                    }
                }
                .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
                .confirmationDialog(
                    "Delete \(selection.count) transactions?",
                    isPresented: $isConfirmingBulkDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete Transactions", role: .destructive) {
                        Task { await bulkDelete() }
                    }
                } message: {
                    Text("Deleting one side of a transfer deletes both sides. This can't be undone.")
                }
                .sheet(isPresented: $isPickingBulkCategory) {
                    NavigationStack {
                        TransactionCategoryPicker(isSelected: { _ in false }) { category in
                            Task { await bulkSetCategory(category.id) }
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { isPickingBulkCategory = false }
                            }
                        }
                    }
                }
                .sheet(isPresented: $isPickingBulkGroup) {
                    TransactionBulkGroupSheet(transactionIds: selection.sorted()) {
                        endSelecting()
                    }
                }
                .sheet(isPresented: $isTemplatesPresented) {
                    NavigationStack {
                        TransactionTemplatesScreen()
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { isTemplatesPresented = false }
                                }
                            }
                    }
                }
                .errorAlert($bulkErrorAlert)
                .sheet(isPresented: $isFilterPresented) {
                    TransactionFilterSheet(filter: model.filter) { filter in
                        Task { await model.update(filter: filter, using: services.transactions) }
                    }
                }
                .sheet(isPresented: $isCreatePresented) {
                    TransactionEditorSheet(mode: .create(accountId: nil))
                }
                .navigationDestination(for: TransactionsRoute.self) { route in
                    TransactionsRouteDestination(route: route)
                }
        }
    }

    private var isSelecting: Bool { editMode.isEditing }

    private var selectionTitle: String {
        selection.isEmpty ? String(localized: "Select Transactions") : String(localized: "\(selection.count) Selected")
    }

    @ViewBuilder
    private var bulkActions: some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            isConfirmingBulkDelete = true
        }
        .disabled(selection.isEmpty || isBulkWorking)
        Spacer()
        if isBulkWorking {
            ProgressView()
            Spacer()
        }
        Button("Set Category", systemImage: "folder") {
            isPickingBulkCategory = true
        }
        .disabled(selection.isEmpty || isBulkWorking)
        Spacer()
        Button("Add to Group", systemImage: "rectangle.stack.badge.plus") {
            isPickingBulkGroup = true
        }
        .disabled(selection.isEmpty || isBulkWorking)
    }

    private func endSelecting() {
        withAnimation {
            editMode = .inactive
            selection = []
        }
    }

    private func bulkDelete() async {
        guard let client = services.client, !selection.isEmpty else { return }
        isBulkWorking = true
        defer { isBulkWorking = false }
        do {
            // The server takes at most 500 ids per call.
            let ids = selection.sorted()
            for start in stride(from: 0, to: ids.count, by: 500) {
                let chunk = Array(ids[start..<min(start + 500, ids.count)])
                _ = try await client.send(Endpoints.bulkDeleteTransactions(TransactionBulkDeleteRequest(transactionIds: chunk)))
            }
            endSelecting()
        } catch {
            bulkErrorAlert = ErrorAlert(error)
        }
        TransactionChangeFeed.shared.publish(.invalidated)
        await referenceData.refreshAccounts()
    }

    private func bulkSetCategory(_ categoryId: String) async {
        guard let client = services.client, !selection.isEmpty else { return }
        isBulkWorking = true
        defer { isBulkWorking = false }
        do {
            _ = try await client.send(Endpoints.bulkSetCategory(
                TransactionBulkCategoryRequest(transactionIds: selection.sorted(), categoryId: categoryId)
            ))
            TransactionChangeFeed.shared.publish(.invalidated)
            endSelecting()
        } catch {
            bulkErrorAlert = ErrorAlert(error)
        }
    }

    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Button("Select", systemImage: "checkmark.circle") {
                withAnimation { editMode = .active }
            }
            .disabled(model.transactions.isEmpty)
            Button("Templates", systemImage: "doc.on.doc") {
                isTemplatesPresented = true
            }
            Divider()
            Button("Review", systemImage: "checkmark.shield") {
                router.transactionsPath.append(.reviewPage(.unreviewed))
            }
            Button("Groups", systemImage: "rectangle.stack") {
                router.transactionsPath.append(.groups)
            }
            Button("Automations", systemImage: "wand.and.stars") {
                router.transactionsPath.append(.automations)
            }
            Button("Optimizations", systemImage: "sparkles") {
                router.transactionsPath.append(.optimizations)
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

/// The destination for each `TransactionsRoute`. Registered by the Transactions stack, and by
/// the Planning and Insights stacks so `AppRouter.openTransaction(id:)` and
/// `openReviewPage(_:)` can push in place there.
struct TransactionsRouteDestination: View {
    let route: TransactionsRoute

    var body: some View {
        switch route {
        case .transaction(let id):
            TransactionDetailScreen(transactionID: id)
        case .reviewPage(let status):
            ReviewPageScreen(initialStatus: status)
        case .groups:
            TransactionGroupsScreen()
        case .automations:
            AutomationsScreen()
        case .optimizations:
            OptimizationsScreen()
        }
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
