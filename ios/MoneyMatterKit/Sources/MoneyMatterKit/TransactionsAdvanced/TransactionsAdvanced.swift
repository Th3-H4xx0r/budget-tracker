import Foundation

/// One split of a transaction: part of the amount booked to another category. The rest stays
/// on the transaction's own category.
public struct TransactionSplitInput: Encodable, Sendable, Hashable {
    public var categoryId: String
    public var amount: Decimal
    public var note: String?

    public init(categoryId: String, amount: Decimal, note: String? = nil) {
        self.categoryId = categoryId
        self.amount = amount
        self.note = note
    }

    private enum CodingKeys: String, CodingKey { case categoryId, amount, note }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

/// `POST /transactions` body with the fields the basic request leaves out: splits, the refund
/// link, the original amount and currency, and the location. Encodes as one flat object.
public struct TransactionAdvancedCreateRequest: Encodable, Sendable, Hashable {
    public var base: TransactionCreateRequest
    /// At most 10; not allowed on transfers.
    public var splits: [TransactionSplitInput]?
    /// The transaction this one refunds. Only for non-transfers.
    public var refundForTxId: String?
    public var originalAmount: Decimal?
    public var originalCurrencyCode: String?
    public var location: TransactionLocation?

    public init(
        base: TransactionCreateRequest,
        splits: [TransactionSplitInput]? = nil,
        refundForTxId: String? = nil,
        originalAmount: Decimal? = nil,
        originalCurrencyCode: String? = nil,
        location: TransactionLocation? = nil
    ) {
        self.base = base
        self.splits = splits
        self.refundForTxId = refundForTxId
        self.originalAmount = originalAmount
        self.originalCurrencyCode = originalCurrencyCode
        self.location = location
    }

    private enum CodingKeys: String, CodingKey {
        case splits, refundForTxId, originalAmount, originalCurrencyCode, location
    }

    public func encode(to encoder: any Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let splits, !splits.isEmpty { try container.encode(splits, forKey: .splits) }
        try container.encodeIfPresent(refundForTxId, forKey: .refundForTxId)
        try container.encodeIfPresent(originalAmount, forKey: .originalAmount)
        try container.encodeIfPresent(originalCurrencyCode, forKey: .originalCurrencyCode)
        try container.encodeIfPresent(location, forKey: .location)
    }
}

/// `PUT /transactions/:id` body with the advanced fields. `.clear` sends `null`: for `splits`
/// that removes every split, for `refundsTxId` it unlinks the refund.
public struct TransactionAdvancedUpdateRequest: Encodable, Sendable, Hashable {
    public var base: TransactionUpdateRequest
    public var splits: FieldUpdate<[TransactionSplitInput]>
    public var isPlanned: Bool?
    public var refundsTxId: FieldUpdate<String>
    public var originalAmount: FieldUpdate<Decimal>
    public var originalCurrencyCode: FieldUpdate<String>
    public var location: FieldUpdate<TransactionLocation>

    public init(
        base: TransactionUpdateRequest = TransactionUpdateRequest(),
        splits: FieldUpdate<[TransactionSplitInput]> = .unchanged,
        isPlanned: Bool? = nil,
        refundsTxId: FieldUpdate<String> = .unchanged,
        originalAmount: FieldUpdate<Decimal> = .unchanged,
        originalCurrencyCode: FieldUpdate<String> = .unchanged,
        location: FieldUpdate<TransactionLocation> = .unchanged
    ) {
        self.base = base
        self.splits = splits
        self.isPlanned = isPlanned
        self.refundsTxId = refundsTxId
        self.originalAmount = originalAmount
        self.originalCurrencyCode = originalCurrencyCode
        self.location = location
    }

    private enum CodingKeys: String, CodingKey {
        case splits, isPlanned, refundsTxId, originalAmount, originalCurrencyCode, location
    }

