import Charts
import MoneyMatterKit
import SwiftUI

/// Where a plan sits relative to today, for the status badge: the web's "Ends in N days".
enum PlannedPlanTimeline: Equatable {
    case upcoming(daysUntilStart: Int)
    case active(daysLeft: Int)
    case ended

    init(start: CalendarDate, end: CalendarDate, today: CalendarDate = CalendarDate(date: .now), calendar: Calendar = .current) {
        func days(from: CalendarDate, to: CalendarDate) -> Int {
            calendar.dateComponents([.day], from: from.startDate(in: calendar), to: to.startDate(in: calendar)).day ?? 0
        }
        if today > end {
            self = .ended
        } else if today < start {
            self = .upcoming(daysUntilStart: days(from: today, to: start))
        } else {
            self = .active(daysLeft: days(from: today, to: end))
        }
    }

    var text: Text {
        switch self {
        case .ended: Text("Ended")
        case .upcoming(let days) where days <= 1: days == 0 ? Text("Starts today") : Text("Starts tomorrow")
        case .upcoming(let days): Text("Starts in \(days) days")
        case .active(let days) where days == 0: Text("Last day")
        case .active(let days): Text("\(days) days left")
        }
    }

    var tint: Color {
        switch self {
        case .ended: .secondary
        case .upcoming: .blue
        case .active: .green
        }
    }
}

/// A capsule showing the plan's timeline status.
struct PlannedPlanTimelineBadge: View {
    let timeline: PlannedPlanTimeline

    var body: some View {
        timeline.text
            .font(.caption.weight(.medium))
            .foregroundStyle(timeline.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(timeline.tint.opacity(0.15), in: .capsule)
    }
}

extension PlannedBudgetPlan {
    var plannedDateRange: String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return "\(startDate.plannedDate.formatted(style)) – \(endDate.plannedDate.formatted(style))"
    }
}

private enum PlannedOccurrenceSort: String, CaseIterable, Identifiable {
    case date, name, source, amount

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .date: "Date"
        case .name: "Name"
        case .source: "Source"
        case .amount: "Amount"
        }
    }
}

private enum PlannedEntrySheetTarget: Identifiable {
    case new
    case edit(PlannedBudgetEntry)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let entry): entry.id
        }
    }

    var entry: PlannedBudgetEntry? {
        if case .edit(let entry) = self { return entry }
        return nil
    }
}

private struct PlannedOccurrenceItem: Identifiable {
    let timeline: PlannedBudgetTimelineOccurrence

    var occurrence: PlannedBudgetOccurrence { timeline.occurrence }
    /// A real transaction standing in for its recurring payment's projected occurrence.
    var isRecurringActual: Bool { timeline.isRecurringActual }
    var id: String { timeline.timelineKey }
}

private struct PlannedCategorySpend: Identifiable {
    let label: String
    let amount: Decimal
    let color: Color

    var id: String { label }
    var value: Double { NSDecimalNumber(decimal: amount).doubleValue }
}

