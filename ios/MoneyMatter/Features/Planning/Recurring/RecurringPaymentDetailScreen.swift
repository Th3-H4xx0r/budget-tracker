import MoneyMatterKit
import SwiftUI

/// One recurring payment (web: subscription details): basics, schedule, automation, matching
/// rules, the current period's pay and skip actions, payment history, and linked transactions.
struct RecurringPaymentDetailScreen: View {
    let subscriptionID: String
    /// Refreshes the list behind this screen after a change.
    var onChange: () async -> Void = {}

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var state: LoadState<RecurringSubscriptionDetail> = .idle
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
            Section {
                header(detail)
            }
            if let period = detail.currentPeriod, detail.isActive {
                currentPeriodSection(detail, period: period)
            }
            Section("Basics") {
                LabeledContent("Amount") {
                    if let amount = detail.expectedAmount, let currency = detail.expectedCurrencyCode {
                        AmountText(amount, currencyCode: currency, style: detail.transactionType == .income ? .income : .neutral)
                    } else {
                        Text("Varies")
                    }
                }
                LabeledContent("Type") { Text(detail.type.recurringLabel) }
                LabeledContent("Direction") {
                    Text(detail.transactionType == .income ? "Income" : "Expense")
                }
            }
            Section("Schedule") {
                LabeledContent("Frequency") { Text(detail.frequency.recurringLabel) }
                if let start = detail.startDate {
                    LabeledContent("Started", value: start.recurringFormatted)
                }
                if let next = detail.dueDate ?? detail.nextExpectedDate {
                    LabeledContent("Next Payment", value: next.recurringFormatted)
                }
                if let end = detail.endDate {
                    LabeledContent("Ends", value: end.recurringFormatted)
                }
                if let max = detail.maxOccurrences {
                    LabeledContent("Payments") {
                        Text("\(detail.paidPeriodsCount) of \(max) paid")
                    }
                }
                LabeledContent("Reminders") {
                    if detail.remindBefore.isEmpty {
                        Text("Off")
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(detail.remindBefore, id: \.self) { preset in
                                Text(preset.label)
                            }
                        }
                    }
                }
                LabeledContent("Email Reminders") { Text(detail.notifyEmail ? "On" : "Off") }
            }
            Section("Automation") {
                LabeledContent("Mode") { Text(detail.automationMode.label) }
                if detail.automationMode == .record {
                    if let account = detail.account {
                        LabeledContent("Records To", value: account.name)
                    } else {
                        Text("Pick an account to record payments automatically.")
                            .foregroundStyle(.orange)
                    }
                }
                ForEach(Array(detail.matchingRules.rules.enumerated()), id: \.offset) { _, rule in
                    ruleRow(rule)
                }
            }
            Section("Organize") {
                LabeledContent("Account", value: detail.account?.name ?? String(localized: "None"))
                LabeledContent("Category", value: detail.category?.name ?? String(localized: "None"))
                if let notes = detail.notes, !notes.isEmpty {
                    Text(notes)
                        .foregroundStyle(.secondary)
                }
            }
            periodsSection(detail)
            transactionsSection(detail)
        }
    }

    private func header(_ detail: RecurringSubscriptionDetail) -> some View {
        HStack(spacing: 14) {
            RecurringLogoBadge(name: detail.name, initials: detail.logoInitials, colorHex: detail.logoColor ?? detail.category?.color, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.name)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    Label { Text(detail.type.recurringLabel) } icon: { Image(systemName: detail.type.recurringSymbol) }
                    if detail.isCompleted {
                        Text("Completed").foregroundStyle(.green)
                    } else if !detail.isActive {
                        Text("Paused").foregroundStyle(.orange)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let amount = detail.expectedAmount, let currency = detail.expectedCurrencyCode {
                AmountText(amount, currencyCode: currency, style: detail.transactionType == .income ? .income : .neutral)
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }

    private func currentPeriodSection(_ detail: RecurringSubscriptionDetail, period: RecurringPeriod) -> some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let due = period.dueDate {
                        Text(due.recurringFormatted)
                            .font(.headline)
                        RecurringDueText(dueDate: due, today: today)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(period.status.recurringLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(period.status.recurringColor)
            }
            HStack {
                Button {
                    startPay(detail, period: period)
                } label: {
                    Label("Mark Paid", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    Task { await perform { try await $0.send(Endpoints.skipRecurringPeriod(id: detail.id, periodId: period.id)) } }
                } label: {
                    Text("Skip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .buttonBorderShape(.capsule)
        } header: {
            Text("Current Payment")
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: RecurringMatchingRule) -> some View {
        switch rule {
        case .note(let keywords):
            LabeledContent("Note Contains", value: keywords.joined(separator: ", "))
        case .amount(let min, let max, let currencyCode):
            LabeledContent("Amount Between") {
                let code = currencyCode ?? state.value?.expectedCurrencyCode ?? ""
                HStack(spacing: 4) {
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
            Section("Payment History") {
                ForEach(periods) { period in
                    periodRow(detail, period: period)
                }
            }
        }
    }

    private func periodRow(_ detail: RecurringSubscriptionDetail, period: RecurringPeriod) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(period.dueDate?.recurringFormatted ?? "")
                if let paidAt = period.paidAt {
                    Text("Paid \(paidAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let transactionID = period.transactionId {
                NavigationLink {
                    TransactionDetailScreen(transactionID: transactionID)
                } label: {
                    Image(systemName: "doc.text")
                }
                .accessibilityLabel(Text("Open transaction"))
                .fixedSize()
            }
            Text(period.status.recurringLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(period.status.recurringColor)
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

    private func transactionsSection(_ detail: RecurringSubscriptionDetail) -> some View {
        Section {
            let linked = detail.activeTransactions
            if linked.isEmpty {
                ContentUnavailableView {
                    Label("No Linked Transactions", systemImage: "link")
                } description: {
                    Text("Link past payments to build this payment's history.")
                } actions: {
                    Button("Find Matches") { isLinkPickerPresented = true }
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
            }
        } header: {
            HStack {
                Text("Linked Transactions")
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