    public func encode(to encoder: any Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeAdvanced(splits, forKey: .splits)
        try container.encodeIfPresent(isPlanned, forKey: .isPlanned)
        try container.encodeAdvanced(refundsTxId, forKey: .refundsTxId)
        try container.encodeAdvanced(originalAmount, forKey: .originalAmount)
        try container.encodeAdvanced(originalCurrencyCode, forKey: .originalCurrencyCode)
        try container.encodeAdvanced(location, forKey: .location)
    }
}

extension KeyedEncodingContainer {
    fileprivate mutating func encodeAdvanced<Value>(_ update: FieldUpdate<Value>, forKey key: Key) throws {
        switch update {
        case .unchanged: break
        case .clear: try encodeNil(forKey: key)
        case .set(let value): try encode(value, forKey: key)
        }
    }
}

// MARK: - Refunds

/// A refund link from `GET /transactions/:id/refunds`. `originalTxId` is nil for a refund
/// whose original isn't tracked.
public struct TransactionRefundLink: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let originalTxId: String?
    public let refundTxId: String
    public let splitId: String?
    public let originalTransaction: Transaction?
    public let refundTransaction: Transaction?

    private enum CodingKeys: String, CodingKey {
        case id, originalTxId, refundTxId, splitId, originalTransaction, refundTransaction
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        originalTxId = try c.decodeIfPresent(String.self, forKey: .originalTxId)
        refundTxId = try c.decode(String.self, forKey: .refundTxId)
        splitId = try c.decodeIfPresent(String.self, forKey: .splitId)
        originalTransaction = try? c.decodeIfPresent(Transaction.self, forKey: .originalTransaction)
        refundTransaction = try? c.decodeIfPresent(Transaction.self, forKey: .refundTransaction)
    }
}

/// `POST` and `DELETE /transactions/refund` body.
public struct TransactionRefundLinkRequest: Encodable, Sendable, Hashable {
    public var originalTxId: String
    public var refundTxId: String

    public init(originalTxId: String, refundTxId: String) {
        self.originalTxId = originalTxId
        self.refundTxId = refundTxId
    }
}

// MARK: - Transfer linking

/// `PUT /transactions/link` body: pairs of `[baseTxId, oppositeTxId]`.
public struct TransactionLinkRequest: Encodable, Sendable, Hashable {
    public var ids: [[String]]

    public init(baseTransactionId: String, oppositeTransactionId: String) {
        ids = [[baseTransactionId, oppositeTransactionId]]
    }
}

/// `PUT /transactions/unlink` body.
public struct TransactionUnlinkRequest: Encodable, Sendable, Hashable {
    public var transferIds: [String]

    public init(transferIds: [String]) {
        self.transferIds = transferIds
    }
}

// MARK: - Bulk

/// `POST /transactions/bulk-delete` body. At most 500 ids.
public struct TransactionBulkDeleteRequest: Encodable, Sendable, Hashable {
    public var transactionIds: [String]

    public init(transactionIds: [String]) {
        self.transactionIds = transactionIds
    }
}

/// `PUT /transactions/bulk` body, used here to set one category on many rows.
public struct TransactionBulkCategoryRequest: Encodable, Sendable, Hashable {
    public var transactionIds: [String]
    public var categoryId: String

    public init(transactionIds: [String], categoryId: String) {
        self.transactionIds = transactionIds
        self.categoryId = categoryId
    }
}

// MARK: - Groups

/// A transaction group from `GET /transaction-groups`.
public struct TransactionGroupSummary: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let note: String?
    public let transactionCount: Int?

    public init(id: String, name: String, note: String? = nil, transactionCount: Int? = nil) {
        self.id = id
        self.name = name
        self.note = note
        self.transactionCount = transactionCount
    }
}

/// `POST /transaction-groups/:id/transactions` body.
public struct TransactionGroupAddRequest: Encodable, Sendable, Hashable {
    public var transactionIds: [String]

    public init(transactionIds: [String]) {
        self.transactionIds = transactionIds
    }
}

/// `POST /transaction-groups` body. A new group needs 2 to 50 transactions.
public struct TransactionGroupCreateRequest: Encodable, Sendable, Hashable {
    public var name: String
    public var transactionIds: [String]

    public init(name: String, transactionIds: [String]) {
        self.name = name
        self.transactionIds = transactionIds
    }
}

// MARK: - Templates

