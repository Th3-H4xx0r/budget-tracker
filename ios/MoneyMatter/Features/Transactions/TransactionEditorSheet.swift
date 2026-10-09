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
        var accounts = referenceData.activeAccounts.filter(\.isSystem)
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
            let rows = try await model.save(referenceData: referenceData, service: services.transactions)
            TransactionChangeFeed.shared.publish(model.changesTransferShape ? .invalidated : .saved(rows))
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
