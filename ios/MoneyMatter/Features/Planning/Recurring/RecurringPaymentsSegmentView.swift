import MoneyMatterKit
import SwiftUI

/// Recurring payments (web: Planned → Subscriptions): summary, sort, type and period filters,
/// due-date groups, pause/resume and delete, quick-add, and candidate discovery.
struct RecurringPaymentsSegmentView: View {
    @Environment(AppServices.self) private var services
    @AppStorage("planning.recurring.sort") private var sortRaw = RecurringSortKey.dueDate.rawValue

    @State private var items: LoadState<[SubscriptionListItem]> = .idle
    /// `pendingSuggestionsCount` by subscription id.
    @State private var pendingSuggestions: [String: Int] = [:]
    @State private var summary: LoadState<SubscriptionsSummary> = .idle
    @State private var typeFilter: SubscriptionType?
    @State private var periodFilter: RecurringPeriodFilter = .all
    @State private var lookbackMonths = 6
    @State private var isQuickAddPresented = false
    @State private var deleteTarget: SubscriptionListItem?
    @State private var alert: ErrorAlert?

    private var sortBy: RecurringSortKey { RecurringSortKey(rawValue: sortRaw) ?? .dueDate }
    private var today: CalendarDate { CalendarDate(date: .now) }

    var body: some View {
        content
            .toolbar { toolbar }
            .task { if items.value == nil { await load() } }
            .refreshable { await load() }
            .onChange(of: sortRaw) { Task { await loadList() } }
            .onChange(of: lookbackMonths) { Task { await loadSummary() } }
            .sheet(isPresented: $isQuickAddPresented) {
                RecurringQuickAddSheet(prefill: nil) { _ in await load() }
            }
            .confirmationDialog(
                "Delete this recurring payment?",
                isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                titleVisibility: .visible,
                presenting: deleteTarget
            ) { item in
                Button("Delete \(item.name)", role: .destructive) {
                    Task { await delete(item) }
                }
            } message: { _ in
                Text("Linked transactions stay, but the payment history is removed.")
            }
            .errorAlert($alert)
    }