/// A saved transaction template. Nil fields leave the form's current value alone.
public struct TransactionTemplate: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let transactionType: TransactionType
    public let amount: Decimal?
    public let accountId: String?
    public let categoryId: String?
    public let payeeId: String?
    public let paymentType: PaymentType?
    public let note: String?
    public let originalCurrencyCode: String?
    public let tagIds: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, transactionType, amount, accountId, categoryId, payeeId, paymentType, note
        case originalCurrencyCode, tagIds
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        transactionType = try c.decodeLenient(TransactionType.self, forKey: .transactionType, default: .unknown)
        amount = try c.decodeIfPresent(Decimal.self, forKey: .amount)
        accountId = try c.decodeIfPresent(String.self, forKey: .accountId)
        categoryId = try c.decodeIfPresent(String.self, forKey: .categoryId)
        payeeId = try c.decodeIfPresent(String.self, forKey: .payeeId)
        paymentType = try? c.decodeIfPresent(PaymentType.self, forKey: .paymentType)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        originalCurrencyCode = try c.decodeIfPresent(String.self, forKey: .originalCurrencyCode)
        tagIds = (try? c.decodeIfPresent([String].self, forKey: .tagIds)) ?? []
    }
}

/// `POST /transaction-templates` and `PUT /transaction-templates/:id` body. Every field is
/// sent; nil goes out as `null`, so an update clears what the user removed.
public struct TransactionTemplateRequest: Encodable, Sendable, Hashable {
    public var name: String
    public var transactionType: TransactionType
    public var amount: Decimal?
    public var accountId: String?
    public var categoryId: String?
    public var payeeId: String?
    public var paymentType: PaymentType?
    public var note: String?
    public var originalCurrencyCode: String?
    public var tagIds: [String]

    public init(
        name: String,
        transactionType: TransactionType,
        amount: Decimal? = nil,
        accountId: String? = nil,
        categoryId: String? = nil,
        payeeId: String? = nil,
        paymentType: PaymentType? = nil,
        note: String? = nil,
        originalCurrencyCode: String? = nil,
        tagIds: [String] = []
    ) {
        self.name = name
        self.transactionType = transactionType
        self.amount = amount
        self.accountId = accountId
        self.categoryId = categoryId
        self.payeeId = payeeId
        self.paymentType = paymentType
        self.note = note
        self.originalCurrencyCode = originalCurrencyCode
        self.tagIds = tagIds
    }

    private enum CodingKeys: String, CodingKey {
        case name, transactionType, amount, accountId, categoryId, payeeId, paymentType, note
        case originalCurrencyCode, tagIds
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(transactionType, forKey: .transactionType)
        try c.encode(amount, forKey: .amount)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(payeeId, forKey: .payeeId)
        try c.encode(paymentType, forKey: .paymentType)
        try c.encode(note, forKey: .note)
        try c.encode(originalCurrencyCode, forKey: .originalCurrencyCode)
        try c.encode(tagIds, forKey: .tagIds)
    }
}

// MARK: - Attachments

/// A file attached to a transaction.
public struct TransactionAttachment: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let transactionId: String
    public let filename: String
    public let mimeType: String
    public let size: Int
    public let createdAt: Date?

    public init(id: String, transactionId: String, filename: String, mimeType: String, size: Int, createdAt: Date? = nil) {
        self.id = id
        self.transactionId = transactionId
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.createdAt = createdAt
    }

    public var isImage: Bool { mimeType.hasPrefix("image/") }
}

// MARK: - Endpoints

extension Endpoints {
    /// `POST /transactions` with splits, refund link, original amount, and location.
    public static func createTransactionAdvanced(_ request: TransactionAdvancedCreateRequest) -> Endpoint<[Transaction]> {
        Endpoint(.post, "/transactions", body: request)
    }

    /// `PUT /transactions/:id` with the advanced fields.
    public static func updateTransactionAdvanced(id: String, _ request: TransactionAdvancedUpdateRequest) -> Endpoint<[Transaction]> {
        Endpoint(.put, "/transactions/\(id)", body: request)
    }

    /// `GET /transactions/:id` with its splits.
    public static func transactionWithSplits(id: String) -> Endpoint<Transaction?> {
        var query = QueryBuilder()
        query.addFlag("includeSplits", true)
        return Endpoint(.get, "/transactions/\(id)", query: query.items)
    }

