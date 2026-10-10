import MoneyMatterKit
import SwiftUI

// MARK: - Reason chips

extension RecurringMatchReason {
    /// The chip text: what evidence tied the transaction to the payment.
    var chipLabel: String? {
        switch code {
        case .payeeMatch: String(localized: "Same payee")
        case .merchantSimilar: String(localized: "Similar merchant")
        case .learnedMerchant: String(localized: "Known merchant")
        case .keywordMatch: String(localized: "Keyword match")
        case .ruleMatch: String(localized: "Matches rule")
        case .nearDueDate, .farFromDueDate:
            switch days {
            case nil: code == .nearDueDate ? String(localized: "Near due date") : String(localized: "Far from due date")
            case 0?: String(localized: "On due date")
            case 1?: String(localized: "1 day from due date")
            case let days?: String(localized: "\(days) days from due date")
            }
        case .amountClose, .amountDiffers:
            if let deviationPct {
                Self.deviationLabel(deviationPct)
            } else {
                code == .amountClose ? String(localized: "Amount matches") : String(localized: "Amount differs")
            }
        case .sameAccount: String(localized: "Same account")
        case .differentAccount: String(localized: "Other account")
        case .sameCategory: String(localized: "Same category")
        case .periodAlreadyCovered, .ambiguousWithOtherSubscription, .unknown: nil
        }
    }

    /// Supporting evidence reads in the accent colour; evidence against reads as a warning.
    var chipColor: Color {
        switch code {
        case .farFromDueDate, .amountDiffers: DS.Palette.warning
        case .differentAccount: .gray
        default: DS.Palette.success
        }
    }

    /// "Same amount" under half a percent, otherwise "+16% vs expected" / "−3% vs expected".
    static func deviationLabel(_ pct: Double) -> String {
        let rounded = Int(pct.rounded())
        if rounded == 0 { return String(localized: "Same amount") }
        let signed = rounded > 0 ? "+\(rounded)%" : "−\(abs(rounded))%"
        return String(localized: "\(signed) vs expected")
    }
}

/// The displayable reasons as wrapping `StatusBadge` chips.
struct RecurringMatchReasonChips: View {
    let reasons: [RecurringMatchReason]

    var body: some View {
        let chips = reasons.filter(\.isDisplayable).compactMap { reason in
            reason.chipLabel.map { (label: $0, color: reason.chipColor) }
        }
        if !chips.isEmpty {
            InsightsNetWorthFlowLayout(spacing: DS.Space.xs) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    StatusBadge(label: chip.label, color: chip.color)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Suggested matches section

/// "Suggested matches" on the recurring payment detail: ranked transactions the matcher
/// thinks are this payment, each with its reasons, a Link button and a Dismiss action.
/// Hidden once there is nothing to suggest.
struct RecurringSuggestedMatchesSection: View {
    let state: LoadState<RecurringSuggestionsResponse>
    let busyIDs: Set<String>
    let onLink: (RecurringSuggestion) async -> Void
    let onDismiss: (RecurringSuggestion) async -> Void
    let onRetry: () async -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            EmptyView()
        case .failed(let error):
            Section("Suggested matches") {
                ErrorRow(ErrorMessage.message(for: error), retry: onRetry)
            }
        case .loaded(let response) where response.suggestions.isEmpty:
            EmptyView()
        case .loaded(let response):
            Section {
                ForEach(response.suggestions) { suggestion in
                    RecurringSuggestionRow(
                        suggestion: suggestion,
                        isBusy: busyIDs.contains(suggestion.id),
                        onLink: { Task { await onLink(suggestion) } },
                        onDismiss: { Task { await onDismiss(suggestion) } }
                    )
                }
            } header: {
                Text("Suggested matches (\(response.suggestions.count))")
            } footer: {
                Text("Linking marks the nearest open period paid. Dismissed transactions won't be suggested again.")
            }
        }
    }
}

private struct RecurringSuggestionRow: View {
    let suggestion: RecurringSuggestion
    let isBusy: Bool
    let onLink: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            NavigationLink {
                TransactionDetailScreen(transactionID: suggestion.transaction.id, initial: suggestion.transaction)
            } label: {
                ResolvedTransactionRow(transaction: suggestion.transaction, showsDate: true)
            }
            HStack(alignment: .top, spacing: DS.Space.s) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    StatusBadge(
                        label: suggestion.confidence == .high
                            ? String(localized: "Strong match")
                            : String(localized: "Possible match"),
                        color: suggestion.confidence == .high ? DS.Palette.success : DS.Palette.info
                    )
                    RecurringMatchReasonChips(reasons: suggestion.reasons)
                }
                Spacer(minLength: DS.Space.s)
                Button("Link", action: onLink)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDismiss) {
                Label("Not This One", systemImage: "xmark.circle")
            }
        }
        .swipeActions(edge: .leading) {
            Button(action: onLink) {
                Label("Link", systemImage: "link")
            }
            .tint(DS.Palette.accent)
        }
        .contextMenu {
            Button("Link", systemImage: "link", action: onLink)
            Button("Not This One", systemImage: "xmark.circle", role: .destructive, action: onDismiss)
        }
    }
}

