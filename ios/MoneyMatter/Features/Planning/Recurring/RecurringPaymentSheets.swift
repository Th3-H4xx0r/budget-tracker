import MoneyMatterKit
import SwiftUI

/// Marks a period paid. With an account it books the transaction (amount pre-filled, converted
/// for a cross-currency subscription). Without one, the user either just marks the period
/// paid or picks an account to book against, which is then linked to the subscription.
struct RecurringMarkPaidSheet: View {
    let detail: RecurringSubscriptionDetail
    let period: RecurringPeriod
    let onPaid: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var recordsTransaction: Bool
    @State private var accountId: String?
    @State private var amount: Decimal?
    @State private var paidDate = Date.now
    @State private var notes = ""
    @State private var preview: RecurringPayPreview?
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    init(detail: RecurringSubscriptionDetail, period: RecurringPeriod, onPaid: @escaping () async -> Void) {
        self.detail = detail
        self.period = period
        self.onPaid = onPaid
        _recordsTransaction = State(initialValue: detail.accountId != nil)
        _amount = State(initialValue: detail.expectedAmount)
    }

    private var hasAccount: Bool { detail.accountId != nil }

    private var bookingCurrency: String? {
        if let account = detail.account { return account.currencyCode }
        return referenceData.account(id: accountId)?.currencyCode
    }