    /// `GET /transactions/:id/refunds`: links where the row is the original or the refund.
    public static func transactionRefunds(transactionId: String) -> Endpoint<[TransactionRefundLink]> {
        Endpoint(.get, "/transactions/\(transactionId)/refunds", query: [URLQueryItem(name: "transactionId", value: transactionId)])
    }

    /// `GET /transactions/refund-recommendations`: likely originals for a refund.
    public static func refundRecommendations(transactionId: String) -> Endpoint<[Transaction]> {
        Endpoint(.get, "/transactions/refund-recommendations", query: [URLQueryItem(name: "transactionId", value: transactionId)])
    }

    /// `GET /transactions/refund-recommendations` for a transaction that isn't saved yet:
    /// the server searches the opposite type near `originAmount`.
    public static func refundRecommendations(
        transactionType: TransactionType,
        originAmount: Decimal,
        accountId: String
    ) -> Endpoint<[Transaction]> {
        var query = QueryBuilder()
        query.add("transactionType", transactionType.rawValue)
        query.add("originAmount", originAmount)
        query.add("accountId", accountId)
        return Endpoint(.get, "/transactions/refund-recommendations", query: query.items)
    }

    /// `POST /transactions/refund`.
    public static func linkRefund(_ request: TransactionRefundLinkRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/transactions/refund", body: request)
    }

    /// `DELETE /transactions/refund`.
    public static func unlinkRefund(_ request: TransactionRefundLinkRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/transactions/refund", body: request)
    }

    /// `PUT /transactions/link`: makes two existing rows the legs of one transfer.
    public static func linkTransfer(_ request: TransactionLinkRequest) -> Endpoint<[[Transaction]]> {
        Endpoint(.put, "/transactions/link", body: request)
    }

    /// `PUT /transactions/unlink`: splits a transfer back into two independent rows.
    public static func unlinkTransfer(_ request: TransactionUnlinkRequest) -> Endpoint<[Transaction]> {
        Endpoint(.put, "/transactions/unlink", body: request)
    }

    /// `POST /transactions/bulk-delete`.
    public static func bulkDeleteTransactions(_ request: TransactionBulkDeleteRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/transactions/bulk-delete", body: request)
    }

    /// `PUT /transactions/bulk`.
    public static func bulkSetCategory(_ request: TransactionBulkCategoryRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/transactions/bulk", body: request)
    }

    /// `GET /transaction-groups`.
    public static func transactionGroupSummaries() -> Endpoint<[TransactionGroupSummary]> {
        Endpoint(.get, "/transaction-groups")
    }

    /// `POST /transaction-groups/:id/transactions`.
    public static func addTransactionsToGroup(groupId: String, _ request: TransactionGroupAddRequest) -> Endpoint<TransactionGroupSummary> {
        Endpoint(.post, "/transaction-groups/\(groupId)/transactions", body: request)
    }

    /// `POST /transaction-groups`.
    public static func createTransactionGroupWith(_ request: TransactionGroupCreateRequest) -> Endpoint<TransactionGroupSummary> {
        Endpoint(.post, "/transaction-groups", body: request)
    }

    /// `GET /transaction-templates`.
    public static func transactionTemplates() -> Endpoint<[TransactionTemplate]> {
        Endpoint(.get, "/transaction-templates")
    }

    /// `POST /transaction-templates`.
    public static func createTransactionTemplate(_ request: TransactionTemplateRequest) -> Endpoint<TransactionTemplate> {
        Endpoint(.post, "/transaction-templates", body: request)
    }

    /// `PUT /transaction-templates/:id`.
    public static func updateTransactionTemplate(id: String, _ request: TransactionTemplateRequest) -> Endpoint<TransactionTemplate> {
        Endpoint(.put, "/transaction-templates/\(id)", body: request)
    }

    /// `DELETE /transaction-templates/:id`.
    public static func deleteTransactionTemplate(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/transaction-templates/\(id)")
    }

    /// `GET /transactions/:id/attachments`.
    public static func transactionAttachments(transactionId: String) -> Endpoint<[TransactionAttachment]> {
        Endpoint(.get, "/transactions/\(transactionId)/attachments")
    }

    /// `DELETE /attachments/:id`.
    public static func deleteTransactionAttachment(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/attachments/\(id)")
    }
}
