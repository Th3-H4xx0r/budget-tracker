import MoneyMatterKit
import SwiftUI

extension PlannedBudgetFrequency {
    /// The repeat choices offered in pickers, in the web's order.
    static let plannedChoices: [PlannedBudgetFrequency] = [
        .monthly, .biweekly, .weekly, .quarterly, .semiAnnual, .annual, .custom,
    ]

    var plannedLabel: LocalizedStringKey {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Biweekly"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .semiAnnual: "Every 6 Months"
        case .annual: "Yearly"
        case .custom: "Custom Interval"
        case .unknown: "Other"
        }
    }
}

extension CalendarDate {
    /// A binding-friendly bridge for `DatePicker`.
    var plannedDate: Date { startDate() }
}

/// A category row that pushes the shared category picker; optional, with a clear action.
struct PlannedCategoryField: View {
    let title: LocalizedStringKey
    @Binding var categoryID: String?

    @Environment(ReferenceDataStore.self) private var referenceData

    var body: some View {
        NavigationLink {
            TransactionCategoryPicker(isSelected: { $0 == categoryID }, onSelect: { categoryID = $0.id })
        } label: {
            LabeledContent(title) {
                if let category = referenceData.category(id: categoryID) {
                    Text(category.name)
                } else {
                    Text("None")
                }
            }
        }
        if categoryID != nil {
            Button("Clear Category", role: .destructive) { categoryID = nil }
        }
    }
}

/// A decimal amount field with the currency code as its label.
struct PlannedAmountField: View {
    let title: LocalizedStringKey
    @Binding var amount: Decimal
    let currencyCode: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: $amount, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(currencyCode)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The salary profile fields shared by plan creation and the default salary profile.
private struct PlannedSalaryFields: View {
    @Binding var profile: PlannedBudgetSalaryProfile
    let currencyCode: String

    var body: some View {
        PlannedAmountField(title: "Amount", amount: $profile.salaryAmount, currencyCode: currencyCode)
        Picker("Frequency", selection: $profile.salaryFrequency) {
            ForEach(PlannedBudgetFrequency.plannedChoices, id: \.self) { frequency in
                Text(frequency.plannedLabel).tag(frequency)
            }
        }
        if profile.salaryFrequency == .custom {
            Stepper(value: intervalDays, in: 1...365) {
                LabeledContent("Days Between Payments") {
                    Text(intervalDays.wrappedValue, format: .number).monospacedDigit()
                }
            }
        }
        Toggle("Set Pay Date", isOn: hasPayDate)
        if profile.salaryAnchorDate != nil {
            DatePicker("Pay Date", selection: payDate, displayedComponents: .date)
        }
        PlannedCategoryField(title: "Income Category", categoryID: $profile.salaryCategoryId)
    }

    private var intervalDays: Binding<Int> {
        Binding(
            get: { profile.salaryIntervalDays ?? 30 },
            set: { profile.salaryIntervalDays = $0 }
        )
    }

    private var hasPayDate: Binding<Bool> {
        Binding(
            get: { profile.salaryAnchorDate != nil },
            set: { profile.salaryAnchorDate = $0 ? CalendarDate(date: .now) : nil }
        )
    }

    private var payDate: Binding<Date> {
        Binding(
            get: { profile.salaryAnchorDate?.plannedDate ?? .now },
            set: { profile.salaryAnchorDate = CalendarDate(date: $0) }
        )
    }
}

private extension PlannedBudgetSalaryProfile {
    var isValid: Bool {
        salaryAmount >= 0 && (salaryFrequency != .custom || (salaryIntervalDays ?? 30) > 0)
    }

    /// Custom intervals need an explicit day count; the stepper shows 30 until it's touched.
    var normalized: PlannedBudgetSalaryProfile {
        var copy = self
        if copy.salaryFrequency == .custom, copy.salaryIntervalDays == nil { copy.salaryIntervalDays = 30 }
        return copy
    }
}

// MARK: - Create plan

/// `POST /future-budgets`, prefilled with the default salary profile.
struct PlannedBudgetCreateSheet: View {
    let currencyCode: String
    let onCreated: (PlannedBudgetPlan) -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: PlannedBudgetKind = .manual
    @State private var categoryIDs: [String] = []
    @State private var startDate = Date.now
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var salary: PlannedBudgetSalaryProfile
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    init(defaults: PlannedBudgetSalarySettings?, currencyCode: String, onCreated: @escaping (PlannedBudgetPlan) -> Void) {
        self.currencyCode = currencyCode
        self.onCreated = onCreated
        _salary = State(initialValue: defaults.map(PlannedBudgetSalaryProfile.init) ?? PlannedBudgetSalaryProfile())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Plan Name", text: $name)
                    Picker("Plan Type", selection: $kind) {
                        Text("Manual Plan").tag(PlannedBudgetKind.manual)
                        Text("Category Plan").tag(PlannedBudgetKind.category)
                    }
                    .pickerStyle(.segmented)
                }

