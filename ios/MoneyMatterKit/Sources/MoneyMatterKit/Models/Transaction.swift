import Foundation

/// A transaction row from `/transactions` and `/transactions/review`.
///
/// `amount` is always positive; `transactionType` gives the direction. `refAmount` is in
/// the base currency. `splits`, `tags`, `transactionGroups`, and `hasAttachments` are
/// present only when the matching include flag was sent.
public struct Transaction: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let amount: Decimal
    public let refAmount: Decimal
    public let commissionRate: Decimal
    public let refCommissionRate: Decimal
    public let cashbackAmount: Decimal
    public let originalAmount: Decimal?
    public let originalCurrencyCode: String?
    public let note: String?
    public let externalUrl: String?
    public let externalReference: String?
    public let location: TransactionLocation?
    public let time: Date
    public let userId: Int
    public let transactionType: TransactionType
    public let paymentType: PaymentType
    public let accountId: String
    public let categoryId: String?
    public let currencyCode: String
    public let accountType: AccountType
    public let refCurrencyCode: String?
    public let transferNature: TransferNature
    public let transferId: String?
    public let originalId: String?
    public let refundLinked: Bool
    public let isPlanned: Bool
    public let plannedMergedAt: Date?
    public let reviewStatus: ReviewStatus
    public let reviewDeferredAt: Date?
    public let payeeId: String?
    public let payeeLocked: Bool
    public let categorizationSource: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let splits: [TransactionSplit]?
    public let tags: [TransactionTag]?
    public let transactionGroups: [TransactionGroupRef]?
    public let hasAttachments: Bool?
    /// `GET /transactions/:id` only: whether the caller may edit the row.
    public let canEdit: Bool?

    public init(
        id: String,
        amount: Decimal,
        refAmount: Decimal? = nil,
        time: Date,
        transactionType: TransactionType,
        accountId: String,
        currencyCode: String,
        categoryId: String? = nil,
        note: String? = nil,
        paymentType: PaymentType = .creditCard,
        transferNature: TransferNature = .notTransfer,
        transferId: String? = nil,
        accountType: AccountType = .system,
        refCurrencyCode: String? = nil,
        reviewStatus: ReviewStatus = .notRequired,
        reviewDeferredAt: Date? = nil,
        payeeId: String? = nil,
        payeeLocked: Bool = false,
        isPlanned: Bool = false,
        userId: Int = 0,
        commissionRate: Decimal = 0,
        refCommissionRate: Decimal = 0,
        cashbackAmount: Decimal = 0,
        originalAmount: Decimal? = nil,
        originalCurrencyCode: String? = nil,
        externalUrl: String? = nil,
        externalReference: String? = nil,
        location: TransactionLocation? = nil,
        originalId: String? = nil,
        refundLinked: Bool = false,
        plannedMergedAt: Date? = nil,
        categorizationSource: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        splits: [TransactionSplit]? = nil,
        tags: [TransactionTag]? = nil,
        transactionGroups: [TransactionGroupRef]? = nil,
        hasAttachments: Bool? = nil,
        canEdit: Bool? = nil
    ) {
        self.id = id
        self.amount = amount
        self.refAmount = refAmount ?? amount
        self.time = time
        self.transactionType = transactionType
        self.accountId = accountId
        self.currencyCode = currencyCode
        self.categoryId = categoryId
        self.note = note
        self.paymentType = paymentType
        self.transferNature = transferNature
        self.transferId = transferId
        self.accountType = accountType
        self.refCurrencyCode = refCurrencyCode
        self.reviewStatus = reviewStatus
        self.reviewDeferredAt = reviewDeferredAt
        self.payeeId = payeeId
        self.payeeLocked = payeeLocked
        self.isPlanned = isPlanned
        self.userId = userId
        self.commissionRate = commissionRate
        self.refCommissionRate = refCommissionRate
        self.cashbackAmount = cashbackAmount
        self.originalAmount = originalAmount
        self.originalCurrencyCode = originalCurrencyCode
        self.externalUrl = externalUrl
        self.externalReference = externalReference
        self.location = location
        self.originalId = originalId
        self.refundLinked = refundLinked
        self.plannedMergedAt = plannedMergedAt
        self.categorizationSource = categorizationSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.splits = splits
        self.tags = tags
        self.transactionGroups = transactionGroups
        self.hasAttachments = hasAttachments
        self.canEdit = canEdit
    }

    private enum CodingKeys: String, CodingKey {
        case id, amount, refAmount, commissionRate, refCommissionRate, cashbackAmount
        case originalAmount, originalCurrencyCode, note, externalUrl, externalReference, location
        case time, userId, transactionType, paymentType, accountId, categoryId, currencyCode
        case accountType, refCurrencyCode, transferNature, transferId, originalId, refundLinked
        case isPlanned, plannedMerge, reviewStatus, reviewDeferredAt, payeeId, payeeLocked
        case categorizationMeta, createdAt, updatedAt, splits, tags, transactionGroups
        case hasAttachments, canEdit
    }

    private struct PlannedMerge: Decodable { let mergedAt: Date? }
    private struct CategorizationMeta: Decodable { let source: String? }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        amount = try c.decode(Decimal.self, forKey: .amount)
        refAmount = try c.decodeIfPresent(Decimal.self, forKey: .refAmount) ?? amount
        commissionRate = try c.decodeIfPresent(Decimal.self, forKey: .commissionRate) ?? 0
        refCommissionRate = try c.decodeIfPresent(Decimal.self, forKey: .refCommissionRate) ?? 0
        cashbackAmount = try c.decodeIfPresent(Decimal.self, forKey: .cashbackAmount) ?? 0
        originalAmount = try c.decodeIfPresent(Decimal.self, forKey: .originalAmount)
        originalCurrencyCode = try c.decodeIfPresent(String.self, forKey: .originalCurrencyCode)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        externalUrl = try c.decodeIfPresent(String.self, forKey: .externalUrl)
        externalReference = try c.decodeIfPresent(String.self, forKey: .externalReference)
        location = try? c.decodeIfPresent(TransactionLocation.self, forKey: .location)
        time = try c.decode(Date.self, forKey: .time)
        userId = try c.decodeIfPresent(Int.self, forKey: .userId) ?? 0
        transactionType = try c.decodeLenient(TransactionType.self, forKey: .transactionType, default: .unknown)
        paymentType = try c.decodeLenient(PaymentType.self, forKey: .paymentType, default: .unknown)
        accountId = try c.decode(String.self, forKey: .accountId)
        categoryId = try c.decodeIfPresent(String.self, forKey: .categoryId)
        currencyCode = try c.decode(String.self, forKey: .currencyCode)
        accountType = try c.decodeLenient(AccountType.self, forKey: .accountType, default: .unknown)
        refCurrencyCode = try c.decodeIfPresent(String.self, forKey: .refCurrencyCode)
        transferNature = try c.decodeLenient(TransferNature.self, forKey: .transferNature, default: .notTransfer)
        transferId = try c.decodeIfPresent(String.self, forKey: .transferId)
        originalId = try c.decodeIfPresent(String.self, forKey: .originalId)
        refundLinked = try c.decodeIfPresent(Bool.self, forKey: .refundLinked) ?? false
        isPlanned = try c.decodeIfPresent(Bool.self, forKey: .isPlanned) ?? false
        plannedMergedAt = (try? c.decodeIfPresent(PlannedMerge.self, forKey: .plannedMerge))?.mergedAt
        reviewStatus = try c.decodeLenient(ReviewStatus.self, forKey: .reviewStatus, default: .notRequired)
        reviewDeferredAt = try c.decodeIfPresent(Date.self, forKey: .reviewDeferredAt)
        payeeId = try c.decodeIfPresent(String.self, forKey: .payeeId)
        payeeLocked = try c.decodeIfPresent(Bool.self, forKey: .payeeLocked) ?? false
        categorizationSource = (try? c.decodeIfPresent(CategorizationMeta.self, forKey: .categorizationMeta))?.source
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        splits = try c.decodeLossyArrayIfPresent([TransactionSplit].self, forKey: .splits)
        tags = try c.decodeLossyArrayIfPresent([TransactionTag].self, forKey: .tags)
        transactionGroups = try c.decodeLossyArrayIfPresent([TransactionGroupRef].self, forKey: .transactionGroups)
        hasAttachments = try c.decodeIfPresent(Bool.self, forKey: .hasAttachments)
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit)
    }

    /// Any transfer, including out-of-wallet ones.
    public var isTransfer: Bool { transferNature != .notTransfer }

    public var isFraud: Bool { reviewStatus == .fraud }

    /// Expenses are negative, income positive, in the transaction currency.
    public var signedAmount: Decimal {
        transactionType == .expense ? -amount : amount
    }

    /// Same as `signedAmount`, in the base currency.
    public var signedRefAmount: Decimal {
        transactionType == .expense ? -refAmount : refAmount
    }
}

public struct TransactionLocation: Sendable, Hashable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct TransactionSplit: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let categoryId: String
    public let amount: Decimal
    public let refAmount: Decimal
    public let note: String?
}

public struct TransactionTag: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let color: String?
    public let icon: String?
}

public struct TransactionGroupRef: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let transactionCount: Int?
}