    private var isConfirmDisabled: Bool {
        guard recordsTransaction else { return isSaving }
        return isSaving || (amount ?? 0) <= 0 || (!hasAccount && accountId == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let due = period.dueDate {
                    Section {
                        LabeledContent("Due", value: due.recurringFormatted)
                    }
                }
                if !hasAccount {
                    Section {
                        Picker("Record", selection: $recordsTransaction) {
                            Text("Mark Paid Only").tag(false)
                            Text("Record a Transaction").tag(true)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } footer: {
                        Text(recordsTransaction
                            ? "Books the payment on the account you pick and links the account for future payments."
                            : "Updates the schedule without creating a transaction.")
                    }
                }
                if recordsTransaction {
                    Section {
                        if hasAccount {
                            LabeledContent("Account", value: detail.account?.name ?? "")
                        } else {
                            Picker("Account", selection: $accountId) {
                                Text("Choose").tag(String?.none)
                                ForEach(referenceData.accounts.filter { $0.status == .active }) { account in
                                    Text(account.name).tag(String?.some(account.id))
                                }
                            }
                        }
                        HStack {
                            TextField("Amount", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                                .monospacedDigit()
                            if let bookingCurrency {
                                Text(verbatim: bookingCurrency)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        DatePicker("Paid On", selection: $paidDate, in: ...Date.now, displayedComponents: .date)
                    } footer: {
                        if let preview, preview.isCrossCurrency, let expected = preview.expectedAmount,
                           let code = preview.subscriptionCurrencyCode {
                            Text("Billed as \(expected.formatted()) \(code). The amount is converted at today's rate; adjust it to what your bank charged.")
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Mark Paid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { Task { await save() } }
                        .disabled(isConfirmDisabled)
                }
            }
            .disabled(isSaving)
            .errorAlert($alert)
            .task { await loadPreview() }
        }
    }

    private func loadPreview() async {
        guard hasAccount, let client = services.client else { return }
        // The estimate is a convenience: without it the user types the amount.
        guard let loaded = try? await client.send(Endpoints.recurringPayPreview(id: detail.id)) else { return }
        preview = loaded
        if loaded.isCrossCurrency, let converted = loaded.convertedAmount {
            amount = converted
        }
    }

    private func save() async {
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = recordsTransaction
            ? RecurringMarkPaidRequest(
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                createTransaction: true,
                amount: amount,
                time: paidDate,
                accountId: hasAccount ? nil : accountId
            )
            : RecurringMarkPaidRequest(notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
        do {
            _ = try await client.send(Endpoints.markRecurringPeriodPaid(id: detail.id, periodId: period.id, request))
            await onPaid()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// Recurring patterns detected in the user's transactions. Accept opens quick-add pre-filled
/// and marks the candidate accepted once the subscription exists; a likely existing match can
/// be linked directly; dismiss hides it.
struct RecurringCandidatesScreen: View {
    var onChange: () async -> Void = {}

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData

    @State private var state: LoadState<RecurringCandidatesResponse> = .idle
    @State private var acceptTarget: RecurringCandidate?
    @State private var busyID: String?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Discover")
            .task { if state.value == nil { await load() } }
            .refreshable { await load() }
            .sheet(item: $acceptTarget) { candidate in
                RecurringQuickAddSheet(prefill: RecurringQuickAddPrefill(
                    name: candidate.suggestedName,
                    amount: candidate.averageAmount,
                    currencyCode: candidate.currencyCode,
                    frequency: candidate.detectedFrequency,
                    accountId: candidate.accountId
                )) { created in
                    await resolve(candidate) { try await $0.send(Endpoints.acceptRecurringCandidate(id: candidate.id, subscriptionId: created.id)) }
                }
            }
            .errorAlert($alert)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("Looking for recurring payments…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let response):
            let pending = response.candidates.filter { $0.status == .pending }
            if pending.isEmpty {
                ContentUnavailableView {
                    Label("Nothing New Found", systemImage: "sparkle.magnifyingglass")
                } description: {
                    Text("No new recurring patterns were found in your transactions.")
                } actions: {
                    Button("Check Again") { Task { await load() } }
                }
            } else {
                List {
                    let active = pending.filter { !$0.isOutdated }
                    let outdated = pending.filter(\.isOutdated)
                    if !active.isEmpty {
                        Section {
                            ForEach(active) { candidate in row(candidate) }
                        } footer: {
                            if let lastRun = response.lastRunAt {
                                Text("Checked \(lastRun.formatted(.relative(presentation: .named)))")
                            }
                        }
                    }
                    if !outdated.isEmpty {
                        Section {
                            ForEach(outdated) { candidate in row(candidate) }
                        } header: {
                            Text("No Longer Recurring")
                        } footer: {
                            Text("These patterns stopped in recent months.")
                        }
                    }
                }
            }
        }
    }

    private func row(_ candidate: RecurringCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.suggestedName)
                        .font(.headline)
                    Text("\(Text(candidate.detectedFrequency.recurringLabel)) · \(candidate.occurrenceCount) payments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let accountName = referenceData.account(id: candidate.accountId)?.name {
                        Text(accountName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    AmountText(candidate.averageAmount, currencyCode: candidate.currencyCode)
                        .font(.body.weight(.semibold))
                    Text("\(candidate.confidenceScore, format: .percent.precision(.fractionLength(0))) match")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                if let match = candidate.possibleMatch {
                    Button {
                        Task { await resolve(candidate) { try await $0.send(Endpoints.acceptRecurringCandidate(id: candidate.id, subscriptionId: match.id)) } }
                    } label: {
                        Text("Link to \(match.name)")
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Add") { acceptTarget = candidate }
                        .buttonStyle(.borderedProminent)
                }
                Button("Dismiss") {
                    Task { await resolve(candidate) { try await $0.send(Endpoints.dismissRecurringCandidate(id: candidate.id)) } }
                }
                .buttonStyle(.bordered)
                if candidate.possibleMatch != nil {
                    Button("Add New") { acceptTarget = candidate }
                        .buttonStyle(.bordered)
                }
            }
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .disabled(busyID == candidate.id)
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await client.send(Endpoints.detectRecurringCandidates()))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(error) }
        }
    }

    private func resolve<Value>(_ candidate: RecurringCandidate, _ action: (APIClient) async throws -> Value) async {
        guard let client = services.client else { return }
        busyID = candidate.id
        defer { busyID = nil }
        do {
            _ = try await action(client)
        } catch {
            alert = ErrorAlert(error)
        }
        await load()
        await onChange()
    }
}
