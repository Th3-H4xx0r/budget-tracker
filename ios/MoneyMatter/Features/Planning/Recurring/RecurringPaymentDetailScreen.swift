import MoneyMatterKit
import SwiftUI

/// One recurring payment (web: subscription details), Stocks style: a hero with the amount,
/// status and the current period's pay and skip actions, a details grid, then reminders,
/// automation, matching rules, payment history, suggested matches and linked transactions.
struct RecurringPaymentDetailScreen: View {
    let subscriptionID: String
    /// Refreshes the list behind this screen after a change.
    var onChange: () async -> Void = {}

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var state: LoadState<RecurringSubscriptionDetail> = .idle
    @State private var suggestions: LoadState<RecurringSuggestionsResponse> = .idle
    @State private var busySuggestionIDs = Set<String>()
    @State private var isEditing = false
    @State private var payTarget: RecurringPeriod?
    @State private var isLinkPickerPresented = false
    @State private var isDeleteConfirming = false
    @State private var revertTarget: RecurringPeriod?
    @State private var isWorking = false
    @State private var alert: ErrorAlert?

    private var today: CalendarDate { CalendarDate(date: .now) }

    var body: some View {
        content
            .navigationTitle(state.value?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .task { if state.value == nil { await load() } }
            .refreshable { await load() }
            .sheet(isPresented: $isEditing) {
                if let detail = state.value {
                    RecurringPaymentFormSheet(detail: detail) { await changed() }
                }
            }
            .sheet(item: $payTarget) { period in
                if let detail = state.value {
                    RecurringMarkPaidSheet(detail: detail, period: period) { await changed() }
                }
            }
            .sheet(isPresented: $isLinkPickerPresented) {
                RecurringLinkTransactionsSheet(subscriptionID: subscriptionID) { await changed() }
            }
            .confirmationDialog(
                "Delete this recurring payment?",
                isPresented: $isDeleteConfirming,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Linked transactions stay, but the payment history is removed.")
            }
            .confirmationDialog(
                "Reopen this period?",
                isPresented: Binding(get: { revertTarget != nil }, set: { if !$0 { revertTarget = nil } }),
                titleVisibility: .visible,
                presenting: revertTarget
            ) { period in
                Button("Reopen Period", role: .destructive) {
                    Task { await perform { try await $0.send(Endpoints.revertRecurringPeriod(id: subscriptionID, periodId: period.id)) } }
                }
            } message: { period in
                if period.transactionAutoCreated {
                    Text("The transaction created for this payment is deleted.")
                } else {
                    Text("The period goes back to unpaid.")
                }
            }
            .errorAlert($alert)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let detail):
            detailList(detail)
                .disabled(isWorking)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let detail = state.value {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !detail.isCompleted {
                        Button {
                            Task { await perform { try await $0.send(Endpoints.toggleRecurringSubscription(id: detail.id, isActive: !detail.isActive)) } }
                        } label: {
                            if detail.isActive {
                                Label("Pause", systemImage: "pause.circle")
                            } else {
                                Label("Resume", systemImage: "play.circle")
                            }
                        }
                    }
                    Button {
                        isLinkPickerPresented = true
                    } label: {
                        Label("Link Transactions", systemImage: "link")
                    }
                    Button(role: .destructive) {
                        isDeleteConfirming = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
    }

    private func detailList(_ detail: RecurringSubscriptionDetail) -> some View {
        List {
            heroSection(detail)
            if let period = detail.currentPeriod, detail.isActive {
                Section {
                    InlineActionRow(String(localized: "Skip this payment"), systemImage: "forward") {
                        Task { await perform { try await $0.send(Endpoints.skipRecurringPeriod(id: detail.id, periodId: period.id)) } }
                    }
                }
            }
            detailsSection(detail)
            remindersSection(detail)
            automationSection(detail)
            matchingRulesSection(detail)
            Section("Organize") {
                LabeledContent("Account", value: detail.account?.name ?? String(localized: "None"))
                LabeledContent("Category", value: detail.category?.name ?? String(localized: "None"))
                if let notes = detail.notes, !notes.isEmpty {
                    Text(notes)
                        .foregroundStyle(.secondary)
                }
            }
            periodsSection(detail)
            RecurringSuggestedMatchesSection(
                state: suggestions,
                busyIDs: busySuggestionIDs,
                onLink: { await linkSuggestion($0) },
                onDismiss: { await dismissSuggestion($0) },
                onRetry: { await loadSuggestions() }
            )
            transactionsSection(detail)
        }
        .listStyle(.insetGrouped)
        .textCase(nil)
    }

    // MARK: - Hero

    /// Stocks-style hero on the bare canvas: the logo and "Type · Frequency" eyebrow, the
    /// amount at hero size, the status badge and next date, then the primary action. The
    /// name stays in the navigation title only.
    private func heroSection(_ detail: RecurringSubscriptionDetail) -> some View {
        let isIncome = detail.transactionType == .income
        let next = detail.dueDate ?? detail.nextExpectedDate
        let status = heroStatus(detail)
        return Section {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                HStack(spacing: DS.Space.m) {
                    RecurringLogoBadge(
                        name: detail.name,
                        initials: detail.logoInitials,
                        colorHex: detail.logoColor ?? detail.category?.color,
                        size: 56
                    )
                    Text("\(Text(detail.type.recurringLabel)) · \(Text(detail.frequency.recurringLabel))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HeroValueHeader(heroValue(detail), numericValue: detail.expectedAmount.map { NSDecimalNumber(decimal: $0).doubleValue }) {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        if let status {
                            StatusBadge(label: status.label, color: status.color)
                        }
                        if let next {
                            Text("Next payment \(next.recurringFormatted)")
                        }
                    }
                    .padding(.top, DS.Space.xs)
                }
                .foregroundStyle(isIncome ? DS.Palette.up : Color.primary)
            }
            .padding(.vertical, DS.Space.xs)
            .listRowSeparator(.hidden)

            if let period = detail.currentPeriod, detail.isActive {
                Button {
                    startPay(detail, period: period)
                } label: {
                    Label("Mark as paid", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .dsProminentButton()
                .controlSize(.large)
                .listRowInsets(EdgeInsets(top: DS.Space.s, leading: 0, bottom: DS.Space.xs, trailing: 0))
                .listRowSeparator(.hidden)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: DS.Space.s, leading: DS.Space.xs, bottom: DS.Space.s, trailing: DS.Space.xs))
    }

    /// The amount as the hero shows it: unsigned (green when income), or "Varies".
    private func heroValue(_ detail: RecurringSubscriptionDetail) -> String {
        guard let amount = detail.expectedAmount, let currency = detail.expectedCurrencyCode else {
            return String(localized: "Varies")
        }
        let shown = detail.transactionType == .income ? abs(amount) : amount
        return MoneyFormat.string(shown, currencyCode: currency, digits: referenceData.digits(for: currency))
    }

    /// The payment's state in one badge: completed or paused first, then how far the current
    /// period's due date is (orange within a week, red once overdue), else "Paid" when the
    /// latest period is settled.
    private func heroStatus(_ detail: RecurringSubscriptionDetail) -> (label: String, color: Color)? {
        if detail.isCompleted {
            return (String(localized: "Completed"), DS.Palette.success)
        }
        if !detail.isActive {
            return (String(localized: "Paused"), .gray)
        }
        if let period = detail.currentPeriod {
            guard let due = period.dueDate else {
                return (period.status.badgeLabel, period.status.badgeColor)
            }
            let days = RecurringGrouping.days(until: due, today: today)
            return switch days {
            case ..<0: (String(localized: "\(-days) days overdue"), DS.Palette.danger)
            case 0: (String(localized: "Due today"), DS.Palette.warning)
            case 1: (String(localized: "Due tomorrow"), DS.Palette.warning)
            case 2...7: (String(localized: "Due in \(days) days"), DS.Palette.warning)
            default: (String(localized: "Due in \(days) days"), DS.Palette.accent)
            }
        }
        let latest = detail.periods.max { ($0.dueDate ?? today) < ($1.dueDate ?? today) }
        if latest?.status == .paid {
            return (String(localized: "Paid"), DS.Palette.success)
        }
        return nil
    }

    // MARK: - Sections

    private func detailsSection(_ detail: RecurringSubscriptionDetail) -> some View {
        Section("Details") {
            StatGrid {
                StatCell(label: String(localized: "Amount")) {
                    if let amount = detail.expectedAmount, let currency = detail.expectedCurrencyCode {
                        AmountText(
                            amount,
                            currencyCode: currency,
                            digits: referenceData.digits(for: currency),
                            style: detail.transactionType == .income ? .income : .neutral
                        )
                    } else {
                        Text("Varies")
                    }
                }
                StatCell(label: String(localized: "Type")) { Text(detail.type.recurringLabel) }
                StatCell(label: String(localized: "Direction")) {
                    Text(detail.transactionType == .income ? "Income" : "Expense")
                }
                StatCell(label: String(localized: "Frequency")) { Text(detail.frequency.recurringLabel) }
                if let start = detail.startDate {
                    StatCell(label: String(localized: "Started"), value: start.recurringFormatted)
                }
                if let next = detail.dueDate ?? detail.nextExpectedDate {
                    StatCell(label: String(localized: "Next payment"), value: next.recurringFormatted)
                }
                if let end = detail.endDate {
                    StatCell(label: String(localized: "Ends"), value: end.recurringFormatted)
                }
                if let max = detail.maxOccurrences {
                    StatCell(label: String(localized: "Payments")) {
                        Text("\(detail.paidPeriodsCount) of \(max) paid")
                    }
                }
            }
            .padding(.vertical, DS.Space.s)
        }
    }

    private func remindersSection(_ detail: RecurringSubscriptionDetail) -> some View {
        Section("Reminders") {
            LabeledContent("Notifications") {
                if detail.remindBefore.isEmpty {
                    Text("Off")
                } else {
                    VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                        ForEach(detail.remindBefore, id: \.self) { preset in
                            Text(preset.label)
                        }
                    }
                }
            }
            LabeledContent("Email") { Text(detail.notifyEmail ? "On" : "Off") }
        }
    }

    private func automationSection(_ detail: RecurringSubscriptionDetail) -> some View {
        Section("Automation") {
            LabeledContent("Mode") { Text(detail.automationMode.label) }
            if detail.automationMode == .record {
                if let account = detail.account {
                    LabeledContent("Records to", value: account.name)
                } else {
                    Label {
                        Text("Pick an account to record payments automatically.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.warning)
                }
            }
        }
    }

    @ViewBuilder
    private func matchingRulesSection(_ detail: RecurringSubscriptionDetail) -> some View {
        let rules = detail.matchingRules.rules.filter { if case .unknown = $0 { false } else { true } }
        if !rules.isEmpty {
            Section("Matching rules") {
                ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                    ruleRow(rule)
                }
            }
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: RecurringMatchingRule) -> some View {
        switch rule {
        case .note(let keywords):
            LabeledContent("Note contains", value: keywords.joined(separator: ", "))
        case .amount(let min, let max, let currencyCode):
            LabeledContent("Amount between") {
                let code = currencyCode ?? state.value?.expectedCurrencyCode ?? ""
                HStack(spacing: DS.Space.xs) {
                    AmountText(min, currencyCode: code)
                    Text(verbatim: "–")
                    AmountText(max, currencyCode: code)
                }
            }
        case .transactionType(let value):
            LabeledContent("Direction", value: value == "income" ? String(localized: "Income") : String(localized: "Expense"))
        case .accountId(let id):
            LabeledContent("Account", value: referenceData.account(id: id)?.name ?? String(localized: "Unknown account"))
        case .unknown:
            EmptyView()
        }
    }

    @ViewBuilder
    private func periodsSection(_ detail: RecurringSubscriptionDetail) -> some View {
        let periods = detail.periods.sorted { ($0.dueDate ?? today) > ($1.dueDate ?? today) }
        if !periods.isEmpty {
            Section("Payment history") {
                ForEach(periods) { period in
                    periodRow(detail, period: period)
                }
            }
        }
    }

    /// One period: its due date, when it was paid, and its status badge. A period with a
    /// transaction opens it.
    private func periodRow(_ detail: RecurringSubscriptionDetail, period: RecurringPeriod) -> some View {
        Group {
            if let transactionID = period.transactionId {
                NavigationLink {
                    TransactionDetailScreen(transactionID: transactionID)
                } label: {
                    periodEntity(period)
                }
            } else {
                periodEntity(period)
            }
        }
        .swipeActions(edge: .trailing) {
            if period.isOpen {
                Button {
                    startPay(detail, period: period)
                } label: {
                    Label("Mark Paid", systemImage: "checkmark.circle")
                }
                .tint(.green)
                Button {
                    Task { await perform { try await $0.send(Endpoints.skipRecurringPeriod(id: detail.id, periodId: period.id)) } }
                } label: {
                    Label("Skip", systemImage: "forward")
                }
            } else {
                Button {
                    revertTarget = period
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
                .tint(.orange)
                if period.transactionId != nil && !period.transactionAutoCreated {
                    Button {
                        Task { await perform { try await $0.send(Endpoints.unlinkRecurringPeriod(id: detail.id, periodId: period.id)) } }
                    } label: {
                        Label("Unlink", systemImage: "link")
                    }
                }
            }
        }
        .contextMenu {
            if period.isOpen {
                Button("Mark Paid", systemImage: "checkmark.circle") { startPay(detail, period: period) }
                Button("Skip", systemImage: "forward") {
                    Task { await perform { try await $0.send(Endpoints.skipRecurringPeriod(id: detail.id, periodId: period.id)) } }
                }
            } else {
                Button("Reopen", systemImage: "arrow.uturn.backward") { revertTarget = period }
                if period.transactionId != nil && !period.transactionAutoCreated {
                    Button("Unlink Transaction", systemImage: "link") {
                        Task { await perform { try await $0.send(Endpoints.unlinkRecurringPeriod(id: detail.id, periodId: period.id)) } }
                    }
                }
            }
        }
    }

    private func periodEntity(_ period: RecurringPeriod) -> some View {
        EntityRow(
            period.dueDate?.recurringFormatted ?? "",
            subtitle: period.paidAt.map { String(localized: "Paid \($0.formatted(date: .abbreviated, time: .omitted))") }
        ) {
            StatusBadge(label: period.status.badgeLabel, color: period.status.badgeColor)
        }
    }

    private func transactionsSection(_ detail: RecurringSubscriptionDetail) -> some View {
        Section {
            let linked = detail.activeTransactions
            if linked.isEmpty {
                ContentUnavailableView {
                    Label("No Linked Transactions", systemImage: "link")
                } description: {
                    Text("Link past payments to build this payment's history.")
                } actions: {
                    Button("Search Transactions") { isLinkPickerPresented = true }
                }
            } else {
                ForEach(linked) { link in
                    NavigationLink {
                        TransactionDetailScreen(transactionID: link.transaction.id, initial: link.transaction)
                    } label: {
                        ResolvedTransactionRow(transaction: link.transaction, showsDate: true)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await perform { try await $0.send(Endpoints.unlinkRecurringTransactions(id: detail.id, transactionIds: [link.id])) } }
                        } label: {
                            Label("Unlink", systemImage: "link")
                        }
                    }
                }
                InlineActionRow(String(localized: "Search all transactions"), systemImage: "magnifyingglass") {
                    isLinkPickerPresented = true
                }
            }
        } header: {
            HStack {
                Text("Linked transactions")
                Spacer()
                Button {
                    isLinkPickerPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Link Transactions"))
            }
        }
    }

    /// A fixed amount booked in the account's own currency needs no input, so it's recorded
    /// in one tap; otherwise the sheet asks for the amount or the account.
    private func startPay(_ detail: RecurringSubscriptionDetail, period: RecurringPeriod) {
        let isCrossCurrency = detail.account.map { $0.currencyCode != detail.expectedCurrencyCode } ?? false
        if detail.accountId != nil, detail.expectedAmount != nil, !isCrossCurrency {
            Task {
                await perform {
                    try await $0.send(Endpoints.markRecurringPeriodPaid(
                        id: detail.id,
                        periodId: period.id,
                        RecurringMarkPaidRequest(createTransaction: true, time: .now)
                    ))
                }
            }
        } else {
            payTarget = period
        }
    }

    // MARK: - Data

    private func load() async {
        async let detail: Void = loadDetail()
        async let matches: Void = loadSuggestions()
        _ = await (detail, matches)
    }

    private func loadDetail() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await client.send(Endpoints.recurringSubscription(id: subscriptionID)))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(error) }
        }
    }

    private func loadSuggestions() async {
        guard let client = services.client else { return }
        if suggestions.value == nil { suggestions = .loading }
        do {
            suggestions = .loaded(try await client.send(Endpoints.recurringSuggestions(id: subscriptionID)))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if suggestions.value == nil { suggestions = .failed(apiError) }
        }
    }

    private func linkSuggestion(_ suggestion: RecurringSuggestion) async {
        await updateSuggestion(suggestion) {
            try await $0.send(Endpoints.linkRecurringTransactions(id: subscriptionID, transactionIds: [suggestion.id]))
        }
    }

    private func dismissSuggestion(_ suggestion: RecurringSuggestion) async {
        await updateSuggestion(suggestion) {
            try await $0.send(Endpoints.dismissRecurringSuggestions(id: subscriptionID, transactionIds: [suggestion.id]))
        }
    }

    /// Runs a link or dismiss for one suggestion, then reloads the payment and its suggestions
    /// so the linked list, periods and the remaining ranking stay in step.
    private func updateSuggestion<Value>(
        _ suggestion: RecurringSuggestion,
        _ action: (APIClient) async throws -> Value
    ) async {
        guard let client = services.client else { return }
        busySuggestionIDs.insert(suggestion.id)
        defer { busySuggestionIDs.remove(suggestion.id) }
        do {
            _ = try await action(client)
            await changed()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func changed() async {
        await load()
        await onChange()
    }

    private func perform<Value>(_ action: (APIClient) async throws -> Value) async {
        guard let client = services.client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await action(client)
            await changed()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func delete() async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.deleteRecurringSubscription(id: subscriptionID))
            await onChange()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

private extension SubscriptionPeriodStatus {
    /// The status as `StatusBadge` text.
    var badgeLabel: String {
        switch self {
        case .upcoming: String(localized: "Upcoming")
        case .paid: String(localized: "Paid")
        case .overdue: String(localized: "Overdue")
        case .skipped: String(localized: "Skipped")
        case .unknown: String(localized: "Unknown")
        }
    }

    var badgeColor: Color {
        switch self {
        case .paid: DS.Palette.success
        case .overdue: DS.Palette.danger
        case .skipped: .gray
        case .upcoming, .unknown: DS.Palette.warning
        }
    }
}