// MARK: - Search-all link sheet

/// Date presets for the search-all sheet's filter menu.
enum RecurringLinkDateRange: String, CaseIterable, Identifiable {
    case any
    case last30Days
    case last90Days
    case lastYear
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: String(localized: "Any Time")
        case .last30Days: String(localized: "Last 30 Days")
        case .last90Days: String(localized: "Last 90 Days")
        case .lastYear: String(localized: "Last 12 Months")
        case .custom: String(localized: "Custom Range")
        }
    }

    func bounds(today: CalendarDate, customFrom: Date, customTo: Date) -> (from: CalendarDate?, to: CalendarDate?) {
        switch self {
        case .any: (nil, nil)
        case .last30Days: (today.adding(days: -30), today)
        case .last90Days: (today.adding(days: -90), today)
        case .lastYear: (today.adding(days: -365), today)
        case .custom: (CalendarDate(date: min(customFrom, customTo)), CalendarDate(date: max(customFrom, customTo)))
        }
    }
}

/// Searches every transaction of the payment's direction (`linkable-transactions`) by note,
/// payee or amount, filtered by date range and account and paged on scroll. Rows already
/// linked to another payment are badged and can't be picked.
struct RecurringLinkTransactionsSheet: View {
    let subscriptionID: String
    let onLinked: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var items: [RecurringLinkableItem] = []
    @State private var hasMore = false
    @State private var phase: Phase = .idle
    @State private var search = ""
    @State private var dateRange: RecurringLinkDateRange = .any
    @State private var customFrom = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
    @State private var customTo = Date.now
    @State private var accountIDs = Set<String>()
    @State private var sort: RecurringLinkableSort = .date
    @State private var isCustomRangePresented = false
    @State private var selection = Set<String>()
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    private enum Phase: Equatable {
        case idle
        case loading
        case loadingMore
        case failed(String)
    }

    private struct FilterKey: Hashable {
        let search: String
        let dateRange: RecurringLinkDateRange
        let customFrom: Date
        let customTo: Date
        let accountIDs: Set<String>
        let sort: RecurringLinkableSort
    }

    private var filterKey: FilterKey {
        FilterKey(search: search, dateRange: dateRange, customFrom: customFrom, customTo: customTo, accountIDs: accountIDs, sort: sort)
    }