    @ViewBuilder
    private var content: some View {
        switch items {
        case .idle, .loading:
            RecurringLoadingList()
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let all) where all.isEmpty:
            ContentUnavailableView {
                Label("No Recurring Payments", systemImage: "repeat")
            } description: {
                Text("Track subscriptions, bills, and installments to see what's due and what they cost.")
            } actions: {
                Button("Add Recurring Payment") { isQuickAddPresented = true }
                    .buttonStyle(.borderedProminent)
                NavigationLink("Discover from Transactions") {
                    RecurringCandidatesScreen { await load() }
                }
            }
        default:
            list(items.value ?? [])
        }
    }

    private func list(_ all: [SubscriptionListItem]) -> some View {
        let filtered = filteredItems(all)
        let groups = RecurringGrouping.group(filtered, sortBy: sortBy, today: today)
        return List {
            Section {
                summarySection
            }
            if filtered.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Nothing Matches", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No recurring payments match these filters.")
                    } actions: {
                        Button("Clear Filters") {
                            typeFilter = nil
                            periodFilter = .all
                        }
                    }
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { item in
                        row(item)
                    }
                } header: {
                    Text("\(Text(group.key.label)) (\(group.items.count))")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ item: SubscriptionListItem) -> some View {
        NavigationLink {
            RecurringPaymentDetailScreen(subscriptionID: item.id) { await load() }
        } label: {
            RecurringListRow(item: item, today: today, pendingSuggestions: pendingSuggestions[item.id] ?? 0)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteTarget = item
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                Task { await toggle(item) }
            } label: {
                if item.isActive {
                    Label("Pause", systemImage: "pause.circle")
                } else {
                    Label("Resume", systemImage: "play.circle")
                }
            }
            .tint(item.isActive ? .orange : .green)
        }
        .contextMenu {
            Button {
                Task { await toggle(item) }
            } label: {
                if item.isActive {
                    Label("Pause", systemImage: "pause.circle")
                } else {
                    Label("Resume", systemImage: "play.circle")
                }
            }
            Button(role: .destructive) {
                deleteTarget = item
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        switch summary {
        case .failed(let error):
            if case .validation(let message, _, let code) = error, code == "CURRENCY_NOT_CONNECTED" {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                .font(.subheadline)
            } else {
                InlineRetryView(ErrorMessage.inline(for: error)) { await loadSummary() }
            }
        default:
            RecurringSummaryCard(summary: summary.value, lookbackMonths: $lookbackMonths)
                .redactedWhileLoading(summary.value == nil)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Picker("Sort By", selection: $sortRaw) {
                    ForEach(RecurringSortKey.allCases, id: \.self) { key in
                        Text(key.label).tag(key.rawValue)
                    }
                }
                Picker("Type", selection: $typeFilter) {
                    Text("All Types").tag(SubscriptionType?.none)
                    ForEach(SubscriptionType.recurringSelectable, id: \.self) { type in
                        Text(type.recurringLabel).tag(SubscriptionType?.some(type))
                    }
                }
                Picker("Due", selection: $periodFilter) {
                    ForEach(RecurringPeriodFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
            } label: {
                Label("Sort and Filter", systemImage: isFiltering
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
            }
            NavigationLink {
                RecurringCandidatesScreen { await load() }
            } label: {
                Label("Discover", systemImage: "sparkle.magnifyingglass")
            }
            Button {
                isQuickAddPresented = true
            } label: {
                Label("Add Recurring Payment", systemImage: "plus")
            }
        }
    }

    private var isFiltering: Bool { typeFilter != nil || periodFilter != .all }

    private func filteredItems(_ all: [SubscriptionListItem]) -> [SubscriptionListItem] {
        all.filter { item in
            if let typeFilter, item.type != typeFilter { return false }
            guard let lastDay = periodFilter.lastDay(from: today) else { return true }
            guard let due = item.nextDueDate else { return false }
            return due >= today && due <= lastDay
        }
    }

    // MARK: - Data

    private func load() async {
        async let list: Void = loadList()
        async let totals: Void = loadSummary()
        _ = await (list, totals)
    }

    private func loadList() async {
        guard let client = services.client else { return }
        if items.value == nil { items = .loading }
        do {
            let entries = try await client.send(Endpoints.recurringSubscriptionEntries(sortBy: sortBy))
            pendingSuggestions = Dictionary(entries.map { ($0.id, $0.pendingSuggestionsCount) }, uniquingKeysWith: { first, _ in first })
            items = .loaded(entries.map(\.item))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if items.value == nil { items = .failed(apiError) } else { alert = ErrorAlert(error) }
        }
    }

    private func loadSummary() async {
        guard let client = services.client else { return }
        if summary.value == nil { summary = .loading }
        do {
            summary = .loaded(try await client.send(Endpoints.recurringSummary(lookbackMonths: lookbackMonths)))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            summary = .failed(apiError)
        }
    }

    private func toggle(_ item: SubscriptionListItem) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.toggleRecurringSubscription(id: item.id, isActive: !item.isActive))
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func delete(_ item: SubscriptionListItem) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.deleteRecurringSubscription(id: item.id))
            if case .loaded(let all) = items {
                items = .loaded(all.filter { $0.id != item.id })
            }
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// The web's period selector, reduced to its presets: how far ahead the next due date may be.
enum RecurringPeriodFilter: String, CaseIterable, Identifiable, Hashable {
    case next7Days
    case next30Days
    case next3Months
    case next6Months
    case nextYear
    case all

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .next7Days: "Next 7 Days"
        case .next30Days: "Next 30 Days"
        case .next3Months: "Next 3 Months"
        case .next6Months: "Next 6 Months"
        case .nextYear: "Next Year"
        case .all: "Any Time"
        }
    }

    func lastDay(from today: CalendarDate, calendar: Calendar = .current) -> CalendarDate? {
        let start = today.startDate(in: calendar)
        let end: Date? = switch self {
        case .next7Days: calendar.date(byAdding: .day, value: 7, to: start)
        case .next30Days: calendar.date(byAdding: .day, value: 30, to: start)
        case .next3Months: calendar.date(byAdding: .month, value: 3, to: start)
        case .next6Months: calendar.date(byAdding: .month, value: 6, to: start)
        case .nextYear: calendar.date(byAdding: .year, value: 1, to: start)
        case .all: nil
        }
        return end.map { CalendarDate(date: $0, calendar: calendar) }
    }
}