/// `GET /future-budgets/:id`: projected income, expenses, and net; spending by category; the
/// projected timeline from salary, bank-derived recurring payments, and plan-only entries.
struct PlannedBudgetDetailScreen: View {
    let planID: String
    var onChange: () -> Void = {}

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState<PlannedBudgetDetailsWithActuals> = .idle
    @State private var sort: PlannedOccurrenceSort = .date
    @State private var isAscending = true
    @State private var entrySheet: PlannedEntrySheetTarget?
    @State private var adjusting: PlannedOccurrenceItem?
    @State private var isRenaming = false
    @State private var nameDraft = ""
    @State private var isConfirmingDelete = false
    @State private var isAskingSalary = false
    @State private var hasHandledSalaryChange = false
    @State private var isMutating = false
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle(state.value?.plan.name ?? String(localized: "Planned Budget"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let plan = state.value?.plan {
                    ToolbarItem(placement: .primaryAction) { actionsMenu(plan) }
                }
            }
            .task {
                if state.value == nil { await load() }
            }
            .refreshable { await load() }
            .sheet(item: $entrySheet) { target in
                PlannedBudgetEntrySheet(
                    planID: planID,
                    entry: target.entry,
                    defaultDate: defaultEntryDate,
                    currencyCode: currencyCode
                ) {
                    Task { await load() }
                }
            }
            .sheet(item: $adjusting) { item in
                PlannedRecurringAdjustSheet(planID: planID, occurrence: item.occurrence, currencyCode: currencyCode) {
                    Task { await load() }
                }
            }
            .alert("Edit Plan", isPresented: $isRenaming) {
                TextField("Plan Name", text: $nameDraft)
                Button("Cancel", role: .cancel) {}
                Button("Save") { Task { await rename() } }
            }
            .confirmationDialog("Delete plan?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Plan", role: .destructive) { Task { await deletePlan() } }
            } message: {
                Text("This will permanently delete this planned budget and its entries.")
            }
            .alert("Salary Profile Changed", isPresented: $isAskingSalary) {
                Button("Apply New Salary") { Task { await resolveSalary(apply: true) } }
                Button("Keep Current", role: .cancel) { Task { await resolveSalary(apply: false) } }
            } message: {
                Text("Your salary profile has changed. Apply the new salary to this plan?")
            }
            .errorAlert($alert)
    }

    private var currencyCode: String {
        session.baseCurrency?.currencyCode ?? "USD"
    }

    private var defaultEntryDate: CalendarDate {
        let today = CalendarDate(date: .now)
        guard let plan = state.value?.plan else { return today }
        return min(max(today, plan.startDate), plan.endDate)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            List {
                Section {
                    Text("Placeholder date range")
                    Text("Placeholder plan type")
                }
                Section {
                    ForEach(0..<5, id: \.self) { _ in
                        HStack {
                            Text("Placeholder projection")
                            Spacer()
                            Text("$000.00")
                        }
                    }
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let details):
            loadedList(details)
        }
    }

    private func loadedList(_ details: PlannedBudgetDetailsWithActuals) -> some View {
        List {
            Section {
                overview(details.plan)
                summaryTiles(details.summary)
            }

            Section {
                spendingChart(details.occurrences.map(\.occurrence))
            } header: {
                Text("Spending by Category")
            } footer: {
                Text("Projected expenses across this plan's date range.")
            }

            Section {
                Toggle("Auto-Add Synced Transactions", isOn: autoAddBinding(details.plan))
                    .disabled(isMutating)
            } footer: {
                Text("Automatically add real transactions to this plan when they sync and fall within \(details.plan.plannedDateRange).")
            }

            timelineSection(details)
        }
    }

    // MARK: Sections

    private func overview(_ plan: PlannedBudgetPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(plan.plannedDateRange, systemImage: "calendar")
                .font(.subheadline)
            HStack(spacing: 8) {
                PlannedPlanTimelineBadge(timeline: PlannedPlanTimeline(start: plan.startDate, end: plan.endDate))
                Text(plan.type == .category ? "Category Plan" : "Manual Plan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if plan.isArchived {
                    Label("Archived", systemImage: "archivebox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func summaryTiles(_ summary: PlannedBudgetDetails.Summary) -> some View {
        Grid(horizontalSpacing: 12) {
            GridRow {
                summaryTile("Income", amount: summary.income, style: .income)
                summaryTile("Expenses", amount: summary.expense, style: .neutral)
                summaryTile("Net", amount: summary.net, style: .neutral)
            }
        }
        .padding(.vertical, 4)
    }

    private func summaryTile(_ title: LocalizedStringKey, amount: Decimal, style: AmountStyle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            AmountText(amount, currencyCode: currencyCode, digits: referenceData.digits(for: currencyCode), style: style)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func spendingChart(_ occurrences: [PlannedBudgetOccurrence]) -> some View {
        let rows = categorySpend(occurrences)
        if rows.isEmpty {
            Text("No projected expenses yet.")
                .foregroundStyle(.secondary)
        } else {
            Chart(rows) { row in
                BarMark(
                    x: .value("Amount", row.value),
                    y: .value("Category", row.label)
                )
                .foregroundStyle(row.color)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(MoneyFormat.compactString(row.amount, currencyCode: currencyCode))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartXScale(range: .plotDimension(endPadding: 48))
            .frame(height: max(80, CGFloat(rows.count) * 34))
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Spending by category"))
            .accessibilityValue(Text(rows.map {
                "\($0.label): \(MoneyFormat.string($0.amount, currencyCode: currencyCode))"
            }.formatted(.list(type: .and))))
        }
    }

    private func timelineSection(_ details: PlannedBudgetDetailsWithActuals) -> some View {
        Section {
            Button {
                entrySheet = .new
            } label: {
                Label("Add Plan-Only Entry", systemImage: "plus")
            }
            let items = sortedItems(details.occurrences)
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No Projections", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Add a plan-only entry, set a salary, or link recurring payments to see projections.")
                }
            } else {
                ForEach(items) { item in
                    occurrenceRow(item, details: details)
                }
            }
        } header: {
            HStack {
                Text("Projected Timeline")
                Spacer()
                sortMenu
            }
        } footer: {
            Text("Salary and active bank-derived recurring payments update automatically; a paid recurring payment shows its real transaction in place of the projection. Manual entries are isolated to this plan.")
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(PlannedOccurrenceSort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Picker("Order", selection: $isAscending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel(Text("Sort projections"))
    }

    @ViewBuilder
    private func occurrenceRow(_ item: PlannedOccurrenceItem, details: PlannedBudgetDetailsWithActuals) -> some View {
        if item.isRecurringActual, let transactionID = item.timeline.transactionId {
            NavigationLink {
                TransactionDetailScreen(transactionID: transactionID)
            } label: {
                occurrenceContent(item, details: details)
            }
        } else {
            occurrenceContent(item, details: details)
        }
    }

    private func occurrenceContent(_ item: PlannedOccurrenceItem, details: PlannedBudgetDetailsWithActuals) -> some View {
        let occurrence = item.occurrence
        let entry = occurrence.source == .manual ? details.entry(id: occurrence.id) : nil
        let isRecurring = occurrence.source == .recurring && occurrence.subscriptionId != nil
        return HStack(spacing: 12) {
            Image(systemName: item.isRecurringActual ? "checkmark.circle" : sourceSymbol(occurrence.source))
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Space.s) {
                    Text(displayName(occurrence))
                        .lineLimit(1)
                    if item.isRecurringActual {
                        StatusBadge(label: String(localized: "Paid"), color: DS.Palette.success)
                    }
                }
                HStack(spacing: 4) {
                    Text(occurrence.date.plannedDate, format: .dateTime.month(.abbreviated).day().year())
                    Text(verbatim: "·")
                    Text(item.isRecurringActual ? String(localized: "Recurring Payment") : sourceLabel(occurrence.source))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let category = referenceData.category(id: occurrence.categoryId) {
                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            AmountText(
                occurrence.amount,
                currencyCode: currencyCode,
                digits: referenceData.digits(for: currencyCode),
                style: occurrence.transactionType == .income ? .income : .expense,
                showsPlusSign: occurrence.transactionType == .income
            )
        }
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            if let entry {
                Button(role: .destructive) {
                    Task { await deleteEntry(entry.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    entrySheet = .edit(entry)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            } else if isRecurring {
                Button {
                    Task { await exclude(occurrence) }
                } label: {
                    Label("Exclude", systemImage: "minus.circle")
                }
                .tint(.orange)
                Button {
                    adjusting = item
                } label: {
                    Label("Adjust", systemImage: "slider.horizontal.3")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if let entry {
                Button {
                    entrySheet = .edit(entry)
                } label: {
                    Label("Edit Entry", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    Task { await deleteEntry(entry.id) }
                } label: {
                    Label("Delete Entry", systemImage: "trash")
                }
            } else if isRecurring {
                Button {
                    adjusting = item
                } label: {
                    Label("Adjust Projection", systemImage: "slider.horizontal.3")
                }
                Button {
                    Task { await exclude(occurrence) }
                } label: {
                    Label("Exclude From This Plan", systemImage: "minus.circle")
                }
            }
        }
    }

    private func actionsMenu(_ plan: PlannedBudgetPlan) -> some View {
        Menu {
            Button {
                nameDraft = plan.name
                isRenaming = true
            } label: {
                Label("Edit Name", systemImage: "pencil")
            }
            Button {
                Task { await update(PlannedBudgetUpdateRequest(status: plan.isArchived ? .active : .archived)) }
            } label: {
                if plan.isArchived {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                } else {
                    Label("Archive", systemImage: "archivebox")
                }
            }
            Divider()
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete Plan", systemImage: "trash")
            }
        } label: {
            Label("Plan Actions", systemImage: "ellipsis")
        }
        .disabled(isMutating)
    }

    // MARK: Derived data

    private func autoAddBinding(_ plan: PlannedBudgetPlan) -> Binding<Bool> {
        Binding(
            get: { plan.autoAddSyncedTransactions },
            set: { isOn in Task { await update(PlannedBudgetUpdateRequest(autoAddSyncedTransactions: isOn)) } }
        )
    }

    private func displayName(_ occurrence: PlannedBudgetOccurrence) -> String {
        if let name = occurrence.name, !name.isEmpty { return name }
        if let note = occurrence.note, !note.isEmpty { return note }
        return occurrence.source == .salary ? String(localized: "Salary") : String(localized: "Future Transaction")
    }

    private func sourceLabel(_ source: PlannedBudgetSource) -> String {
        switch source {
        case .recurring: String(localized: "Bank Recurring")
        case .salary: String(localized: "Salary")
        case .manual, .unknown: String(localized: "Plan Only")
        }
    }

    private func timelineSourceLabel(_ item: PlannedBudgetTimelineOccurrence) -> String {
        item.isRecurringActual ? String(localized: "Recurring Payment") : sourceLabel(item.occurrence.source)
    }

    private func sourceSymbol(_ source: PlannedBudgetSource) -> String {
        switch source {
        case .recurring: "arrow.triangle.2.circlepath"
        case .salary: "banknote"
        case .manual, .unknown: "square.and.pencil"
        }
    }

    private func sortedItems(_ timeline: [PlannedBudgetTimelineOccurrence]) -> [PlannedOccurrenceItem] {
        let sorted = timeline.sorted { lhsItem, rhsItem in
            let lhs = lhsItem.occurrence
            let rhs = rhsItem.occurrence
            switch sort {
            case .date:
                return isAscending ? lhs.date < rhs.date : rhs.date < lhs.date
            case .name:
                let order = displayName(lhs).localizedStandardCompare(displayName(rhs))
                return isAscending ? order == .orderedAscending : order == .orderedDescending
            case .source:
                let order = timelineSourceLabel(lhsItem).localizedStandardCompare(timelineSourceLabel(rhsItem))
                return isAscending ? order == .orderedAscending : order == .orderedDescending
            case .amount:
                return isAscending ? lhs.signedAmount < rhs.signedAmount : rhs.signedAmount < lhs.signedAmount
            }
        }
        var seen = Set<String>()
        return sorted.map(PlannedOccurrenceItem.init).filter { seen.insert($0.id).inserted }
    }

    private func categorySpend(_ occurrences: [PlannedBudgetOccurrence]) -> [PlannedCategorySpend] {
        var totals: [String: (amount: Decimal, color: Color)] = [:]
        for occurrence in occurrences where occurrence.transactionType == .expense {
            let category = referenceData.category(id: occurrence.categoryId)
            let label = category?.name ?? String(localized: "Uncategorized")
            let color = Color(hex: category?.color) ?? .gray
            totals[label, default: (0, color)].amount += occurrence.amount
        }
        return totals
            .map { PlannedCategorySpend(label: $0.key, amount: $0.value.amount, color: $0.value.color) }
            .sorted { $0.amount > $1.amount }
            .prefix(8)
            .map { $0 }
    }

    // MARK: Actions

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            let details = try await client.send(Endpoints.plannedBudgetDetailsWithActuals(id: planID))
            state = .loaded(details)
            if details.salaryProfileChanged, !hasHandledSalaryChange {
                hasHandledSalaryChange = true
                isAskingSalary = true
            }
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if state.value == nil {
                state = .failed(apiError)
            } else {
                alert = ErrorAlert(error)
            }
        }
    }

    private func update(_ request: PlannedBudgetUpdateRequest) async {
        guard let client = services.client else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            _ = try await client.send(Endpoints.updatePlannedBudget(id: planID, request))
            onChange()
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func rename() async {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != state.value?.plan.name else { return }
        await update(PlannedBudgetUpdateRequest(name: name))
    }

    private func deletePlan() async {
        guard let client = services.client else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            _ = try await client.send(Endpoints.deletePlannedBudget(id: planID))
            onChange()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func deleteEntry(_ entryID: String) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.deletePlannedBudgetEntry(planId: planID, entryId: entryID))
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func exclude(_ occurrence: PlannedBudgetOccurrence) async {
        guard let client = services.client, let subscriptionID = occurrence.subscriptionId else { return }
        do {
            _ = try await client.send(Endpoints.updatePlannedBudgetRecurring(
                planId: planID,
                subscriptionId: subscriptionID,
                PlannedBudgetRecurringOverrideRequest(isIncluded: false)
            ))
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func resolveSalary(apply: Bool) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.resolvePlannedBudgetSalaryChange(id: planID, apply: apply))
            if apply {
                onChange()
                await load()
            }
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
