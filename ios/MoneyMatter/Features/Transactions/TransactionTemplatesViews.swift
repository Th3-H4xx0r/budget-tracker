import MoneyMatterKit
import SwiftUI

/// Loads and caches templates for the picker and the manage screen.
@Observable
final class TransactionTemplatesModel {
    private(set) var state: LoadState<[TransactionTemplate]> = .idle

    var templates: [TransactionTemplate] { state.value ?? [] }

    func load(client: APIClient?) async {
        guard let client else { return }
        if state.value == nil { state = .loading }
        do {
            let rows = try await client.send(Endpoints.transactionTemplates())
            state = .loaded(rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if state.value == nil { state = .failed(apiError) }
        }
    }

    func delete(_ template: TransactionTemplate, client: APIClient?) async throws {
        guard let client else { return }
        _ = try await client.send(Endpoints.deleteTransactionTemplate(id: template.id))
        state = .loaded(templates.filter { $0.id != template.id })
    }

    func replace(_ template: TransactionTemplate) {
        var rows = templates.filter { $0.id != template.id }
        rows.append(template)
        state = .loaded(rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
}

/// Lists templates to apply to the new-transaction form.
struct TransactionTemplatePickerScreen: View {
    let onApply: (TransactionTemplate) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var model = TransactionTemplatesModel()

    var body: some View {
        List {
            switch model.state {
            case .idle, .loading:
                TransactionTemplateRowsPlaceholder()
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await model.load(client: services.client) }
            case .loaded(let templates):
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "doc.on.doc",
                        description: Text("Save a transaction as a template to reuse its details.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(templates) { template in
                        Button {
                            onApply(template)
                            dismiss()
                        } label: {
                            TransactionTemplateRow(template: template)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Manage") {
                    TransactionTemplatesScreen()
                }
            }
        }
        .task { await model.load(client: services.client) }
        .refreshable { await model.load(client: services.client) }
    }
}

/// Manage templates: edit and delete.
struct TransactionTemplatesScreen: View {
    @Environment(AppServices.self) private var services
    @State private var model = TransactionTemplatesModel()
    @State private var editing: TransactionTemplate?
    @State private var pendingDelete: TransactionTemplate?
    @State private var errorAlert: ErrorAlert?

    var body: some View {
        List {
            switch model.state {
            case .idle, .loading:
                TransactionTemplateRowsPlaceholder()
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await model.load(client: services.client) }
            case .loaded(let templates):
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "doc.on.doc",
                        description: Text("In the transaction form, choose Save as Template to create one.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(templates) { template in
                        Button {
                            editing = template
                        } label: {
                            TransactionTemplateRow(template: template)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDelete = template
                            }
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editing = template }
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = template }
                        }
                    }
                }
            }
        }
        .navigationTitle("Templates")
        .task { await model.load(client: services.client) }
        .refreshable { await model.load(client: services.client) }
        .sheet(item: $editing) { template in
            TransactionTemplateFormSheet(template: template) { saved in
                model.replace(saved)
            }
        }
        .confirmationDialog(
            "Delete this template?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { template in
            Button("Delete Template", role: .destructive) {
                Task {
                    do {
                        try await model.delete(template, client: services.client)
                    } catch {
                        errorAlert = ErrorAlert(error)
                    }
                }
            }
        } message: { template in
            Text(verbatim: template.name)
        }
        .errorAlert($errorAlert)
    }
}

/// Edits every field of a saved template.
struct TransactionTemplateFormSheet: View {
    let template: TransactionTemplate
    let onSaved: (TransactionTemplate) -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var type: TransactionType
    @State private var amountText: String
    @State private var accountId: String?
    @State private var categoryId: String?
    @State private var paymentType: PaymentType?
    @State private var note: String
    @State private var isSaving = false
    @State private var errorAlert: ErrorAlert?

    init(template: TransactionTemplate, onSaved: @escaping (TransactionTemplate) -> Void) {
        self.template = template
        self.onSaved = onSaved
        _name = State(initialValue: template.name)
        _type = State(initialValue: template.transactionType == .income ? .income : .expense)
        _amountText = State(initialValue: template.amount.map(EditorAmountParser.text) ?? "")
        _accountId = State(initialValue: template.accountId)
        _categoryId = State(initialValue: template.categoryId)
        _paymentType = State(initialValue: template.paymentType)
        _note = State(initialValue: template.note ?? "")
    }

    private var amount: Decimal? { EditorAmountParser.parse(amountText) }

    private var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Enter a name.") }
        if !amountText.isEmpty, amount == nil { return String(localized: "Enter a valid amount.") }
        if amount != nil, accountId == nil { return String(localized: "A template with an amount needs an account.") }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        Text("Expense").tag(TransactionType.expense)
                        Text("Income").tag(TransactionType.income)
                    }
                    LabeledContent("Amount") {
                        TextField("Optional", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }
                Section {
                    Picker("Account", selection: $accountId) {
                        Text("None").tag(String?.none)
                        ForEach(referenceData.activeAccounts) { account in
                            Text(verbatim: account.name).tag(String?.some(account.id))
                        }
                    }
                    NavigationLink {
                        TransactionCategoryPicker(isSelected: { $0 == categoryId }, onSelect: { categoryId = $0.id })
                    } label: {
                        LabeledContent("Category", value: referenceData.category(id: categoryId)?.name ?? String(localized: "None"))
                    }
                    Picker("Payment Type", selection: $paymentType) {
                        Text("None").tag(PaymentType?.none)
                        ForEach(TransactionPaymentTypeLabel.selectable, id: \.self) { type in
                            Text(TransactionPaymentTypeLabel.title(type)).tag(PaymentType?.some(type))
                        }
                    }
                }
                Section("Note") {
                    TextField("Add a note", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                if let message = validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(validationMessage != nil)
                    }
                }
            }
            .errorAlert($errorAlert)
        }
    }

    private func save() async {
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = TransactionTemplateRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            transactionType: type,
            amount: amount,
            accountId: accountId,
            categoryId: categoryId,
            payeeId: template.payeeId,
            paymentType: paymentType,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            originalCurrencyCode: template.originalCurrencyCode,
            tagIds: template.tagIds
        )
        do {
            let saved = try await client.send(Endpoints.updateTransactionTemplate(id: template.id, request))
            onSaved(saved)
            dismiss()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

private struct TransactionTemplateRow: View {
    let template: TransactionTemplate
    @Environment(ReferenceDataStore.self) private var referenceData

    var body: some View {
        let category = referenceData.category(id: template.categoryId)
        let account = referenceData.account(id: template.accountId)
        HStack(spacing: 12) {
            CategoryIcon(category: category, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: template.name)
                    .foregroundStyle(.primary)
                Text(verbatim: [category?.name, account?.name].compactMap(\.self).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let amount = template.amount, let code = account?.currencyCode {
                AmountText(template.transactionType == .expense ? -amount : amount, currencyCode: code, digits: referenceData.digits(for: code))
                    .font(.subheadline)
            }
        }
        .contentShape(.rect)
    }
}

private struct TransactionTemplateRowsPlaceholder: View {
    var body: some View {
        ForEach(0..<4, id: \.self) { _ in
            HStack(spacing: 12) {
                Circle().frame(width: 32, height: 32)
                VStack(alignment: .leading) {
                    Text(verbatim: "Template name")
                    Text(verbatim: "Category · Account").font(.footnote)
                }
            }
            .redacted(reason: .placeholder)
        }
    }
}
