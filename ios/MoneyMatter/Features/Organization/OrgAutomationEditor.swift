import MoneyMatterKit
import SwiftUI

/// Creates or edits an automation rule: a name, a conditions builder (all/any), an actions
/// builder, and a live preview of matching transactions, matching the web's
/// `pages/automations/editor.vue`.
struct OrgAutomationEditorScreen: View {
    let rule: OrgAutomation?
    let onSaved: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isEnabled: Bool
    @State private var match: OrgAutomationMatch
    @State private var conditions: [ConditionDraft]
    @State private var actions: [ActionDraft]
    @State private var accountGroups: [OrgAutoOption] = []
    @State private var bankConnections: [OrgAutoOption] = []
    @State private var preview: LoadState<OrgAutomationPreview> = .idle
    @State private var isSaving = false
    @State private var isConfirmingDelete = false
    @State private var isApplying = false
    @State private var alert: ErrorAlert?

    init(rule: OrgAutomation?, onSaved: @escaping () async -> Void) {
        self.rule = rule
        self.onSaved = onSaved
        _name = State(initialValue: rule?.name ?? "")
        _isEnabled = State(initialValue: rule?.isEnabled ?? true)
        _match = State(initialValue: rule?.conditions.match == .any ? .any : .all)
        _conditions = State(initialValue: rule.map { $0.conditions.items.compactMap(ConditionDraft.init) } ?? [ConditionDraft(field: .note)])
        _actions = State(initialValue: rule.map { $0.actions.compactMap(ActionDraft.init) } ?? [ActionDraft(kind: .setCategory)])
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasUnknownParts: Bool { rule.map { !$0.isFullyEditable } ?? false }

    private var nameError: String? {
        if trimmedName.isEmpty { return String(localized: "Enter a name.") }
        if trimmedName.count > OrgAutomationLimits.maxNameLength { return String(localized: "Names can be up to 120 characters.") }
        return nil
    }

    private var formError: String? {
        if conditions.isEmpty { return String(localized: "Add at least one condition.") }
        if actions.isEmpty { return String(localized: "Add at least one action.") }
        if conditions.filter({ $0.field == .transactionType }).count > 1 {
            return String(localized: "Use one transaction type condition at most.")
        }
        return nil
    }

    private var isValid: Bool {
        nameError == nil && formError == nil && !hasUnknownParts
            && conditions.allSatisfy { $0.error == nil } && actions.allSatisfy { $0.error == nil }
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                Toggle("Enabled", isOn: $isEnabled)
            } footer: {
                if !name.isEmpty, let nameError { Text(nameError) }
            }

            Section {
                Picker("Match", selection: $match) {
                    Text("All conditions").tag(OrgAutomationMatch.all)
                    Text("Any condition").tag(OrgAutomationMatch.any)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("When a transaction matches")
            } footer: {
                if hasUnknownParts {
                    Text("This rule uses conditions or actions this app version can't edit. Edit it on the web.")
                        .foregroundStyle(.orange)
                } else if let formError {
                    Text(formError)
                }
            }

            ForEach($conditions) { $draft in
                conditionSection($draft)
            }
            if conditions.count < OrgAutomationLimits.maxConditions {
                Section {
                    Menu {
                        ForEach(OrgAutoField.allCases, id: \.self) { field in
                            Button(field.title) { conditions.append(ConditionDraft(field: field)) }
                                .disabled(field == .transactionType && conditions.contains { $0.field == .transactionType })
                        }
                    } label: {
                        Label("Add Condition", systemImage: "plus.circle")
                    }
                }
            }

            ForEach($actions) { $draft in
                actionSection($draft)
            }
            let unusedKinds = OrgAutoActionKind.allCases.filter { kind in !actions.contains { $0.kind == kind } }
            if !unusedKinds.isEmpty, actions.count < OrgAutomationLimits.maxActions {
                Section {
                    Menu {
                        ForEach(unusedKinds, id: \.self) { kind in
                            Button(kind.title) { actions.append(ActionDraft(kind: kind)) }
                        }
                    } label: {
                        Label("Add Action", systemImage: "plus.circle")
                    }
                }
            }

            previewSection

            if rule != nil {
                Section {
                    Button("Run on Past Transactions", systemImage: "clock.arrow.circlepath") { isApplying = true }
                } footer: {
                    Text("Uses the saved version of this rule.")
                }
                Section {
                    Button("Delete Automation", role: .destructive) { isConfirmingDelete = true }
                }
            }
        }
        .navigationTitle(rule == nil ? LocalizedStringKey("New Automation") : LocalizedStringKey("Edit Automation"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(!isValid)
                }
            }
        }
        .confirmationDialog("Delete Automation?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Automation", role: .destructive) { Task { await delete() } }
        } message: {
            Text("The rule stops running. Transactions it already changed keep their changes.")
        }
        .sheet(isPresented: $isApplying) {
            if let rule {
                OrgAutomationApplySheet(rule: rule) {
                    await onSaved()
                }
            }
        }
        .errorAlert($alert)
        .task {
            await referenceData.loadIfNeeded()
            await loadOptions()
        }
    }

    // MARK: Conditions

    @ViewBuilder
    private func conditionSection(_ draft: Binding<ConditionDraft>) -> some View {
        let value = draft.wrappedValue
        Section {
            Picker("Field", selection: draft.field) {
                ForEach(OrgAutoField.allCases, id: \.self) { field in
                    Text(field.title).tag(field)
                }
            }
            switch value.field {
            case .note, .merchant:
                Picker("Operator", selection: draft.textOperator) {
                    ForEach(OrgAutomationTextOperator.editable, id: \.self) { op in
                        Text(OrgAutoField.title(for: op)).tag(op)
                    }
                }
                if value.textOperator != .isEmpty {
                    OrgAutoKeywordField(keywords: draft.keywords)
                }
            case .payee, .account, .accountGroup, .bankConnection:
                Picker("Operator", selection: draft.listOperator) {
                    Text("Is any of").tag(OrgAutomationListOperator.isIn)
                    Text("Is none of").tag(OrgAutomationListOperator.notIn)
                }
                let choices = options(for: value.field)
                NavigationLink {
                    OrgAutoMultiSelect(title: value.field.title, options: choices, selection: draft.ids)
                } label: {
                    LabeledContent(value.field.title) {
                        Text(selectionSummary(ids: value.ids, options: choices))
                    }
                }
            case .amount:
                Picker("Operator", selection: draft.amountOperator) {
                    Text("At least").tag(OrgAutomationAmountOperator.gte)
                    Text("At most").tag(OrgAutomationAmountOperator.lte)
                    Text("Between").tag(OrgAutomationAmountOperator.between)
                    Text("Equals").tag(OrgAutomationAmountOperator.equals)
                }
                if value.amountOperator != .lte {
                    LabeledContent(value.amountOperator == .between ? LocalizedStringKey("Minimum") : LocalizedStringKey("Amount")) {
                        TextField("0", value: draft.amountMin, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }
                if value.amountOperator == .lte || value.amountOperator == .between {
                    LabeledContent(value.amountOperator == .between ? LocalizedStringKey("Maximum") : LocalizedStringKey("Amount")) {
                        TextField("0", value: draft.amountMax, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }
                Picker("Currency", selection: draft.currencyChoice) {
                    Text("Transaction currency").tag("transaction")
                    Text("Base currency").tag("base")
                    ForEach(referenceData.userCurrencies) { currency in
                        Text(verbatim: currency.currencyCode).tag("specific:\(currency.currencyCode)")
                    }
                }
            case .transactionType:
                Picker("Type", selection: draft.transactionType) {
                    Text("Expense").tag(TransactionType.expense)
                    Text("Income").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)
            case .dayOfMonth:
                Stepper(value: draft.dayMin, in: 1...31) {
                    LabeledContent("From day", value: "\(value.dayMin)")
                }
                Stepper(value: draft.dayMax, in: 1...31) {
                    LabeledContent("To day", value: "\(value.dayMax)")
                }
            }
        } header: {
            HStack {
                Text("Condition")
                Spacer()
                Button(role: .destructive) {
                    conditions.removeAll { $0.id == value.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .accessibilityLabel(Text("Remove condition"))
            }
        } footer: {
            if let error = value.error { Text(error) }
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func actionSection(_ draft: Binding<ActionDraft>) -> some View {
        let value = draft.wrappedValue
        Section {
            switch value.kind {
            case .setCategory:
                Picker("Category", selection: draft.categoryId) {
                    Text("Choose").tag(String?.none)
                    ForEach(CategoryTree.flatten(referenceData.categoryTree)) { item in
                        Text(verbatim: String(repeating: "    ", count: item.depth) + item.category.name)
                            .tag(Optional(item.category.id))
                    }
                }
                .pickerStyle(.navigationLink)
            case .addTags:
                let options = referenceData.tags.map { OrgAutoOption(id: $0.id, name: $0.name) }
                NavigationLink {
                    OrgAutoMultiSelect(title: String(localized: "Tags"), options: options, selection: draft.tagIds)
                } label: {
                    LabeledContent("Tags") {
                        Text(selectionSummary(ids: value.tagIds, options: options))
                    }
                }
            case .setPayee:
                Picker("Payee", selection: draft.payeeId) {
                    Text("Choose").tag(String?.none)
                    ForEach(referenceData.payees.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { payee in
                        Text(verbatim: payee.name).tag(Optional(payee.id))
                    }
                }
                .pickerStyle(.navigationLink)
            case .setNote:
                Picker("Mode", selection: draft.noteMode) {
                    Text("Replace").tag(OrgAutomationNoteMode.replace)
                    Text("Append").tag(OrgAutomationNoteMode.append)
                    Text("Prepend").tag(OrgAutomationNoteMode.prepend)
                }
                .pickerStyle(.segmented)
                TextField("Note text", text: draft.noteValue, axis: .vertical)
                    .lineLimit(1...4)
            }
        } header: {
            HStack {
                Text(value.kind.title)
                Spacer()
                Button(role: .destructive) {
                    actions.removeAll { $0.id == value.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .accessibilityLabel(Text("Remove action"))
            }
        } footer: {
            if let error = value.error { Text(error) }
        }
    }

    // MARK: Preview

    private var previewSection: some View {
        Section {
            Button {
                Task { await runPreview() }
            } label: {
                Label("Test on Recent Transactions", systemImage: "play.circle")
            }
            .disabled(conditions.isEmpty || conditions.contains { $0.error != nil } || preview.isLoading)
            switch preview {
            case .idle:
                EmptyView()
            case .loading:
                ProgressView()
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await runPreview() }
            case .loaded(let result):
                Text("\(result.matchedCount) of the last \(result.scannedCount) transactions match.")
                    .monospacedDigit()
                ForEach(result.matches) { transaction in
                    ResolvedTransactionRow(transaction: transaction, showsDate: true)
                }
            }
        } header: {
            Text("Preview")
        }
    }

    // MARK: Helpers

    private func options(for field: OrgAutoField) -> [OrgAutoOption] {
        switch field {
        case .payee:
            referenceData.payees
                .map { OrgAutoOption(id: $0.id, name: $0.name) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .account:
            referenceData.accounts.map { OrgAutoOption(id: $0.id, name: $0.name) }
        case .accountGroup:
            accountGroups
        case .bankConnection:
            bankConnections
        default:
            []
        }
    }

    private func selectionSummary(ids: [String], options: [OrgAutoOption]) -> String {
        if ids.isEmpty { return String(localized: "None") }
        let names = ids.compactMap { id in options.first { $0.id == id }?.name }
        if names.count == 1 { return names[0] }
        return String(localized: "\(ids.count) selected")
    }

    private func loadOptions() async {
        guard let client = services.client else { return }
        async let groups = try? client.send(Endpoints.accountGroups())
        async let connections = try? client.send(Endpoints.orgAutomationBankConnections())
        if let loaded = await groups {
            accountGroups = flattenGroups(loaded, depth: 0)
        }
        if let loaded = await connections {
            bankConnections = loaded.map { OrgAutoOption(id: $0.id, name: $0.displayName) }
        }
    }

    private func flattenGroups(_ groups: [AccountGroup], depth: Int) -> [OrgAutoOption] {
        groups.flatMap { group in
            [OrgAutoOption(id: group.id, name: String(repeating: "  ", count: depth) + group.name)]
                + flattenGroups(group.childGroups, depth: depth + 1)
        }
    }

    private var builtConditions: OrgAutomationConditions {
        OrgAutomationConditions(match: match, items: conditions.map(\.condition))
    }

    private func runPreview() async {
        guard let client = services.client else { return }
        preview = .loading
        do {
            preview = .loaded(try await client.send(Endpoints.orgPreviewAutomation(conditions: builtConditions, limit: 5)))
        } catch {
            let apiError = APIError(error)
            preview = apiError.isCancellation ? .idle : .failed(apiError)
        }
    }

    private func save() async {
        guard let client = services.client, isValid else { return }
        isSaving = true
        defer { isSaving = false }
        let payload = OrgAutomationPayload(
            name: trimmedName,
            isEnabled: isEnabled,
            conditions: builtConditions,
            actions: actions.compactMap(\.action)
        )
        do {
            if let rule {
                _ = try await client.send(Endpoints.orgUpdateAutomation(id: rule.id, payload))
            } else {
                _ = try await client.send(Endpoints.orgCreateAutomation(payload))
            }
            await onSaved()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func delete() async {
        guard let client = services.client, let rule else { return }
        do {
            _ = try await client.send(Endpoints.orgDeleteAutomation(id: rule.id))
            await onSaved()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: Drafts

private enum OrgAutoField: String, CaseIterable, Hashable {
    case note, merchant, payee, amount, transactionType, account, accountGroup, bankConnection, dayOfMonth

    var title: String {
        switch self {
        case .note: String(localized: "Note")
        case .merchant: String(localized: "Merchant")
        case .payee: String(localized: "Payee")
        case .amount: String(localized: "Amount")
        case .transactionType: String(localized: "Transaction type")
        case .account: String(localized: "Account")
        case .accountGroup: String(localized: "Account group")
        case .bankConnection: String(localized: "Bank connection")
        case .dayOfMonth: String(localized: "Day of month")
        }
    }

    static func title(for op: OrgAutomationTextOperator) -> String {
        switch op {
        case .containsAny: String(localized: "Contains any of")
        case .notContainsAny: String(localized: "Contains none of")
        case .startsWithAny: String(localized: "Starts with any of")
        case .endsWithAny: String(localized: "Ends with any of")
        case .equalsAny: String(localized: "Equals any of")
        case .isEmpty: String(localized: "Is empty")
        case .unknown: String(localized: "Unknown")
        }
    }
}

private struct ConditionDraft: Identifiable, Hashable {
    let id = UUID()
    var field: OrgAutoField
    var textOperator: OrgAutomationTextOperator = .containsAny
    var keywords: [String] = []
    var listOperator: OrgAutomationListOperator = .isIn
    var ids: [String] = []
    var amountOperator: OrgAutomationAmountOperator = .gte
    var amountMin: Decimal?
    var amountMax: Decimal?
    /// `transaction`, `base`, or `specific:CODE`.
    var currencyChoice = "transaction"
    var transactionType: TransactionType = .expense
    var dayMin = 1
    var dayMax = 31

    init(field: OrgAutoField) {
        self.field = field
    }

    init?(_ condition: OrgAutomationCondition) {
        switch condition {
        case .text(let field, let op, let keywords):
            self.init(field: field == .note ? .note : .merchant)
            textOperator = op == .unknown ? .containsAny : op
            self.keywords = keywords
        case .list(let field, let op, let ids):
            let mapped: OrgAutoField = switch field {
            case .payee: .payee
            case .account: .account
            case .accountGroup: .accountGroup
            case .bankConnection: .bankConnection
            }
            self.init(field: mapped)
            listOperator = op == .unknown ? .isIn : op
            self.ids = ids
        case .amount(let op, let min, let max, let currency):
            self.init(field: .amount)
            amountOperator = op == .unknown ? .gte : op
            amountMin = min
            amountMax = max
            currencyChoice = switch currency {
            case .transaction: "transaction"
            case .base: "base"
            case .specific(let code): "specific:\(code)"
            }
        case .transactionType(let type):
            self.init(field: .transactionType)
            transactionType = type == .income ? .income : .expense
        case .dayOfMonth(let min, let max):
            self.init(field: .dayOfMonth)
            dayMin = min
            dayMax = max
        case .unknown:
            return nil
        }
    }

    var condition: OrgAutomationCondition {
        switch field {
        case .note, .merchant:
            .text(
                field: field == .note ? .note : .merchant,
                operator: textOperator,
                keywords: textOperator == .isEmpty ? [] : keywords
            )
        case .payee, .account, .accountGroup, .bankConnection:
            .list(field: listField, operator: listOperator, ids: ids)
        case .amount:
            .amount(
                operator: amountOperator,
                min: amountOperator == .lte ? nil : amountMin,
                max: amountOperator == .lte || amountOperator == .between ? amountMax : nil,
                currency: currency
            )
        case .transactionType:
            .transactionType(transactionType)
        case .dayOfMonth:
            .dayOfMonth(min: dayMin, max: dayMax)
        }
    }

    private var listField: OrgAutomationListField {
        switch field {
        case .account: .account
        case .accountGroup: .accountGroup
        case .bankConnection: .bankConnection
        default: .payee
        }
    }

    private var currency: OrgAutomationAmountCurrency {
        if currencyChoice == "base" { return .base }
        if currencyChoice.hasPrefix("specific:") { return .specific(code: String(currencyChoice.dropFirst("specific:".count))) }
        return .transaction
    }

    var error: String? {
        switch field {
        case .note, .merchant:
            if textOperator != .isEmpty, keywords.isEmpty { return String(localized: "Add at least one keyword.") }
        case .payee, .account, .accountGroup, .bankConnection:
            if ids.isEmpty { return String(localized: "Choose at least one item.") }
            if ids.count > OrgAutomationLimits.maxIds { return String(localized: "Choose up to 20 items.") }
        case .amount:
            switch amountOperator {
            case .between:
                guard let amountMin, let amountMax else { return String(localized: "Enter both amounts.") }
                if amountMin > amountMax { return String(localized: "The minimum must not exceed the maximum.") }
            case .lte:
                if amountMax == nil { return String(localized: "Enter an amount.") }
            default:
                if amountMin == nil { return String(localized: "Enter an amount.") }
            }
        case .dayOfMonth:
            if dayMin > dayMax { return String(localized: "The first day must not be after the last day.") }
        case .transactionType:
            break
        }
        return nil
    }
}

private enum OrgAutoActionKind: CaseIterable, Hashable {
    case setCategory, addTags, setPayee, setNote

    var title: String {
        switch self {
        case .setCategory: String(localized: "Set category")
        case .addTags: String(localized: "Add tags")
        case .setPayee: String(localized: "Set payee")
        case .setNote: String(localized: "Set note")
        }
    }
}

private struct ActionDraft: Identifiable, Hashable {
    let id = UUID()
    var kind: OrgAutoActionKind
    var categoryId: String?
    var tagIds: [String] = []
    var payeeId: String?
    var noteMode: OrgAutomationNoteMode = .replace
    var noteValue = ""

    init(kind: OrgAutoActionKind) {
        self.kind = kind
    }

    init?(_ action: OrgAutomationAction) {
        switch action {
        case .setCategory(let categoryId):
            self.init(kind: .setCategory)
            self.categoryId = categoryId.isEmpty ? nil : categoryId
        case .addTags(let tagIds):
            self.init(kind: .addTags)
            self.tagIds = tagIds
        case .setPayee(let payeeId):
            self.init(kind: .setPayee)
            self.payeeId = payeeId.isEmpty ? nil : payeeId
        case .setNote(let mode, let value):
            self.init(kind: .setNote)
            noteMode = mode == .unknown ? .replace : mode
            noteValue = value
        case .unknown:
            return nil
        }
    }

    var action: OrgAutomationAction? {
        switch kind {
        case .setCategory: categoryId.map { OrgAutomationAction.setCategory(categoryId: $0) }
        case .addTags: .addTags(tagIds: tagIds)
        case .setPayee: payeeId.map { OrgAutomationAction.setPayee(payeeId: $0) }
        case .setNote: .setNote(mode: noteMode, value: noteValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    var error: String? {
        switch kind {
        case .setCategory:
            if categoryId == nil { return String(localized: "Choose a category.") }
        case .addTags:
            if tagIds.isEmpty { return String(localized: "Choose at least one tag.") }
            if tagIds.count > OrgAutomationLimits.maxIds { return String(localized: "Choose up to 20 tags.") }
        case .setPayee:
            if payeeId == nil { return String(localized: "Choose a payee.") }
        case .setNote:
            let trimmed = noteValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return String(localized: "Enter the note text.") }
            if trimmed.count > OrgAutomationLimits.maxNoteLength { return String(localized: "Notes can be up to 200 characters.") }
        }
        return nil
    }
}

// MARK: Shared pieces

private struct OrgAutoOption: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Keyword chips with a field that adds one on Return.
private struct OrgAutoKeywordField: View {
    @Binding var keywords: [String]
    @State private var input = ""

    var body: some View {
        if !keywords.isEmpty {
            OrgAutoFlowLayout(spacing: 6) {
                ForEach(keywords, id: \.self) { keyword in
                    Button {
                        keywords.removeAll { $0 == keyword }
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: keyword)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove \(keyword)"))
                }
            }
            .padding(.vertical, 4)
        }
        if keywords.count < OrgAutomationLimits.maxKeywords {
            TextField("Add keyword", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(add)
        }
    }

    private func add() {
        let keyword = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(OrgAutomationLimits.maxKeywordLength))
        input = ""
        guard !keyword.isEmpty, !keywords.contains(keyword) else { return }
        keywords.append(keyword)
    }
}

/// Wraps children onto new lines when they run out of width.
private struct OrgAutoFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// A searchable checklist for id-list conditions and tag actions.
private struct OrgAutoMultiSelect: View {
    let title: String
    let options: [OrgAutoOption]
    @Binding var selection: [String]
    @State private var searchText = ""

    private var filtered: [OrgAutoOption] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return options }
        return options.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if options.isEmpty {
                ContentUnavailableView("Nothing to Choose", systemImage: "tray", description: Text("There are no items of this kind yet."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                Section {
                    ForEach(filtered) { option in
                        let isSelected = selection.contains(option.id)
                        Button {
                            if isSelected {
                                selection.removeAll { $0 == option.id }
                            } else if selection.count < OrgAutomationLimits.maxIds {
                                selection.append(option.id)
                            }
                        } label: {
                            HStack {
                                Text(verbatim: option.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                } footer: {
                    Text("Choose up to 20.")
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText)
    }
}
