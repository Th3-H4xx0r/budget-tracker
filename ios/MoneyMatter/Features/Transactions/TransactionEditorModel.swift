import Foundation
import MoneyMatterKit
import Observation

/// State, validation, and request building for the transaction editor sheet.
@Observable
final class TransactionEditorModel {
    enum Kind: String, CaseIterable, Identifiable {
        case expense
        case income
        case transfer

        var id: Self { self }

        var title: String {
            switch self {
            case .expense: String(localized: "Expense")
            case .income: String(localized: "Income")
            case .transfer: String(localized: "Transfer")
            }
        }
    }

    enum Mode {
        /// A new transaction, optionally on a preselected account.
        case create(accountId: String?)
        case edit(Transaction)
    }

    let mode: Mode
    var kind: Kind = .expense
    var amountText = ""
    var accountId: String?
    var destinationAccountId: String?
    var destinationAmountText = ""
    var categoryId: String?
    var time = Date.now
    var payeeId: String?
    var tagIds: Set<String> = []
    var note = ""
    /// The server's or local validation message, shown under the form.
    var validationMessage: String?
    private(set) var isSaving = false

    @ObservationIgnored private var initialKind: Kind?
    @ObservationIgnored private var initialTagIds: Set<String>?
    @ObservationIgnored private var initialPayeeId: String?
    @ObservationIgnored private var initialNote: String?
    /// The leg a transfer update is sent to: the source (expense) leg.
    @ObservationIgnored private var sourceLegId: String?
    @ObservationIgnored private var hasLoadedLegs = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create(let accountId):
            self.accountId = accountId
        case .edit(let transaction):
            kind = transaction.transferNature.isTwoLegTransfer
                ? .transfer
                : (transaction.transactionType == .income ? .income : .expense)
            initialKind = kind
            amountText = EditorAmountParser.text(transaction.amount)
            accountId = transaction.accountId
            categoryId = transaction.categoryId
            time = transaction.time
            payeeId = transaction.payeeId
            initialPayeeId = transaction.payeeId
            note = transaction.note ?? ""
            initialNote = transaction.note
            if let tags = transaction.tags {
                tagIds = Set(tags.map(\.id))
                initialTagIds = tagIds
            }
        }
    }

    var editedTransaction: Transaction? {
        if case .edit(let transaction) = mode { return transaction }
        return nil
    }

    var isEditing: Bool { editedTransaction != nil }

    /// Rows from bank-connected accounts keep their amount and account.
    var isExternal: Bool {
        editedTransaction.map { $0.accountType != .system } ?? false
    }

    /// Out-of-wallet, portfolio, and venture transfers keep their nature and have no
    /// category; the editor only changes their amount, date, payee, tags, and note.
    var keepsTransferNature: Bool {
        guard let nature = editedTransaction?.transferNature else { return false }
        return nature != .notTransfer && !nature.isTwoLegTransfer
    }

    var showsCategory: Bool { kind != .transfer && !keepsTransferNature }

    var amount: Decimal? { EditorAmountParser.parse(amountText) }

    func currencyCode(in referenceData: ReferenceDataStore) -> String? {
        referenceData.account(id: accountId)?.currencyCode ?? editedTransaction?.currencyCode
    }

    func destinationCurrencyCode(in referenceData: ReferenceDataStore) -> String? {
        referenceData.account(id: destinationAccountId)?.currencyCode
    }

    func needsDestinationAmount(in referenceData: ReferenceDataStore) -> Bool {
        guard kind == .transfer, let source = currencyCode(in: referenceData),
              let destination = destinationCurrencyCode(in: referenceData) else { return false }
        return source != destination
    }

    /// Picks a default account for a new transaction, and loads both legs of an edited
    /// transfer. Throws when the legs can't be loaded; `save` retries before sending.
    func prepare(referenceData: ReferenceDataStore, service: any TransactionsServicing) async throws {
        let systemAccounts = referenceData.activeAccounts.filter(\.isSystem)
        if !isEditing, referenceData.account(id: accountId)?.isSystem != true {
            accountId = systemAccounts.first?.id
        }
        try await loadTransferLegs(service: service, prefillsFields: true)
    }

    /// `prefillsFields` is false when retried at save, so the user's edits aren't replaced.
    private func loadTransferLegs(service: any TransactionsServicing, prefillsFields: Bool) async throws {
        guard !hasLoadedLegs, let transaction = editedTransaction,
              transaction.transferNature.isTwoLegTransfer, let transferId = transaction.transferId else { return }
        let legs = try await service.transferLegs(transferId: transferId)
        hasLoadedLegs = true
        guard legs.count == 2 else {
            sourceLegId = transaction.id
            return
        }
        let source = legs.first { $0.transactionType == .expense } ?? transaction
        let destination = legs.first { $0.id != source.id }
        sourceLegId = source.id
        guard prefillsFields else { return }
        accountId = source.accountId
        amountText = EditorAmountParser.text(source.amount)
        destinationAccountId = destination?.accountId
        destinationAmountText = destination.map { EditorAmountParser.text($0.amount) } ?? ""
    }

    /// A message for the first invalid field, or nil when the form can be saved.
    func validate(referenceData: ReferenceDataStore) -> String? {
        guard let amount, amount > 0 else { return String(localized: "Enter an amount greater than zero.") }
        guard accountId != nil else { return String(localized: "Choose an account.") }
        if kind == .transfer {
            guard let destinationAccountId else { return String(localized: "Choose the account the money goes to.") }
            guard destinationAccountId != accountId else { return String(localized: "Choose two different accounts.") }
            if needsDestinationAmount(in: referenceData) {
                guard let received = EditorAmountParser.parse(destinationAmountText), received > 0 else {
                    return String(localized: "Enter the amount received.")
                }
            }
        } else if showsCategory, categoryId == nil, !isEditing || kind != initialKind {
            // Legacy rows without a category can still be edited as long as the type stays.
            return String(localized: "Choose a category.")
        }
        if note.count > 1000 { return String(localized: "The note can be at most 1,000 characters.") }
        return nil
    }

    /// Sends the create or update and returns the saved rows (one, or both transfer legs).
    func save(referenceData: ReferenceDataStore, service: any TransactionsServicing) async throws -> [Transaction] {
        isSaving = true
        defer { isSaving = false }
        try await loadTransferLegs(service: service, prefillsFields: false)
        let digits = referenceData.digits(for: currencyCode(in: referenceData)) ?? 2
        let amount = MoneyFormat.rounded(amount ?? 0, digits: digits)
        let destinationAmount = resolvedDestinationAmount(sourceAmount: amount, referenceData: referenceData)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let transaction = editedTransaction else {
            return try await service.createTransaction(
                makeCreateRequest(amount: amount, destinationAmount: destinationAmount, note: trimmedNote)
            )
        }
        var request = TransactionUpdateRequest()
        if !isExternal {
            request.amount = amount
            request.accountId = accountId
        }
        request.time = time
        if trimmedNote != (initialNote ?? "") {
            request.note = trimmedNote.isEmpty ? .clear : .set(trimmedNote)
        }
        if payeeId != initialPayeeId {
            request.payeeId = payeeId.map { .set($0) } ?? .clear
        }
        if tagIds != (initialTagIds ?? []) {
            request.tagIds = .set(tagIds.sorted())
        }
        if !keepsTransferNature {
            switch kind {
            case .transfer:
                request.transferNature = .betweenUserAccounts
                request.transactionType = .expense
                request.destinationAccountId = destinationAccountId
                request.destinationAmount = destinationAmount
            case .expense, .income:
                request.transferNature = .notTransfer
                request.transactionType = kind == .income ? .income : .expense
                request.categoryId = categoryId
            }
        }
        return try await service.updateTransaction(id: sourceLegId ?? transaction.id, request)
    }

    /// Whether the save changed which legs exist, so lists must reload rather than patch.
    var changesTransferShape: Bool {
        guard let transaction = editedTransaction else { return false }
        return transaction.transferNature.isTwoLegTransfer != (kind == .transfer)
    }

    private func resolvedDestinationAmount(sourceAmount: Decimal, referenceData: ReferenceDataStore) -> Decimal? {
        guard kind == .transfer else { return nil }
        guard needsDestinationAmount(in: referenceData) else { return sourceAmount }
        let digits = referenceData.digits(for: destinationCurrencyCode(in: referenceData)) ?? 2
        return EditorAmountParser.parse(destinationAmountText).map { MoneyFormat.rounded($0, digits: digits) }
    }

    private func makeCreateRequest(amount: Decimal, destinationAmount: Decimal?, note: String) -> TransactionCreateRequest {
        let tags = tagIds.isEmpty ? nil : tagIds.sorted()
        if kind == .transfer {
            var request = TransactionCreateRequest.transfer(
                amount: amount,
                fromAccountId: accountId ?? "",
                toAccountId: destinationAccountId ?? "",
                destinationAmount: destinationAmount ?? amount,
                time: time,
                note: note.isEmpty ? nil : note,
                tagIds: tags
            )
            request.payeeId = payeeId
            return request
        }
        return TransactionCreateRequest(
            amount: amount,
            transactionType: kind == .income ? .income : .expense,
            accountId: accountId ?? "",
            transferNature: .notTransfer,
            categoryId: categoryId,
            time: time,
            note: note.isEmpty ? nil : note,
            payeeId: payeeId,
            tagIds: tags
        )
    }
}
