import Charts
import MoneyMatterKit
import SwiftUI

/// One budget: stats, limit utilization, category and timeline charts, and its transactions.
/// Category budgets list the transactions their categories match; manual budgets list the
/// transactions added to them, which can be added or removed here.
struct BudgetDetailScreen: View {
    let budgetID: String
    var onChange: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var budget: PlanningBudget?
    @State private var loadError: APIError?
    @State private var stats: PlanningBudgetStats?
    @State private var spending: LoadState<PlanningBudgetSpendingStats> = .idle
    @State private var chartMode = ChartMode.categories
    @State private var manualTransactions: [Transaction] = []
    @State private var categoryTransactions: [PlanningBudgetCategoryTransaction] = []
    @State private var transactionsError: APIError?
    @State private var hasMoreTransactions = false
    @State private var hasLoadedTransactions = false
    @State private var isLoadingMore = false
    @State private var isEditing = false
    @State private var isSharing = false
    @State private var isAddingTransactions = false
    @State private var isConfirmingDelete = false
    @State private var pendingRemovalIDs: [String]?
    @State private var isSelecting = false
    @State private var selectedIDs = Set<String>()
    @State private var alert: ErrorAlert?

    private static let pageSize = 30

    private enum ChartMode: Hashable { case categories, timeline }

