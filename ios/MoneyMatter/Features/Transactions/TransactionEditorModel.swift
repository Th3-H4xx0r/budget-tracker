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
    var paymentType: PaymentType = .creditCard
    var isPlanned = false
    var splits: [SplitRow] = []
    var originalAmountText = ""
    var originalCurrencyCode: String?
    var location: TransactionLocation?
    /// The transaction this one refunds ("Mark as refund of").
    var refundOf: Transaction?
    /// Files picked before the transaction exists; uploaded right after it's created.
    var pendingAttachments: [PendingAttachment] = []
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
    @ObservationIgnored private var initialPaymentType: PaymentType?
    @ObservationIgnored private var initialIsPlanned = false
    @ObservationIgnored private var initialSplits: [TransactionSplitInput] = []
    @ObservationIgnored private var initialOriginalAmount: Decimal?
    @ObservationIgnored private var initialOriginalCurrencyCode: String?
    @ObservationIgnored private var initialLocation: TransactionLocation?
    @ObservationIgnored private var initialRefundOfId: String?
    @ObservationIgnored private var hasLoadedDetails = false

    static let maxSplits = 10

    /// One editable split row.
    struct SplitRow: Identifiable, Equatable {
        let id = UUID()
        var categoryId: String?
        var amountText = ""
        var note = ""
    }

    /// A file waiting to be uploaded once the new transaction is saved.
    struct PendingAttachment: Identifiable, Equatable {
        let id = UUID()
        let filename: String
        let data: Data
    }

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
            paymentType = transaction.paymentType == .unknown ? .creditCard : transaction.paymentType
            initialPaymentType = paymentType
            isPlanned = transaction.isPlanned
            initialIsPlanned = transaction.isPlanned
            originalAmountText = transaction.originalAmount.map(EditorAmountParser.text) ?? ""
            initialOriginalAmount = transaction.originalAmount
            originalCurrencyCode = transaction.originalCurrencyCode
            initialOriginalCurrencyCode = transaction.originalCurrencyCode
            location = transaction.location
            initialLocation = transaction.location
            if let splits = transaction.splits { fillSplits(splits) }
        }
    }

    private func fillSplits(_ rows: [TransactionSplit]) {
        splits = rows.map { SplitRow(categoryId: $0.categoryId, amountText: EditorAmountParser.text($0.amount), note: $0.note ?? "") }
        initialSplits = splitInputs
    }

    /// Valid-looking split rows as request inputs. Rows without a category or amount are left out.
    var splitInputs: [TransactionSplitInput] {
        splits.compactMap { row in
            guard let categoryId = row.categoryId, let amount = EditorAmountParser.parse(row.amountText), amount > 0 else { return nil }
            let note = row.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return TransactionSplitInput(categoryId: categoryId, amount: amount, note: note.isEmpty ? nil : note)
        }
    }

    var splitsTotal: Decimal {
        splits.reduce(0) { $0 + (EditorAmountParser.parse($1.amountText) ?? 0) }
    }

    /// What stays on the main category after the splits.
    var remainingAfterSplits: Decimal { (amount ?? 0) - splitsTotal }

    var canAddSplit: Bool { splits.count < Self.maxSplits }

    var showsSplits: Bool { showsCategory }

    /// New income and expense rows can be plans. On a saved row the toggle only appears for a
    /// plan, so it can be marked as done; a real row can't become a plan again.
    var showsPlannedToggle: Bool {
        kind != .transfer && !keepsTransferNature && (!isEditing || initialIsPlanned)
    }

    /// Refund links apply to income and expense rows only.
    var showsRefund: Bool { kind != .transfer && !keepsTransferNature }

    /// Fills the form from a template. Nil template fields keep the current value.
    func apply(_ template: TransactionTemplate) {
        switch template.transactionType {
        case .income: kind = .income
        case .expense: kind = .expense
        case .unknown: break
        }
        if let amount = template.amount { amountText = EditorAmountParser.text(amount) }
        if let accountId = template.accountId { self.accountId = accountId }
        if let categoryId = template.categoryId { self.categoryId = categoryId }
        if let payeeId = template.payeeId { self.payeeId = payeeId }
        if let paymentType = template.paymentType, paymentType != .unknown { self.paymentType = paymentType }
        if let note = template.note { self.note = note }
        if let code = template.originalCurrencyCode { originalCurrencyCode = code }
        if !template.tagIds.isEmpty { tagIds = Set(template.tagIds) }
    }

    /// The current form as a template body.
    func templateRequest(name: String) -> TransactionTemplateRequest {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return TransactionTemplateRequest(
            name: name,
            transactionType: kind == .income ? .income : .expense,
            amount: amount.flatMap { $0 > 0 ? $0 : nil },
            accountId: accountId,
            categoryId: categoryId,
            payeeId: payeeId,
            paymentType: paymentType,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            originalCurrencyCode: originalCurrencyCode,
            tagIds: tagIds.sorted()
        )
    }

    /// Loads splits and the refund link of an edited row, which list rows don't carry.
    func loadDetails(client: APIClient?) async {
        guard !hasLoadedDetails, let client, let transaction = editedTransaction else { return }
        hasLoadedDetails = true
        if transaction.splits == nil, !transaction.isTransfer,
           let fresh = try? await client.send(Endpoints.transactionWithSplits(id: transaction.id)),
           let rows = fresh.splits, splits.isEmpty {
            fillSplits(rows)
        }
        if transaction.refundLinked, !transaction.isTransfer,
           let links = try? await client.send(Endpoints.transactionRefunds(transactionId: transaction.id)),
           let link = links.first(where: { $0.refundTxId == transaction.id }), refundOf == nil {
            refundOf = link.originalTransaction
            initialRefundOfId = link.originalTxId
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
        if showsSplits, !splits.isEmpty {
            if let message = validateSplits() { return message }
        }
        if !originalAmountText.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let original = EditorAmountParser.parse(originalAmountText), original >= 0 else {
                return String(localized: "Enter a valid original amount.")
            }
            guard originalCurrencyCode != nil else { return String(localized: "Choose the original currency.") }
        }
        return nil
    }

    private func validateSplits() -> String? {
        if splits.count > Self.maxSplits { return String(localized: "A transaction can have at most 10 splits.") }
        var seen: Set<String> = []
        for row in splits {
            guard let categoryId = row.categoryId else { return String(localized: "Choose a category for each split.") }
            guard let amount = EditorAmountParser.parse(row.amountText), amount > 0 else {
                return String(localized: "Enter an amount greater than zero for each split.")
            }
            if categoryId == self.categoryId { return String(localized: "A split can't use the transaction's own category.") }
            guard seen.insert(categoryId).inserted else { return String(localized: "Each split needs a different category.") }
            if row.note.count > 100 { return String(localized: "A split note can be at most 100 characters.") }
        }
        if remainingAfterSplits < 0 { return String(localized: "The splits add up to more than the transaction amount.") }
        return nil
    }

    /// Sends the create or update and returns the saved rows (one, or both transfer legs).
    func save(referenceData: ReferenceDataStore, service: any TransactionsServicing, client: APIClient?) async throws -> [Transaction] {
        isSaving = true
        defer { isSaving = false }
        try await loadTransferLegs(service: service, prefillsFields: false)
        let digits = referenceData.digits(for: currencyCode(in: referenceData)) ?? 2
        let amount = MoneyFormat.rounded(amount ?? 0, digits: digits)
        let destinationAmount = resolvedDestinationAmount(sourceAmount: amount, referenceData: referenceData)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let transaction = editedTransaction else {
            let base = makeCreateRequest(amount: amount, destinationAmount: destinationAmount, note: trimmedNote)
            guard let client else { return try await service.createTransaction(base) }
            return try await client.send(Endpoints.createTransactionAdvanced(makeAdvancedCreate(base: base)))
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
        let advanced = makeAdvancedUpdate(base: request)
        guard let client else { return try await service.updateTransaction(id: sourceLegId ?? transaction.id, request) }
        return try await client.send(Endpoints.updateTransactionAdvanced(id: sourceLegId ?? transaction.id, advanced))
    }

    private var parsedOriginalAmount: Decimal? {
        EditorAmountParser.parse(originalAmountText)
    }

    private func makeAdvancedCreate(base: TransactionCreateRequest) -> TransactionAdvancedCreateRequest {
        var base = base
        let isTransfer = kind == .transfer
        if !isTransfer {
            base.paymentType = paymentType
            base.isPlanned = isPlanned ? true : nil
        }
        let hasOriginal = parsedOriginalAmount != nil && originalCurrencyCode != nil
        return TransactionAdvancedCreateRequest(
            base: base,
            splits: showsSplits ? splitInputs : nil,
            refundForTxId: showsRefund ? refundOf?.id : nil,
            originalAmount: hasOriginal ? parsedOriginalAmount : nil,
            originalCurrencyCode: hasOriginal ? originalCurrencyCode : nil,
            location: location
        )
    }

    private func makeAdvancedUpdate(base: TransactionUpdateRequest) -> TransactionAdvancedUpdateRequest {
        var base = base
        var request = TransactionAdvancedUpdateRequest()
        if kind != .transfer, !keepsTransferNature, paymentType != initialPaymentType {
            base.paymentType = paymentType
        }
        if showsSplits, splitInputs != initialSplits {
            request.splits = splitInputs.isEmpty ? .clear : .set(splitInputs)
        } else if !showsSplits, !initialSplits.isEmpty {
            request.splits = .clear
        }
        if showsPlannedToggle, isPlanned != initialIsPlanned {
            request.isPlanned = isPlanned
        }
        if showsRefund, refundOf?.id != initialRefundOfId {
            request.refundsTxId = refundOf.map { .set($0.id) } ?? .clear
        }
        let original = parsedOriginalAmount
        let code = original == nil ? nil : originalCurrencyCode
        if original != initialOriginalAmount || code != initialOriginalCurrencyCode {
            request.originalAmount = original.map { .set($0) } ?? .clear
            request.originalCurrencyCode = code.map { .set($0) } ?? .clear
        }
        if location != initialLocation {
            request.location = location.map { .set($0) } ?? .clear
        }
        request.base = base
        return request
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
