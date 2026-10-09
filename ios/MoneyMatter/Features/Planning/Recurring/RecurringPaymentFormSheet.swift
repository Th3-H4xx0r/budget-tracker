import MoneyMatterKit
import SwiftUI

/// Values a quick-add can start from, e.g. a discovered candidate.
struct RecurringQuickAddPrefill: Hashable {
    var name: String
    var amount: Decimal?
    var currencyCode: String?
    var frequency: SubscriptionFrequency
    var accountId: String?
}

/// The web's quick-add dialog: the essentials only; the detail screen refines the rest.
struct RecurringQuickAddSheet: View {
    let prefill: RecurringQuickAddPrefill?
    let onCreated: (RecurringSubscriptionRef) async -> Void

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var transactionType: TransactionType = .expense
    @State private var type: SubscriptionType = .subscription
    @State private var amount: Decimal?
    @State private var currencyCode = ""
    @State private var frequency: SubscriptionFrequency = .monthly
    @State private var hasNextPayment = true
    @State private var nextPayment = Date.now
    @State private var maxOccurrences = 12
    @State private var isSaving = false
    @State private var alert: ErrorAlert?
    @State private var didPrefill = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var validationMessage: LocalizedStringKey? {
        if trimmedName.isEmpty { return "Enter a name." }
        if type == .subscription && (amount ?? 0) <= 0 { return "Subscriptions need an amount." }
        if type == .installment && !hasNextPayment { return "Installments need a first payment date." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Direction", selection: $transactionType) {
                        Text("Expense").tag(TransactionType.expense)
                        Text("Income").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    Picker("Type", selection: $type) {
                        ForEach(SubscriptionType.recurringSelectable, id: \.self) { type in
                            Text(type.recurringLabel).tag(type)
                        }
                    }
                }
                Section("Amount") {
                    TextField("Amount", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                    RecurringCurrencyPicker(selection: $currencyCode)
                }
                Section {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(SubscriptionFrequency.recurringSelectable, id: \.self) { frequency in
                            Text(frequency.recurringLabel).tag(frequency)
                        }
                    }
                    Toggle("Next Payment Date", isOn: $hasNextPayment)
                    if hasNextPayment {
                        DatePicker("Next Payment", selection: $nextPayment, displayedComponents: .date)
                    }
                    if type == .installment {
                        Stepper(value: $maxOccurrences, in: 1...600) {
                            LabeledContent("Number of Payments", value: "\(maxOccurrences)")
                        }
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    if let validationMessage {
                        Text(validationMessage)
                    } else {
                        Text("Transactions whose note contains the name are linked automatically.")
                    }
                }
            }
            .navigationTitle("New Recurring Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(validationMessage != nil || isSaving)
                }
            }
            .disabled(isSaving)
            .errorAlert($alert)
            .onAppear(perform: applyPrefill)
        }
    }

    private func applyPrefill() {
        guard !didPrefill else { return }
        didPrefill = true
        currencyCode = session.baseCurrency?.currencyCode ?? referenceData.userCurrencies.first?.currencyCode ?? "USD"
        guard let prefill else { return }
        name = prefill.name
        amount = prefill.amount
        if let code = prefill.currencyCode { currencyCode = code }
        if prefill.frequency != .unknown { frequency = prefill.frequency }
    }

    private func save() async {
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }
        let request = RecurringSubscriptionRequest.quickAdd(
            name: trimmedName,
            type: type,
            transactionType: transactionType,
            amount: amount,
            currencyCode: currencyCode,
            frequency: frequency,
            nextPaymentDate: hasNextPayment ? CalendarDate(date: nextPayment) : nil,
            maxOccurrences: maxOccurrences,
            accountId: prefill?.accountId,
            today: CalendarDate(date: .now)
        )
        do {
            let created = try await client.send(Endpoints.createRecurringSubscription(request))
            await onCreated(created)
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// The full editor: basics, schedule and reminders, automation with matching rules, and
/// organisation. Mirrors the web's four detail editors in one form.
struct RecurringPaymentFormSheet: View {
    let detail: RecurringSubscriptionDetail
    let onSaved: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var type: SubscriptionType
    @State private var transactionType: TransactionType
    @State private var amount: Decimal?
    @State private var currencyCode: String
    @State private var frequency: SubscriptionFrequency
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var maxOccurrences: Int
    @State private var reminders: Set<RecurringRemindPreset>
    @State private var notifyEmail: Bool
    @State private var mode: RecurringAutomationMode
    @State private var keywords: String
    @State private var amountRuleOn: Bool
    @State private var amountMin: Decimal?
    @State private var amountMax: Decimal?
    @State private var accountRuleOn: Bool
    @State private var accountId: String?
    @State private var categoryId: String?
    @State private var payeeId: String?
    @State private var tagIds: Set<String>
    @State private var notes: String
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    init(detail: RecurringSubscriptionDetail, onSaved: @escaping () async -> Void) {
        self.detail = detail
        self.onSaved = onSaved
        _name = State(initialValue: detail.name)
        _type = State(initialValue: detail.type == .unknown ? .subscription : detail.type)
        _transactionType = State(initialValue: detail.transactionType == .unknown ? .expense : detail.transactionType)
        _amount = State(initialValue: detail.expectedAmount)
        _currencyCode = State(initialValue: detail.expectedCurrencyCode ?? detail.account?.currencyCode ?? "")
        _frequency = State(initialValue: detail.frequency == .unknown ? .monthly : detail.frequency)
        _startDate = State(initialValue: (detail.startDate ?? CalendarDate(date: .now)).startDate())
        _hasEndDate = State(initialValue: detail.endDate != nil)
        _endDate = State(initialValue: detail.endDate?.startDate() ?? .now)
        _hasDueDate = State(initialValue: detail.dueDate != nil)
        _dueDate = State(initialValue: detail.dueDate?.startDate() ?? .now)
        _maxOccurrences = State(initialValue: detail.maxOccurrences ?? 12)
        _reminders = State(initialValue: Set(detail.remindBefore))
        _notifyEmail = State(initialValue: detail.notifyEmail)
        _mode = State(initialValue: detail.automationMode)
        var keywordList: [String] = []
        var amountRange: (Decimal, Decimal)?
        var hasAccountRule = false
        for rule in detail.matchingRules.rules {
            switch rule {
            case .note(let values): keywordList += values
            case .amount(let min, let max, _): amountRange = (min, max)
            case .accountId: hasAccountRule = true
            default: break
            }
        }
        _keywords = State(initialValue: keywordList.joined(separator: ", "))
        _amountRuleOn = State(initialValue: amountRange != nil)
        _amountMin = State(initialValue: amountRange?.0)
        _amountMax = State(initialValue: amountRange?.1)
        _accountRuleOn = State(initialValue: hasAccountRule)
        _accountId = State(initialValue: detail.accountId)
        _categoryId = State(initialValue: detail.categoryId)
        _payeeId = State(initialValue: detail.payeeId)
        _tagIds = State(initialValue: Set(detail.tagIds))
        _notes = State(initialValue: detail.notes ?? "")
    }

    private var hasAmount: Bool { (amount ?? 0) > 0 }

    private var validationMessage: LocalizedStringKey? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a name." }
        if type == .subscription && !hasAmount { return "Subscriptions need an amount." }
        if type == .installment && !hasDueDate { return "Installments need a payment schedule date." }
        if hasEndDate && endDate < startDate { return "The end date must be after the start date." }
        if mode == .record && accountId == nil { return "Automatic recording needs an account." }
        if mode == .record && !hasAmount { return "Automatic recording needs an amount." }
        if mode == .match && rules.isEmpty { return "Add at least one matching rule." }
        return nil
    }

    private var rules: [RecurringMatchingRule] {
        var rules: [RecurringMatchingRule] = []
        let words = keywords.split(separator: ",").map { String($0) }
        rules.append(.note(keywords: words))
        if amountRuleOn {
            rules.append(.amount(min: amountMin ?? 0, max: amountMax ?? 0, currencyCode: hasAmount ? currencyCode : nil))
        }
        if accountRuleOn, let accountId {
            rules.append(.accountId(accountId))
        }
        return RecurringMatchingRule.nonEmpty(rules)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(SubscriptionType.recurringSelectable, id: \.self) { type in
                            Text(type.recurringLabel).tag(type)
                        }
                    }
                    Picker("Direction", selection: $transactionType) {
                        Text("Expense").tag(TransactionType.expense)
                        Text("Income").tag(TransactionType.income)
                    }
                    TextField("Amount", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                    RecurringCurrencyPicker(selection: $currencyCode)
                }
                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(SubscriptionFrequency.recurringSelectable, id: \.self) { frequency in
                            Text(frequency.recurringLabel).tag(frequency)
                        }
                    }
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    Toggle("Next Payment Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Next Payment", selection: $dueDate, displayedComponents: .date)
                    }
                    Toggle("End Date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                    if type == .installment {
                        Stepper(value: $maxOccurrences, in: 1...600) {
                            LabeledContent("Number of Payments", value: "\(maxOccurrences)")
                        }
                    }
                }
                Section {
                    ForEach(RecurringRemindPreset.selectable, id: \.self) { preset in
                        Button {
                            toggleReminder(preset)
                        } label: {
                            HStack {
                                Text(preset.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if reminders.contains(preset) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(!reminders.contains(preset) && reminders.count >= RecurringRemindPreset.maxSelected)
                    }
                    Toggle("Email Reminders", isOn: $notifyEmail)
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Choose up to \(RecurringRemindPreset.maxSelected) reminders.")
                }
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(RecurringAutomationMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    if mode == .match {
                        TextField("Note keywords, comma-separated", text: $keywords)
                            .textInputAutocapitalization(.never)
                        Toggle("Amount Range", isOn: $amountRuleOn)
                        if amountRuleOn {
                            TextField("Minimum", value: $amountMin, format: .number)
                                .keyboardType(.decimalPad)
                            TextField("Maximum", value: $amountMax, format: .number)
                                .keyboardType(.decimalPad)
                        }
                        Toggle("Only This Account", isOn: $accountRuleOn)
                    }
                } header: {
                    Text("Automation")
                } footer: {
                    switch mode {
                    case .match: Text("Imported transactions that pass every rule are linked and mark the period paid.")
                    case .record: Text("On each due date, the expense is recorded on the account and the period is marked paid.")
                    case .manual: Text("You mark each payment yourself.")
                    }
                }
                Section("Organize") {
                    Picker("Account", selection: $accountId) {
                        Text("None").tag(String?.none)
                        ForEach(referenceData.accounts.filter { $0.status == .active || $0.id == accountId }) { account in
                            Text(account.name).tag(String?.some(account.id))
                        }
                    }
                    Picker("Category", selection: $categoryId) {
                        Text("None").tag(String?.none)
                        ForEach(referenceData.categories) { category in
                            Text(category.name).tag(String?.some(category.id))
                        }
                    }
                    Picker("Payee", selection: $payeeId) {
                        Text("None").tag(String?.none)
                        ForEach(referenceData.payees) { payee in
                            Text(payee.name).tag(String?.some(payee.id))
                        }
                    }
                    if !referenceData.tags.isEmpty {
                        NavigationLink {
                            RecurringTagPicker(selection: $tagIds)
                        } label: {
                            LabeledContent("Tags") {
                                Text(tagIds.isEmpty ? String(localized: "None") : String(localized: "\(tagIds.count) selected"))
                            }
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("Edit Recurring Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(validationMessage != nil || isSaving)
                }
                if let validationMessage {
                    ToolbarItem(placement: .bottomBar) {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isSaving)
            .errorAlert($alert)
        }
    }

    private func toggleReminder(_ preset: RecurringRemindPreset) {
        if reminders.contains(preset) {
            reminders.remove(preset)
        } else if reminders.count < RecurringRemindPreset.maxSelected {
            reminders.insert(preset)
        }
    }

    private func save() async {
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = RecurringSubscriptionRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            transactionType: transactionType,
            expectedAmount: hasAmount ? amount : nil,
            expectedCurrencyCode: hasAmount ? currencyCode : nil,
            frequency: frequency,
            startDate: CalendarDate(date: startDate),
            endDate: hasEndDate ? CalendarDate(date: endDate) : nil,
            accountId: accountId,
            categoryId: categoryId,
            payeeId: payeeId,
            tagIds: referenceData.tags.map(\.id).filter { tagIds.contains($0) },
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            dueDate: hasDueDate ? CalendarDate(date: dueDate) : nil,
            maxOccurrences: type == .installment ? maxOccurrences : nil,
            remindBefore: RecurringRemindPreset.selectable.filter { reminders.contains($0) },
            notifyEmail: notifyEmail,
            autoRecord: mode == .record,
            matchingRules: RecurringMatchingRules(rules: mode == .match ? rules : []),
            sendsNulls: true
        )
        do {
            _ = try await client.send(Endpoints.updateRecurringSubscription(id: detail.id, request))
            await onSaved()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// Picks one of the user's connected currencies.
struct RecurringCurrencyPicker: View {
    @Binding var selection: String
    @Environment(ReferenceDataStore.self) private var referenceData

    var body: some View {
        let codes = Set(referenceData.userCurrencies.map(\.currencyCode) + (selection.isEmpty ? [] : [selection]))
        Picker("Currency", selection: $selection) {
            ForEach(codes.sorted(), id: \.self) { code in
                Text(verbatim: code).tag(code)
            }
        }
    }
}

/// Multi-select of the user's tags.
private struct RecurringTagPicker: View {
    @Binding var selection: Set<String>
    @Environment(ReferenceDataStore.self) private var referenceData

    var body: some View {
        List(referenceData.tags) { tag in
            Button {
                if selection.contains(tag.id) {
                    selection.remove(tag.id)
                } else {
                    selection.insert(tag.id)
                }
            } label: {
                HStack {
                    Circle()
                        .fill(Color(hex: tag.color) ?? .secondary)
                        .frame(width: 10, height: 10)
                    Text(tag.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(tag.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .accessibilityAddTraits(selection.contains(tag.id) ? .isSelected : [])
        }
        .navigationTitle("Tags")
    }
}