    init(budgetID: String, initial: PlanningBudget? = nil, onChange: @escaping () async -> Void = {}) {
        self.budgetID = budgetID
        self.onChange = onChange
        _budget = State(initialValue: initial)
    }

    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }

    var body: some View {
        Group {
            if let budget {
                content(budget)
            } else if let loadError {
                LoadFailedView(error: loadError) { await loadAll() }
            } else {
                content(PlanningBudget(id: budgetID, name: "Budget name", limitAmount: 1000))
                    .redactedWhileLoading(true)
            }
        }
        .navigationTitle(budget?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .sheet(isPresented: $isSharing) {
            ShareResourceSheet(resourceType: .budget, resourceID: budgetID)
        }
        .sheet(isPresented: $isEditing) {
            if let budget {
                BudgetFormSheet(budget: budget) { saved in
                    if let saved { self.budget = saved }
                    Task {
                        await loadAll()
                        await onChange()
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingTransactions) {
            BudgetAddTransactionsSheet(budgetID: budgetID) {
                Task {
                    await loadAll()
                    await onChange()
                }
            }
        }
        .confirmationDialog(
            "Delete Budget?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("The budget will be deleted. Its transactions stay in your accounts.")
        }
        .confirmationDialog(
            "Remove from Budget?",
            isPresented: Binding(get: { pendingRemovalIDs != nil }, set: { if !$0 { pendingRemovalIDs = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemovalIDs
        ) { ids in
            Button(role: .destructive) {
                Task { await remove(ids) }
            } label: {
                if ids.count == 1 {
                    Text("Remove")
                } else {
                    Text("Remove \(ids.count) Transactions")
                }
            }
        } message: { _ in
            Text("Transactions stay in your accounts; they just stop counting toward this budget.")
        }
        .errorAlert($alert)
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if let budget, budget.canManage || budget.isOwner || budget.canWrite {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if budget.type != .category, budget.canWrite {
                    Button {
                        isAddingTransactions = true
                    } label: {
                        Label("Add Transactions", systemImage: "plus")
                    }
                    .accessibilityLabel(Text("Add Transactions"))
                }
                Menu {
                    if budget.canManage {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            Task { await setArchived(!budget.isArchived) }
                        } label: {
                            if budget.isArchived {
                                Label("Unarchive", systemImage: "archivebox.fill")
                            } else {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                    }
                    if budget.isOwner {
                        Button {
                            isSharing = true
                        } label: {
                            Label("Share", systemImage: "person.badge.plus")
                        }
                    }
                    if budget.isOwner {
                        Divider()
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .accessibilityLabel(Text("Budget actions"))
            }
        }
    }

    // MARK: Content

    private func content(_ budget: PlanningBudget) -> some View {
        List(selection: $selectedIDs) {
            headerSection(budget)
            statsSection
            if let limit = budget.limitAmount {
                utilizationSection(limit: limit)
            }
            chartsSection
            transactionsSection(budget)
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                Button(role: .destructive) {
                    pendingRemovalIDs = Array(selectedIDs)
                } label: {
                    Text("Remove \(selectedIDs.count) from Budget")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(selectedIDs.isEmpty)
                .padding()
            }
        }
    }

    private func headerSection(_ budget: PlanningBudget) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    BudgetFormatting.typeLabel(budget.type)
                    if budget.isArchived {
                        Text("·")
                        Label("Archived", systemImage: "archivebox")
                    } else if let status = BudgetTimeStatus(budget: budget) {
                        Text("·")
                        status.text.foregroundStyle(status.tint)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let handle = budget.sharedByHandle {
                    Label {
                        Text("Shared by @\(handle)")
                    } icon: {
                        Image(systemName: "person.2")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let range = BudgetFormatting.dateRange(start: budget.startDate, end: budget.endDate) {
                    Label { range } icon: { Image(systemName: "calendar") }
                        .font(.subheadline)
                }
                if budget.type != .category, budget.autoInclude {
                    Label("Auto-includes transactions in this period", systemImage: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if budget.type == .category {
                DisclosureGroup {
                    ForEach(budget.categories) { category in
                        Label {
                            Text(category.name)
                        } icon: {
                            Circle()
                                .fill(Color(hex: category.color) ?? .secondary)
                                .frame(width: 10, height: 10)
                        }
                    }
                } label: {
                    LabeledContent("Tracked Categories") {
                        Text(budget.categories.count, format: .number)
                    }
                }
            }
        }
    }

    private var statsSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                statTile("Income", amount: stats?.actualIncome ?? 0, style: .income, symbol: "arrow.down.left")
                statTile("Expenses", amount: stats?.actualExpense ?? 0, style: .neutral, symbol: "arrow.up.right")
                statTile(
                    "Net Balance",
                    amount: stats?.balance ?? 0,
                    style: (stats?.balance ?? 0) >= 0 ? .income : .expense,
                    symbol: "equal"
                )
                VStack(alignment: .leading, spacing: 4) {
                    Label("Transactions", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(stats?.transactionsCount ?? 0, format: .number)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            .padding(.vertical, 4)
            .redactedWhileLoading(stats == nil)
        }
    }

    private func statTile(_ title: LocalizedStringKey, amount: Decimal, style: AmountStyle, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            AmountText(style == .neutral ? abs(amount) : amount, currencyCode: currencyCode, style: style)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func utilizationSection(limit: Decimal) -> some View {
        let rate = stats?.utilizationRate
        let spent = max(0, -(stats?.balance ?? 0))
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Utilization")
                            .font(.subheadline.weight(.medium))
                        Text("\(MoneyFormat.string(spent, currencyCode: currencyCode)) of \(MoneyFormat.string(limit, currencyCode: currencyCode))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    if let rate {
                        Text(rate / 100, format: .percent.precision(.fractionLength(0)))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(BudgetFormatting.utilizationColor(rate))
                    } else {
                        Text("N/A")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                BudgetUtilizationBar(rate: rate ?? 0, showsLabel: false)
                if limit > spent {
                    Text("\(MoneyFormat.string(limit - spent, currencyCode: currencyCode)) left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if spent > limit {
                    Text("\(MoneyFormat.string(spent - limit, currencyCode: currencyCode)) over the limit")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
            .redactedWhileLoading(stats == nil)
        }
    }

    // MARK: Charts

    private var chartsSection: some View {
        Section {
            switch spending {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            case .failed(let error):
                InlineRetryView(ErrorMessage.inline(for: error)) { await loadSpending() }
            case .loaded(let data):
                if data.isEmpty {
                    ContentUnavailableView(
                        "No Statistics Yet",
                        systemImage: "chart.bar",
                        description: Text("Charts appear once the budget has transactions.")
                    )
                } else {
                    Picker("Chart", selection: $chartMode) {
                        Text("Categories").tag(ChartMode.categories)
                        Text("Timeline").tag(ChartMode.timeline)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    switch chartMode {
                    case .categories: BudgetCategoryBreakdownChart(categories: data.spendingsByCategory, currencyCode: currencyCode)
                    case .timeline: BudgetTimelineChart(periods: data.periods, granularity: data.granularity, currencyCode: currencyCode)
                    }
                }
            }
        } header: {
            Text("Statistics")
        }
    }

    // MARK: Transactions

    @ViewBuilder private func transactionsSection(_ budget: PlanningBudget) -> some View {
        Section {
            if let transactionsError, !hasLoadedTransactions {
                InlineRetryView(ErrorMessage.inline(for: transactionsError)) { await loadTransactions(reset: true) }
            } else if !hasLoadedTransactions {
                TransactionRowsPlaceholder()
            } else if budget.type == .category {
                if categoryTransactions.isEmpty {
                    emptyTransactions(budget)
                } else {
                    ForEach(Array(categoryTransactions.enumerated()), id: \.offset) { _, transaction in
                        NavigationLink {
                            TransactionDetailScreen(transactionID: transaction.id)
                        } label: {
                            BudgetCategoryTransactionRow(transaction: transaction, currencyCode: currencyCode)
                        }
                    }
                }
            } else {
                if manualTransactions.isEmpty {
                    emptyTransactions(budget)
                } else {
                    ForEach(manualTransactions) { transaction in
                        NavigationLink {
                            TransactionDetailScreen(transactionID: transaction.id)
                        } label: {
                            ResolvedTransactionRow(transaction: transaction, showsDate: true)
                        }
                        .tag(transaction.id)
                        .swipeActions(edge: .trailing) {
                            if budget.canWrite {
                                Button(role: .destructive) {
                                    pendingRemovalIDs = [transaction.id]
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                }
            }
            if hasLoadedTransactions, hasMoreTransactions {
                Button {
                    Task { await loadTransactions(reset: false) }
                } label: {
                    if isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Load More").frame(maxWidth: .infinity)
                    }
                }
                .disabled(isLoadingMore)
            }
        } header: {
            HStack {
                Text("Transactions")
                if let count = stats?.transactionsCount {
                    Text(count, format: .number).monospacedDigit()
                }
                Spacer()
                if budget.type != .category, budget.canWrite, !manualTransactions.isEmpty {
                    Button {
                        withAnimation {
                            isSelecting.toggle()
                            selectedIDs.removeAll()
                        }
                    } label: {
                        isSelecting ? Text("Done") : Text("Select")
                    }
                    .font(.subheadline)
                    .textCase(nil)
                }
            }
        }
    }

    @ViewBuilder private func emptyTransactions(_ budget: PlanningBudget) -> some View {
        if budget.type == .category {
            ContentUnavailableView(
                "No Transactions",
                systemImage: "tray",
                description: Text("Transactions in the tracked categories will appear here.")
            )
        } else {
            ContentUnavailableView {
                Label("No Transactions", systemImage: "tray")
            } description: {
                Text("Add transactions to start tracking this budget.")
            } actions: {
                if budget.canWrite {
                    Button("Add Transactions") { isAddingTransactions = true }
                }
            }
        }
    }

    // MARK: Loading

    private func loadAll() async {
        guard let client = services.client else { return }
        let id = budgetID
        async let budgetValue = client.send(Endpoints.planningBudget(id: id))
        async let statsValue = client.send(Endpoints.planningBudgetStats(id: id))
        async let spendingValue = client.send(Endpoints.planningBudgetSpendingStats(id: id))
        do {
            budget = try await budgetValue
            loadError = nil
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation, budget == nil { loadError = apiError }
        }
        if let value = try? await statsValue { stats = value }
        do {
            spending = .loaded(try await spendingValue)
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation, spending.value == nil { spending = .failed(apiError) }
        }
        await loadTransactions(reset: true)
    }

    private func loadSpending() async {
        guard let client = services.client else { return }
        if spending.value == nil { spending = .loading }
        do {
            spending = .loaded(try await client.send(Endpoints.planningBudgetSpendingStats(id: budgetID)))
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation, spending.value == nil { spending = .failed(apiError) }
        }
    }

    private func loadTransactions(reset: Bool) async {
        guard let client = services.client, let budget else { return }
        if !reset { isLoadingMore = true }
        defer { isLoadingMore = false }
        do {
            if budget.type == .category {
                let offset = reset ? 0 : categoryTransactions.count
                let page = try await client.send(
                    Endpoints.planningBudgetCategoryTransactions(id: budgetID, from: offset, limit: Self.pageSize)
                )
                categoryTransactions = reset ? page.transactions : categoryTransactions + page.transactions
                hasMoreTransactions = categoryTransactions.count < page.total
            } else {
                let offset = reset ? 0 : manualTransactions.count
                var query = TransactionListQuery(limit: Self.pageSize, offset: offset)
                query.order = .descending
                query.budgetIds = [budgetID]
                let page = try await client.send(Endpoints.transactions(query))
                manualTransactions = reset ? page : manualTransactions + page
                hasMoreTransactions = page.count == Self.pageSize
            }
            transactionsError = nil
            hasLoadedTransactions = true
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if hasLoadedTransactions { alert = ErrorAlert(error) } else { transactionsError = apiError }
        }
    }

    // MARK: Mutations

    private func setArchived(_ isArchived: Bool) async {
        guard let client = services.client else { return }
        do {
            budget = try await client.send(Endpoints.setPlanningBudgetArchived(id: budgetID, isArchived: isArchived))
            await onChange()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func delete() async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.deletePlanningBudget(id: budgetID))
            await onChange()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func remove(_ ids: [String]) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.removeTransactionsFromPlanningBudget(id: budgetID, transactionIds: ids))
            manualTransactions.removeAll { ids.contains($0.id) }
            selectedIDs.subtract(ids)
            if manualTransactions.isEmpty || selectedIDs.isEmpty { isSelecting = false }
            if let value = try? await client.send(Endpoints.planningBudgetStats(id: budgetID)) { stats = value }
            await loadSpending()
            await onChange()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// A row from the category-budget transactions endpoint, which carries only the effective
/// category, note, and base-currency amount.
private struct BudgetCategoryTransactionRow: View {
    let transaction: PlanningBudgetCategoryTransaction
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: transaction.effectiveCategory?.color) ?? .secondary)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.effectiveCategory?.name ?? String(localized: "Uncategorized"))
                    .lineLimit(1)
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(transaction.time, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(
                transaction.budgetAmount,
                currencyCode: currencyCode,
                style: transaction.transactionType == .income ? .income : .expense
            )
            .font(.body.weight(.medium))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Donut of spending by top-level category, with the total in the middle and a legend below.
private struct BudgetCategoryBreakdownChart: View {
    let categories: [PlanningBudgetSpendingStats.CategorySpending]
    let currencyCode: String

    private var slices: [PlanningBudgetSpendingStats.CategorySpending] {
        categories.filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
    }

    private var total: Decimal { slices.reduce(0) { $0 + $1.amount } }

    var body: some View {
        if slices.isEmpty {
            Text("No category data")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: 16) {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Amount", NSDecimalNumber(decimal: slice.amount).doubleValue),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .cornerRadius(3)
                    .foregroundStyle(Color(hex: slice.color) ?? .gray)
                }
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let frame = proxy.plotFrame {
                            let rect = geometry[frame]
                            VStack(spacing: 2) {
                                Text("Total")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                AmountText(total, currencyCode: currencyCode)
                                    .font(.headline)
                            }
                            .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
                .frame(height: 200)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Spending by category"))
                .accessibilityValue(Text(accessibilitySummary))

                VStack(spacing: 8) {
                    ForEach(slices) { slice in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: slice.color) ?? .gray)
                                .frame(width: 10, height: 10)
                            Text(slice.name).lineLimit(1)
                            Spacer()
                            Text(share(of: slice), format: .percent.precision(.fractionLength(0)))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            AmountText(slice.amount, currencyCode: currencyCode)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func share(of slice: PlanningBudgetSpendingStats.CategorySpending) -> Double {
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: slice.amount / total).doubleValue
    }

    private var accessibilitySummary: String {
        slices.prefix(5).map { slice in
            "\(slice.name) \(MoneyFormat.string(slice.amount, currencyCode: currencyCode))"
        }
        .joined(separator: ", ")
    }
}

/// Income and expenses per week or month across the budget's period.
private struct BudgetTimelineChart: View {
    let periods: [PlanningBudgetSpendingStats.Period]
    let granularity: PlanningBudgetGranularity
    let currencyCode: String

    private struct Bar: Identifiable {
        let date: Date
        let kind: String
        let amount: Double
        var id: String { "\(date.timeIntervalSince1970)-\(kind)" }
    }

    private var bars: [Bar] {
        periods.flatMap { period -> [Bar] in
            let date = period.periodStart.startDate()
            return [
                Bar(date: date, kind: String(localized: "Expenses"), amount: NSDecimalNumber(decimal: period.expense).doubleValue),
                Bar(date: date, kind: String(localized: "Income"), amount: NSDecimalNumber(decimal: period.income).doubleValue),
            ]
        }
    }

    private var unit: Calendar.Component { granularity == .weekly ? .weekOfYear : .month }

    var body: some View {
        if periods.isEmpty {
            Text("No timeline data")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Chart(bars) { bar in
                BarMark(
                    x: .value("Period", bar.date, unit: unit),
                    y: .value("Amount", bar.amount)
                )
                .foregroundStyle(by: .value("Type", bar.kind))
                .position(by: .value("Type", bar.kind))
            }
            .chartForegroundStyleScale([
                String(localized: "Expenses"): Color.red,
                String(localized: "Income"): Color.green,
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: unit)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: granularity == .weekly
                        ? .dateTime.day().month(.abbreviated)
                        : .dateTime.month(.abbreviated).year(.twoDigits))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(MoneyFormat.string(Decimal(amount), currencyCode: currencyCode, digits: 0))
                        }
                    }
                }
            }
            .frame(height: 220)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Income and expenses over time"))
            .accessibilityValue(Text(accessibilitySummary))
        }
    }

    private var accessibilitySummary: String {
        let expense = periods.reduce(Decimal(0)) { $0 + $1.expense }
        let income = periods.reduce(Decimal(0)) { $0 + $1.income }
        return String(localized: "\(periods.count) periods, expenses \(MoneyFormat.string(expense, currencyCode: currencyCode)), income \(MoneyFormat.string(income, currencyCode: currencyCode))")
    }
}
