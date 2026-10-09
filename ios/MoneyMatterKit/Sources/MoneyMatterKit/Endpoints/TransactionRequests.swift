import Foundation

/// `POST /transactions` body. `amount` is always positive; `transactionType` gives the
/// direction. Nil fields are omitted.
public struct TransactionCreateRequest: Encodable, Sendable, Hashable {
    public var amount: Decimal
    public var transactionType: TransactionType
    public var paymentType: PaymentType
    public var accountId: String
    public var transferNature: TransferNature
    /// Required for normal transactions; must be nil for transfers.
    public var categoryId: String?
    /// Transfers between the user's accounts only.
    public var destinationAccountId: String?
    /// In the destination currency; equals `amount` for a same-currency transfer.
    public var destinationAmount: Decimal?
    /// Defaults to now on the server.
    public var time: Date?
    public var note: String?
    public var payeeId: String?
    public var payeeLocked: Bool?
    /// `[]` skips the payee's default tags; nil applies them.
    public var tagIds: [String]?
    public var isPlanned: Bool?

    public init(
        amount: Decimal,
        transactionType: TransactionType,
        accountId: String,
        transferNature: TransferNature = .notTransfer,
        paymentType: PaymentType = .creditCard,
        categoryId: String? = nil,
        destinationAccountId: String? = nil,
        destinationAmount: Decimal? = nil,
        time: Date? = nil,
        note: String? = nil,
        payeeId: String? = nil,
        payeeLocked: Bool? = nil,
        tagIds: [String]? = nil,
        isPlanned: Bool? = nil
    ) {
        self.amount = amount
        self.transactionType = transactionType
        self.accountId = accountId
        self.transferNature = transferNature
        self.paymentType = paymentType
        self.categoryId = categoryId
        self.destinationAccountId = destinationAccountId
        self.destinationAmount = destinationAmount
        self.time = time
        self.note = note
        self.payeeId = payeeId
        self.payeeLocked = payeeLocked
        self.tagIds = tagIds
        self.isPlanned = isPlanned
    }

    /// A transfer between two of the user's accounts. The source leg is sent as an expense.
    public static func transfer(
        amount: Decimal,
        fromAccountId: String,
        toAccountId: String,
        destinationAmount: Decimal,
        time: Date? = nil,
        note: String? = nil,
        tagIds: [String]? = nil
    ) -> TransactionCreateRequest {
        TransactionCreateRequest(
            amount: amount,
            transactionType: .expense,
            accountId: fromAccountId,
            transferNature: .betweenUserAccounts,
            paymentType: .bankTransfer,
            destinationAccountId: toAccountId,
            destinationAmount: destinationAmount,
            time: time,
            note: note,
            tagIds: tagIds
        )
    }
}

/// A field in an update body: left out, sent as `null` to clear it, or set.
public enum FieldUpdate<Value: Encodable & Sendable & Hashable>: Sendable, Hashable {
    case unchanged
    case clear
    case set(Value)
}

/// `PUT /transactions/:id` body. Every field is optional; `.clear` sends `null`, which the
/// server accepts for `note`, `payeeId`, and `tagIds`. `categoryId` can't be cleared.
public struct TransactionUpdateRequest: Encodable, Sendable, Hashable {
    public var amount: Decimal?
    public var transactionType: TransactionType?
    public var paymentType: PaymentType?
    public var accountId: String?
    public var transferNature: TransferNature?
    public var categoryId: String?
    public var destinationAccountId: String?
    public var destinationAmount: Decimal?
    public var time: Date?
    public var note: FieldUpdate<String>
    public var payeeId: FieldUpdate<String>
    public var payeeLocked: Bool?
    public var tagIds: FieldUpdate<[String]>

    public init(
        amount: Decimal? = nil,
        transactionType: TransactionType? = nil,
        paymentType: PaymentType? = nil,
        accountId: String? = nil,
        transferNature: TransferNature? = nil,
        categoryId: String? = nil,
        destinationAccountId: String? = nil,
        destinationAmount: Decimal? = nil,
        time: Date? = nil,
        note: FieldUpdate<String> = .unchanged,
        payeeId: FieldUpdate<String> = .unchanged,
        payeeLocked: Bool? = nil,
        tagIds: FieldUpdate<[String]> = .unchanged
    ) {
        self.amount = amount
        self.transactionType = transactionType
        self.paymentType = paymentType
        self.accountId = accountId
        self.transferNature = transferNature
        self.categoryId = categoryId
        self.destinationAccountId = destinationAccountId
        self.destinationAmount = destinationAmount
        self.time = time
        self.note = note
        self.payeeId = payeeId
        self.payeeLocked = payeeLocked
        self.tagIds = tagIds
    }

    private enum CodingKeys: String, CodingKey {
        case amount, transactionType, paymentType, accountId, transferNature, categoryId
        case destinationAccountId, destinationAmount, time, note, payeeId, payeeLocked, tagIds
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(transactionType, forKey: .transactionType)
        try container.encodeIfPresent(paymentType, forKey: .paymentType)
        try container.encodeIfPresent(accountId, forKey: .accountId)
        try container.encodeIfPresent(transferNature, forKey: .transferNature)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(destinationAccountId, forKey: .destinationAccountId)
        try container.encodeIfPresent(destinationAmount, forKey: .destinationAmount)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encode(note, forKey: .note)
        try container.encode(payeeId, forKey: .payeeId)
        try container.encodeIfPresent(payeeLocked, forKey: .payeeLocked)
        try container.encode(tagIds, forKey: .tagIds)
    }
}

extension KeyedEncodingContainer {
    fileprivate mutating func encode<Value>(_ update: FieldUpdate<Value>, forKey key: Key) throws {
        switch update {
        case .unchanged:
            break
        case .clear:
            try encodeNil(forKey: key)
        case .set(let value):
            try encode(value, forKey: key)
        }
    }
}
