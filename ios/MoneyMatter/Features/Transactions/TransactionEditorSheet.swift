import MoneyMatterKit
import SwiftUI

/// Creates or edits a transaction: expense, income, or a transfer between the user's accounts.
struct TransactionEditorSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var model: TransactionEditorModel
    @State private var errorAlert: ErrorAlert?
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var isPickingTemplate = false
    @State private var isManagingTemplates = false
    @State private var isNamingTemplate = false
    @State private var templateName = ""
    @State private var savedTemplateName: String?
    @State private var isAttachmentUploadFailed = false
    @FocusState private var isAmountFocused: Bool

    init(mode: TransactionEditorModel.Mode) {
        _model = State(initialValue: TransactionEditorModel(mode: mode))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $model.kind.animation()) {
                        ForEach(TransactionEditorModel.Kind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.keepsTransferNature)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    amountField
                }

                accountSection

                if model.showsCategory {
                    Section {
                        NavigationLink {
                            TransactionCategoryPicker(
                                isSelected: { $0 == model.categoryId },
                                onSelect: { model.categoryId = $0.id }
                            )
                        } label: {
                            LabeledContent("Category") {
                                if let category = referenceData.category(id: model.categoryId) {
                                    HStack(spacing: 8) {
                                        CategoryIcon(category: category, size: 22)
                                        Text(category.name)
                                    }
                                } else {
                                    Text("Choose")
                                }
                            }
                        }
                    }
                }

                if model.showsSplits {
                    TransactionSplitsSection(model: model, currencyCode: model.currencyCode(in: referenceData))
                }

                Section {
                    DatePicker("Date", selection: $model.time, displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    NavigationLink {
                        TransactionPayeePicker(selectedId: model.payeeId) { payee in
                            model.payeeId = payee?.id
                            if let payee { referenceData.upsert(payee) }
                        }
                    } label: {
                        LabeledContent("Payee", value: referenceData.payee(id: model.payeeId)?.name ?? String(localized: "None"))
                    }
                    NavigationLink {
                        TransactionTagsPicker(selection: $model.tagIds)
                    } label: {
                        LabeledContent("Tags", value: tagsSummary)
                    }
                }

                Section("Note") {
                    TextField("Add a note", text: $model.note, axis: .vertical)
                        .lineLimit(1...6)
                }

                TransactionDetailsFieldsSection(model: model)

                if let transaction = model.editedTransaction {
                    TransactionAttachmentsSection(transactionId: transaction.id, canEdit: transaction.canEdit ?? true)
                } else {
                    TransactionPendingAttachmentsSection(model: model)
                }

                if let message = model.validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }

                if model.isEditing {
                    Section {
                        Button("Delete Transaction", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .disabled(isDeleting || model.isSaving)
                    }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Transaction" : "New Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    templatesMenu
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(isDeleting)
                    }
                }
            }
            .task {
                do {
                    try await model.prepare(referenceData: referenceData, service: services.transactions)
                } catch {
                    errorAlert = ErrorAlert(error)
                }
                if !model.isEditing { isAmountFocused = true }
                await model.loadDetails(client: services.client)
            }
            .navigationDestination(isPresented: $isPickingTemplate) {
                TransactionTemplatePickerScreen { template in
                    withAnimation { model.apply(template) }
                }
            }
            .navigationDestination(isPresented: $isManagingTemplates) {
                TransactionTemplatesScreen()
            }
            .alert("Save as Template", isPresented: $isNamingTemplate) {
                TextField("Template name", text: $templateName)
                Button("Save") { Task { await saveTemplate() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The type, amount, account, category, payee, payment type, note, and tags are saved.")
            }
            .alert("Transaction Saved", isPresented: $isAttachmentUploadFailed) {
                Button("OK") { dismiss() }
            } message: {
                Text("Some attachments couldn't be uploaded. Add them again from the transaction's details.")
            }
            .alert(
                "Template Saved",
                isPresented: Binding(get: { savedTemplateName != nil }, set: { if !$0 { savedTemplateName = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: savedTemplateName ?? "")
            }
            .confirmationDialog("Delete this transaction?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Transaction", role: .destructive) {
                    Task { await delete() }
                }
            } message: {
                Text(model.editedTransaction?.transferId != nil
                    ? "Both sides of the transfer are deleted. This can't be undone."
                    : "This can't be undone.")
            }
            .errorAlert($errorAlert)
            .interactiveDismissDisabled(model.isSaving || isDeleting)
        }
    }

    private var templatesMenu: some View {
        Menu("Templates", systemImage: "doc.on.doc") {
            if !model.isEditing {
                Button("Apply Template", systemImage: "square.and.arrow.down") { isPickingTemplate = true }
            }
            if model.kind != .transfer, !model.keepsTransferNature {
                Button("Save as Template", systemImage: "square.and.arrow.up") {
                    templateName = ""
                    isNamingTemplate = true
                }
            }
            Button("Manage Templates", systemImage: "list.bullet") { isManagingTemplates = true }
        }
    }

    private func saveTemplate() async {
        let name = templateName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let client = services.client else { return }
        do {
            let template = try await client.send(Endpoints.createTransactionTemplate(model.templateRequest(name: String(name.prefix(100)))))
            savedTemplateName = template.name
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private var amountField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: model.currencyCode(in: referenceData).map { MoneyFormat.symbol(for: $0) } ?? "")
                .font(.title.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("0", text: $model.amountText)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .keyboardType(.decimalPad)
                .focused($isAmountFocused)
                .minimumScaleFactor(0.5)
                .accessibilityLabel("Amount")
        }
        .disabled(model.isExternal)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if model.isExternal {
                LabeledContent("Account", value: referenceData.account(id: model.accountId)?.name ?? "")
            } else {
                accountPicker(model.kind == .transfer ? "From" : "Account", selection: $model.accountId)
            }
            if model.kind == .transfer {
                accountPicker("To", selection: $model.destinationAccountId)
                if model.needsDestinationAmount(in: referenceData) {
                    LabeledContent("Amount Received") {
                        HStack(spacing: 4) {
                            TextField("0", text: $model.destinationAmountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                            Text(verbatim: model.destinationCurrencyCode(in: referenceData) ?? "")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } footer: {
            if !model.isExternal {
                Text("Only manually managed accounts can take new transactions.")
            }
        }
    }

    private func accountPicker(_ title: LocalizedStringKey, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("Choose").tag(String?.none)
            ForEach(selectableAccounts) { account in
                Text(verbatim: "\(account.name) (\(account.currencyCode))").tag(String?.some(account.id))
            }
        }
    }

    /// Active system accounts, plus the edited row's own account so the picker can show it.
    private var selectableAccounts: [Account] {
        // Plans may sit on bank-connected accounts; real rows there come from the sync.
        var accounts = referenceData.activeAccounts.filter { $0.isSystem || (model.isPlanned && model.kind != .transfer) }
        for id in [model.editedTransaction?.accountId, model.destinationAccountId].compactMap(\.self)
        where !accounts.contains(where: { $0.id == id }) {
            if let account = referenceData.account(id: id) { accounts.append(account) }
        }
        return accounts
    }

    private var tagsSummary: String {
        let names = model.tagIds.compactMap { referenceData.tag(id: $0)?.name }.sorted()
        if names.isEmpty { return String(localized: "None") }
        return names.count <= 2 ? names.formatted(.list(type: .and)) : String(localized: "\(names.count) tags")
    }

    private func save() async {
        if let message = model.validate(referenceData: referenceData) {
            withAnimation { model.validationMessage = message }
            return
        }
        model.validationMessage = nil
        do {
            let rows = try await model.save(referenceData: referenceData, service: services.transactions, client: services.client)
            let uploaded = await uploadPendingAttachments(to: rows)
            TransactionChangeFeed.shared.publish(model.changesTransferShape ? .invalidated : .saved(rows))
            guard uploaded else {
                isAttachmentUploadFailed = true
                return
            }
            dismiss()
            await referenceData.refreshAccounts()
        } catch {
            let apiError = APIError(error)
            if case .validation = apiError {
                withAnimation { model.validationMessage = ErrorMessage.message(for: apiError) }
            } else {
                errorAlert = ErrorAlert(error)
            }
        }
    }

    /// Uploads files picked before the transaction existed. A failed upload is reported, but
    /// the transaction itself is already saved.
    private func uploadPendingAttachments(to rows: [Transaction]) async -> Bool {
        guard !model.pendingAttachments.isEmpty, let client = services.client,
              let target = rows.first(where: { $0.accountId == model.accountId }) ?? rows.first else { return true }
        var allUploaded = true
        for file in model.pendingAttachments {
            do {
                _ = try await client.uploadTransactionAttachment(
                    TransactionAttachmentUpload(transactionId: target.id, filename: file.filename, data: file.data)
                )
            } catch {
                allUploaded = false
            }
        }
        model.pendingAttachments = []
        return allUploaded
    }

    private func delete() async {
        guard let transaction = model.editedTransaction else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await services.transactions.deleteTransaction(id: transaction.id)
            TransactionChangeFeed.shared.publish(.deleted(id: transaction.id, transferId: transaction.transferId))
            dismiss()
            await referenceData.refreshAccounts()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}