/// Estimated monthly and projected yearly cost, plus expected income, in the base currency.
private struct RecurringSummaryCard: View {
    let summary: SubscriptionsSummary?
    @Binding var lookbackMonths: Int

    var body: some View {
        let currency = summary?.currencyCode ?? "USD"
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AmountText(summary?.estimatedMonthlyCost ?? 0, currencyCode: currency)
                        .font(.title2.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Yearly")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AmountText(summary?.projectedYearlyCost ?? 0, currencyCode: currency)
                        .font(.headline)
                }
            }
            HStack {
                let active = (summary?.activeCount.expense ?? 0) + (summary?.activeCount.income ?? 0)
                Text("\(active) active")
                    .foregroundStyle(.secondary)
                Spacer()
                if let income = summary?.expectedMonthlyIncome, income > 0 {
                    HStack(spacing: 4) {
                        Text("Income")
                            .foregroundStyle(.secondary)
                        AmountText(income, currencyCode: currency, style: .income)
                    }
                }
                if let percent = summary?.percentOfIncome {
                    Menu {
                        Picker("Average Income Over", selection: $lookbackMonths) {
                            ForEach([1, 3, 6, 12], id: \.self) { months in
                                Text("Last \(months) months").tag(months)
                            }
                        }
                    } label: {
                        Text("\(NSDecimalNumber(decimal: percent).doubleValue / 100, format: .percent.precision(.fractionLength(0))) of income")
                    }
                    .accessibilityHint(Text("Changes how many months of income are averaged"))
                }
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct RecurringListRow: View {
    let item: SubscriptionListItem
    let today: CalendarDate
    /// Transactions the matcher thinks are this payment, awaiting a link or dismiss.
    var pendingSuggestions = 0

    var body: some View {
        HStack(spacing: 12) {
            RecurringLogoBadge(name: item.name, initials: item.logoInitials, colorHex: item.logoColor ?? item.category?.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                // One Text so the line wraps as a whole instead of squeezing the frequency
                // into a narrow column next to the due label.
                Group {
                    if let due = item.nextDueDate, item.isActive {
                        Text("\(Text(item.frequency.recurringLabel)) · \(RecurringDueText.text(dueDate: due, today: today))")
                    } else if !item.isActive {
                        Text("\(Text(item.frequency.recurringLabel)) · \(Text("Paused"))")
                    } else {
                        Text(item.frequency.recurringLabel)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                if pendingSuggestions > 0 {
                    StatusBadge(
                        label: String(localized: "\(pendingSuggestions) suggested"),
                        color: DS.Palette.info
                    )
                    .accessibilityLabel(Text("\(pendingSuggestions) suggested matches to review"))
                }
                if let max = item.maxOccurrences {
                    ProgressView(value: Double(min(item.paidPeriodsCount ?? 0, max)), total: Double(max)) {
                        Text("\(item.paidPeriodsCount ?? 0) of \(max) paid")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tint(.accentColor)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let amount = item.expectedAmount, let currency = item.expectedCurrencyCode {
                    AmountText(amount, currencyCode: currency, style: item.transactionType == .income ? .income : .neutral)
                        .font(.body.weight(.semibold))
                } else {
                    Text("Varies")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(item.type.recurringLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(item.isActive ? 1 : 0.6)
    }
}

private struct RecurringLoadingList: View {
    var body: some View {
        List {
            Section {
                RecurringSummaryCard(summary: nil, lookbackMonths: .constant(6))
            }
            Section {
                ForEach(0..<5, id: \.self) { _ in
                    HStack(spacing: 12) {
                        Circle().frame(width: 36, height: 36)
                        VStack(alignment: .leading) {
                            Text(verbatim: "Subscription name")
                            Text(verbatim: "Monthly · Due in 3 days").font(.caption)
                        }
                        Spacer()
                        Text(verbatim: "$12.99")
                    }
                }
            } header: {
                Text(verbatim: "Due soon")
            }
        }
        .listStyle(.insetGrouped)
        .redactedWhileLoading(true)
    }
}
