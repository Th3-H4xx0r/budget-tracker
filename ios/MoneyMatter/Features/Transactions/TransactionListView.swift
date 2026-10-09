import MoneyMatterKit
import SwiftUI

/// The paginated transaction list in day sections, with swipe to edit or delete. The
/// Transactions tab shows it on its own; account detail passes a balance header.
struct TransactionListView<Header: View>: View {
    let model: TransactionListModel
    var emptyTitle: LocalizedStringKey = "No Transactions"
    var emptyDescription: LocalizedStringKey = "Transactions you add or import appear here."
    /// Row ids picked in edit mode. Nil turns multi-select off.
    var selection: Binding<Set<String>>? = nil
    @ViewBuilder var header: () -> Header

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(SessionStore.self) private var session
    @State private var editing: Transaction?
    @State private var pendingDelete: Transaction?
    @State private var errorAlert: ErrorAlert?
    @State private var markingDoneId: String?

    var body: some View {
        Group {
            if let selection {
                List(selection: selection) {
                    header()
                    content
                }
            } else {
                List {
                    header()
                    content
                }
            }
        }
        .refreshable {
            await model.reload(using: services.transactions)
        }
        .task {
            if !model.hasLoaded { await model.reload(using: services.transactions) }
        }
        .onChange(of: TransactionChangeFeed.shared.latest) { _, event in
            guard let event, model.apply(event.change) else { return }
            Task { await model.reload(using: services.transactions) }
        }
        .sheet(item: $editing) { transaction in
            TransactionEditorSheet(mode: .edit(transaction))
        }
        .confirmationDialog(
            "Delete this transaction?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { transaction in
            Button("Delete Transaction", role: .destructive) {
                Task { await delete(transaction) }
            }
        } message: { transaction in
            Text(transaction.transferId != nil
                ? "Both sides of the transfer are deleted. This can't be undone."
                : "This can't be undone.")
        }
        .errorAlert($errorAlert)
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            if let error = model.error {
                Section {
                    LoadFailedView(error: error) { await model.reload(using: services.transactions) }
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    TransactionRowsPlaceholder(count: 6)
                }
            }
        } else if model.transactions.isEmpty {
            Section {
                if model.isSearching {
                    ContentUnavailableView.search(text: model.searchText)
                } else if model.filter.activeCount > 0 {
                    ContentUnavailableView(
                        "No Matching Transactions",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try changing or resetting the filters.")
                    )
                } else {
                    ContentUnavailableView(emptyTitle, systemImage: "list.bullet.rectangle.portrait", description: Text(emptyDescription))
                }
            }
            .listRowBackground(Color.clear)
        } else {
            if model.showsPlannedSection, !model.planned.isEmpty {
                plannedSection
            }
            ForEach(model.days) { day in
                Section {
                    ForEach(day.transactions) { transaction in
                        row(for: transaction)
                    }
                } header: {
                    dayHeader(day)
                }
            }
            if model.hasMore {
                Section {
                    if let pageError = model.pageError {
                        InlineRetryView(ErrorMessage.message(for: pageError)) {
                            await model.loadMore(using: services.transactions)
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .task(id: model.pageLoads) {
                                await model.loadMore(using: services.transactions)
                            }
                    }
                }
            }
        }
    }

    private var plannedSection: some View {
        Section {
            ForEach(model.planned) { transaction in
                row(for: transaction)
                    .swipeActions(edge: .leading) {
                        Button("Mark Done", systemImage: "checkmark.circle") {
                            Task { await markDone(transaction) }
                        }
                        .tint(.green)
                    }
            }
        } header: {
            HStack {
                Label("Planned", systemImage: "calendar.badge.clock")
                Spacer()
                if model.planned.count >= TransactionListModel.plannedLimit {
                    Text("Next \(TransactionListModel.plannedLimit)")
                }
            }
        } footer: {
            Text("Swipe right on a plan to mark it as paid.")
        }
    }

    /// Turns a plan into a real transaction (`isPlanned: false`).
    private func markDone(_ transaction: Transaction) async {
        guard let client = services.client, markingDoneId == nil else { return }
        markingDoneId = transaction.id
        defer { markingDoneId = nil }
        do {
            let rows = try await client.send(Endpoints.updateTransactionAdvanced(
                id: transaction.id,
                TransactionAdvancedUpdateRequest(isPlanned: false)
            ))
            TransactionChangeFeed.shared.publish(.saved(rows))
            await referenceData.refreshAccounts()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func row(for transaction: Transaction) -> some View {
        NavigationLink {
            TransactionDetailScreen(transactionID: transaction.id, initial: transaction)
        } label: {
            ResolvedTransactionRow(transaction: transaction)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash") {
                pendingDelete = transaction
            }
            .tint(.red)
            Button("Edit", systemImage: "pencil") {
                editing = transaction
            }
            .tint(.blue)
        }
    }

    private func dayHeader(_ day: TransactionDay) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Self.dayTitle(day.id))
            Spacer()
            if let total = netTotal(of: day) {
                AmountText(
                    total.amount,
                    currencyCode: total.currencyCode,
                    digits: referenceData.digits(for: total.currencyCode),
                    showsPlusSign: true
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// The day's net in one currency: the account's own on account detail, else the base
    /// currency, leaving out transfers between the user's own accounts.
    private func netTotal(of day: TransactionDay) -> (amount: Decimal, currencyCode: String)? {
        if model.scopeAccountIds.count == 1, let first = day.transactions.first,
           day.transactions.allSatisfy({ $0.currencyCode == first.currencyCode }) {
            return (day.transactions.reduce(0) { $0 + $1.signedAmount }, first.currencyCode)
        }
        guard let code = session.baseCurrency?.currencyCode else { return nil }
        let rows = day.transactions.filter { !$0.transferNature.isTwoLegTransfer }
        return (rows.reduce(0) { $0 + $1.signedRefAmount }, code)
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return day.formatted(.dateTime.day().month(.wide).year())
    }

    private func delete(_ transaction: Transaction) async {
        do {
            try await services.transactions.deleteTransaction(id: transaction.id)
            TransactionChangeFeed.shared.publish(.deleted(id: transaction.id, transferId: transaction.transferId))
            await referenceData.refreshAccounts()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

extension TransactionListView where Header == EmptyView {
    init(
        model: TransactionListModel,
        emptyTitle: LocalizedStringKey = "No Transactions",
        emptyDescription: LocalizedStringKey = "Transactions you add or import appear here.",
        selection: Binding<Set<String>>? = nil
    ) {
        self.init(model: model, emptyTitle: emptyTitle, emptyDescription: emptyDescription, selection: selection) { EmptyView() }
    }
}