                if kind == .category {
                    Section {
                        NavigationLink {
                            TransactionCategoryPicker(
                                isSelected: { categoryIDs.contains($0) },
                                onSelect: toggle,
                                dismissesOnSelect: false
                            )
                        } label: {
                            LabeledContent("Categories") {
                                if categoryIDs.isEmpty {
                                    Text("None")
                                } else {
                                    Text(categoryNames)
                                        .lineLimit(1)
                                }
                            }
                        }
                    } footer: {
                        Text("Categories or groups to track.")
                    }
                }

                Section("Dates") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
                }

                Section("Salary Projection") {
                    PlannedSalaryFields(profile: $salary, currencyCode: currencyCode)
                }
            }
            .navigationTitle("New Planned Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create", role: .confirm) { Task { await create() } }
                            .disabled(!canCreate)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($alert)
        }
    }

    private var categoryNames: String {
        categoryIDs.compactMap { referenceData.category(id: $0)?.name }.formatted(.list(type: .and, width: .narrow))
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && CalendarDate(date: startDate) <= CalendarDate(date: endDate)
            && (kind == .manual || !categoryIDs.isEmpty)
            && salary.isValid
    }

    private func toggle(_ category: Category) {
        if let index = categoryIDs.firstIndex(of: category.id) {
            categoryIDs.remove(at: index)
        } else {
            categoryIDs.append(category.id)
        }
    }

    private func create() async {
        guard let client = services.client, canCreate else { return }
        isSaving = true
        defer { isSaving = false }
        let request = PlannedBudgetCreateRequest(
            name: name,
            type: kind,
            categoryIds: categoryIDs,
            startDate: CalendarDate(date: startDate),
            endDate: CalendarDate(date: endDate),
            salary: salary.normalized
        )
        do {
            let plan = try await client.send(Endpoints.createPlannedBudget(request))
            onCreated(plan)
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Salary profile

/// `PUT /future-budgets/salary-settings`: the default for new plans.
struct PlannedSalaryProfileSheet: View {
    let currencyCode: String
    let onSaved: (PlannedBudgetSalarySettings) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var profile: PlannedBudgetSalaryProfile
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    init(settings: PlannedBudgetSalarySettings?, currencyCode: String, onSaved: @escaping (PlannedBudgetSalarySettings) -> Void) {
        self.currencyCode = currencyCode
        self.onSaved = onSaved
        _profile = State(initialValue: settings.map(PlannedBudgetSalaryProfile.init) ?? PlannedBudgetSalaryProfile())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PlannedSalaryFields(profile: $profile, currencyCode: currencyCode)
                } footer: {
                    Text("Used as the default for new plans. Existing plans remain unchanged until you apply the update.")
                }
            }
            .navigationTitle("Salary Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", role: .confirm) { Task { await save() } }
                            .disabled(!profile.isValid)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($alert)
        }
    }

    private func save() async {
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let request = PlannedBudgetSalarySettingsRequest(profile: profile.normalized)
            let settings = try await client.send(Endpoints.updatePlannedBudgetSalarySettings(request))
            onSaved(settings)
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Plan-only entry

/// Adds or edits a plan-only future transaction. It stays in this plan and never touches
/// real transactions.
struct PlannedBudgetEntrySheet: View {
    let planID: String
    let entryID: String?
    let currencyCode: String
    let onSaved: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var request: PlannedBudgetEntryRequest
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    init(planID: String, entry: PlannedBudgetEntry?, defaultDate: CalendarDate, currencyCode: String, onSaved: @escaping () -> Void) {
        self.planID = planID
        self.entryID = entry?.id
        self.currencyCode = currencyCode
        self.onSaved = onSaved
        let initial = entry.map {
            PlannedBudgetEntryRequest(
                transactionType: $0.transactionType == .income ? .income : .expense,
                amount: $0.amount,
                date: $0.date,
                categoryId: $0.categoryId,
                note: $0.note,
                frequency: $0.frequency == .unknown ? nil : $0.frequency,
                intervalDays: $0.intervalDays
            )
        } ?? PlannedBudgetEntryRequest(transactionType: .expense, amount: 0, date: defaultDate)
        _request = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $request.transactionType) {
                        Text("Expense").tag(TransactionType.expense)
                        Text("Income").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    PlannedAmountField(title: "Amount", amount: $request.amount, currencyCode: currencyCode)
                    DatePicker("Date", selection: date, displayedComponents: .date)
                    PlannedCategoryField(title: "Category", categoryID: $request.categoryId)
                }
                Section {
                    Picker("Repeat", selection: $request.frequency) {
                        Text("One Time").tag(PlannedBudgetFrequency?.none)
                        ForEach(PlannedBudgetFrequency.plannedChoices, id: \.self) { frequency in
                            Text(frequency.plannedLabel).tag(PlannedBudgetFrequency?.some(frequency))
                        }
                    }
                    if request.frequency == .custom {
                        Stepper(value: intervalDays, in: 1...365) {
                            LabeledContent("Days Between") {
                                Text(intervalDays.wrappedValue, format: .number).monospacedDigit()
                            }
                        }
                    }
                }
                Section {
                    TextField("Note", text: note, axis: .vertical)
                } footer: {
                    Text("These entries stay in this plan only and never affect your real transactions.")
                }
            }
            .navigationTitle(entryID == nil ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(entryID == nil ? "Add" : "Save", role: .confirm) { Task { await save() } }
                            .disabled(request.amount <= 0)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($alert)
        }
    }

    private var date: Binding<Date> {
        Binding(get: { request.date.plannedDate }, set: { request.date = CalendarDate(date: $0) })
    }

    private var note: Binding<String> {
        Binding(get: { request.note ?? "" }, set: { request.note = $0 })
    }

    private var intervalDays: Binding<Int> {
        Binding(get: { request.intervalDays ?? 30 }, set: { request.intervalDays = $0 })
    }

    private func save() async {
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }
        var body = request
        if body.frequency == .custom, body.intervalDays == nil { body.intervalDays = 30 }
        do {
            if let entryID {
                _ = try await client.send(Endpoints.updatePlannedBudgetEntry(planId: planID, entryId: entryID, body))
            } else {
                _ = try await client.send(Endpoints.createPlannedBudgetEntry(planId: planID, body))
            }
            onSaved()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Recurring adjustment

/// Adjusts one bank-derived recurring payment's projection for this plan only: amount,
/// category, next date, or excluding it.
struct PlannedRecurringAdjustSheet: View {
    let planID: String
    let occurrence: PlannedBudgetOccurrence
    let currencyCode: String
    let onSaved: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Decimal
    @State private var categoryID: String?
    @State private var nextDate: Date
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    init(planID: String, occurrence: PlannedBudgetOccurrence, currencyCode: String, onSaved: @escaping () -> Void) {
        self.planID = planID
        self.occurrence = occurrence
        self.currencyCode = currencyCode
        self.onSaved = onSaved
        _amount = State(initialValue: occurrence.amount)
        _categoryID = State(initialValue: occurrence.categoryId)
        _nextDate = State(initialValue: occurrence.date.plannedDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PlannedAmountField(title: "Projected Amount", amount: $amount, currencyCode: currencyCode)
                    PlannedCategoryField(title: "Category", categoryID: $categoryID)
                    DatePicker("Next Date", selection: $nextDate, displayedComponents: .date)
                } header: {
                    Text(occurrence.name ?? String(localized: "Recurring Payment"))
                } footer: {
                    Text("Changes apply to this plan only. Your recurring payment stays as it is.")
                }
                Section {
                    Button("Exclude From This Plan", role: .destructive) {
                        Task { await send(PlannedBudgetRecurringOverrideRequest(isIncluded: false)) }
                    }
                }
            }
            .navigationTitle("Adjust Projection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", role: .confirm) { Task { await send(changes) } }
                            .disabled(amount < 0 || !hasChanges)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($alert)
        }
    }

    private var hasChanges: Bool {
        amount != occurrence.amount || categoryID != occurrence.categoryId || CalendarDate(date: nextDate) != occurrence.date
    }

    private var changes: PlannedBudgetRecurringOverrideRequest {
        var request = PlannedBudgetRecurringOverrideRequest()
        if amount != occurrence.amount { request.amount = .set(amount) }
        if categoryID != occurrence.categoryId { request.categoryId = categoryID.map { .set($0) } ?? .clear }
        let next = CalendarDate(date: nextDate)
        if next != occurrence.date { request.nextOccurrenceDate = .set(next) }
        return request
    }

    private func send(_ request: PlannedBudgetRecurringOverrideRequest) async {
        guard let client = services.client, let subscriptionID = occurrence.subscriptionId else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.send(Endpoints.updatePlannedBudgetRecurring(planId: planID, subscriptionId: subscriptionID, request))
            onSaved()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