    private var isFiltered: Bool { dateRange != .any || !accountIDs.isEmpty }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Link Transactions")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $search,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Note, payee or amount")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(selection.isEmpty ? String(localized: "Link") : String(localized: "Link (\(selection.count))")) {
                            Task { await link() }
                        }
                        .disabled(selection.isEmpty || isSaving)
                    }
                    ToolbarItem(placement: .bottomBar) { filterMenu }
                }
                .task(id: filterKey) {
                    // Debounces typing; filter changes restart this task and cancel the sleep.
                    if hasLoaded {
                        try? await Task.sleep(for: .milliseconds(300))
                        if Task.isCancelled { return }
                    }
                    await reload()
                }
                .sheet(isPresented: $isCustomRangePresented) { customRangeSheet }
                .errorAlert($alert)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !items.isEmpty || (hasLoaded && phase == .idle) {
            list
        } else if case .failed(let message) = phase {
            List {
                ErrorRow(message) { await reload() }
            }
        } else {
            List { TransactionRowsPlaceholder() }
                .redactedWhileLoading(true)
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(items) { item in
                row(item)
            }
            if hasMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .onAppear { Task { await loadMore() } }
            } else if case .failed(let message) = phase {
                ErrorRow(message) { await loadMore() }
            }
        }
        .environment(\.editMode, .constant(.active))
        .overlay {
            if items.isEmpty, hasLoaded {
                if search.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "magnifyingglass",
                        description: Text("Nothing in this range. Try other filters.")
                    )
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: RecurringLinkableItem) -> some View {
        let linkedElsewhere = item.linkedSubscription.map { $0.id != subscriptionID } ?? false
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ResolvedTransactionRow(transaction: item.transaction, showsDate: true)
            if let other = item.linkedSubscription, linkedElsewhere {
                StatusBadge(label: String(localized: "Linked to \(other.name)"), color: .gray)
            } else if item.isDismissed {
                StatusBadge(label: String(localized: "Dismissed"), color: .gray)
            } else if item.score >= 0.5 {
                RecurringMatchReasonChips(reasons: item.reasons)
            }
        }
        .opacity(linkedElsewhere ? 0.5 : 1)
        .selectionDisabled(linkedElsewhere)
        .tag(item.id)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                Text("Newest First").tag(RecurringLinkableSort.date)
                Text("Best Match").tag(RecurringLinkableSort.relevance)
            }
            Picker("Date", selection: $dateRange) {
                ForEach(RecurringLinkDateRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.menu)
            if dateRange == .custom {
                Button("Edit Custom Range…", systemImage: "calendar") { isCustomRangePresented = true }
            }
            Menu("Accounts") {
                Button("All Accounts") { accountIDs.removeAll() }
                ForEach(referenceData.accounts.filter { $0.status == .active }) { account in
                    Toggle(account.name, isOn: Binding(
                        get: { accountIDs.contains(account.id) },
                        set: { isOn in
                            if isOn { accountIDs.insert(account.id) } else { accountIDs.remove(account.id) }
                        }
                    ))
                }
            }
            if isFiltered {
                Divider()
                Button("Clear Filters", systemImage: "xmark.circle") {
                    dateRange = .any
                    accountIDs.removeAll()
                }
            }
        } label: {
            Label(
                isFiltered ? String(localized: "Filtered") : String(localized: "Filters"),
                systemImage: isFiltered
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
            .labelStyle(.titleAndIcon)
        }
        .onChange(of: dateRange) { _, range in
            if range == .custom { isCustomRangePresented = true }
        }
    }

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $customFrom, in: ...Date.now, displayedComponents: .date)
                DatePicker("To", selection: $customTo, in: ...Date.now, displayedComponents: .date)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isCustomRangePresented = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Data

    private func query(offset: Int) -> RecurringLinkableQuery {
        let bounds = dateRange.bounds(today: CalendarDate(date: .now), customFrom: customFrom, customTo: customTo)
        return RecurringLinkableQuery(
            search: search,
            from: bounds.from,
            to: bounds.to,
            accountIds: accountIDs.sorted(),
            sort: sort,
            offset: offset
        )
    }

    private func reload() async {
        guard let client = services.client else { return }
        phase = .loading
        do {
            let page = try await client.send(Endpoints.recurringLinkableTransactions(id: subscriptionID, query: query(offset: 0)))
            items = page.items
            hasMore = page.hasMore
            hasLoaded = true
            phase = .idle
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            items = []
            hasMore = false
            phase = .failed(ErrorMessage.message(for: apiError))
        }
    }

    private func loadMore() async {
        guard hasMore, phase == .idle, let client = services.client else { return }
        phase = .loadingMore
        do {
            let page = try await client.send(Endpoints.recurringLinkableTransactions(
                id: subscriptionID,
                query: query(offset: items.count)
            ))
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            hasMore = page.hasMore
            phase = .idle
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation {
                phase = .idle
                return
            }
            hasMore = false
            phase = .failed(ErrorMessage.message(for: apiError))
        }
    }

    private func link() async {
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.send(Endpoints.linkRecurringTransactions(id: subscriptionID, transactionIds: Array(selection)))
            await onLinked()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
