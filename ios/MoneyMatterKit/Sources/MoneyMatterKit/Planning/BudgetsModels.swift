import Foundation

public enum PlanningBudgetStatus: String, LenientEnum, CaseIterable {
    case active
    case closed
    case archived
    case unknown
}

public enum PlanningBudgetType: String, LenientEnum, CaseIterable {
    case manual
    case category
    case unknown
}

/// `GET /budgets` and `GET /budgets/:id`. `limitAmount` is in the base currency.
public struct PlanningBudget: Sendable, Hashable, Identifiable, Decodable {
    public struct CategoryRef: Sendable, Hashable, Identifiable, Decodable {
        public let id: String
        public let name: String
        public let color: String?
        public let parentId: String?
    }

    /// Present when the budget is shared with or by the caller.
    public struct ShareInfo: Sendable, Hashable, Decodable {
        public struct Owner: Sendable, Hashable, Decodable {
            public let username: String?
        }

        public let isOwner: Bool
        /// `read`, `write`, or `manage`.
        public let permission: String?
        public let owner: Owner?

        private enum CodingKeys: String, CodingKey { case isOwner, permission, owner }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isOwner = try container.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
            permission = try container.decodeIfPresent(String.self, forKey: .permission)
            owner = try? container.decodeIfPresent(Owner.self, forKey: .owner)
        }
    }

    public let id: String
    public let name: String
    public let status: PlanningBudgetStatus
    public let type: PlanningBudgetType
    public let startDate: Date?
    public let endDate: Date?
    public let autoInclude: Bool
    public let limitAmount: Decimal?
    public let categories: [CategoryRef]
    public let share: ShareInfo?

    public var isArchived: Bool { status == .archived }

    /// Without a share block the caller owns the budget.
    public var isOwner: Bool { share?.isOwner ?? true }

    /// Edit metadata and archive: owners and `manage` recipients. Delete is owner-only.
    public var canManage: Bool { isOwner || share?.permission == "manage" }

    /// Add or remove transactions: owners, `write`, and `manage` recipients.
    public var canWrite: Bool { canManage || share?.permission == "write" }

    /// The owner's handle when the budget is shared with the caller.
    public var sharedByHandle: String? { isOwner ? nil : share?.owner?.username }

    private enum CodingKeys: String, CodingKey {
        case id, name, status, type, startDate, endDate, autoInclude, limitAmount, categories, share
    }

    public init(
        id: String,
        name: String,
        status: PlanningBudgetStatus = .active,
        type: PlanningBudgetType = .manual,
        startDate: Date? = nil,
        endDate: Date? = nil,
        autoInclude: Bool = false,
        limitAmount: Decimal? = nil,
        categories: [CategoryRef] = [],
        share: ShareInfo? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.autoInclude = autoInclude
        self.limitAmount = limitAmount
        self.categories = categories
        self.share = share
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        status = try container.decodeLenient(PlanningBudgetStatus.self, forKey: .status, default: .active)
        type = try container.decodeLenient(PlanningBudgetType.self, forKey: .type, default: .manual)
        startDate = try? container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try? container.decodeIfPresent(Date.self, forKey: .endDate)
        autoInclude = try container.decodeIfPresent(Bool.self, forKey: .autoInclude) ?? false
        limitAmount = try container.decodeIfPresent(Decimal.self, forKey: .limitAmount)
        categories = try container.decodeLossyArrayIfPresent([CategoryRef].self, forKey: .categories) ?? []
        share = try? container.decodeIfPresent(ShareInfo.self, forKey: .share)
    }
}

/// `GET /budgets/:id/stats`. Amounts are in the base currency.
public struct PlanningBudgetStats: Sendable, Hashable, Decodable {
    public let actualIncome: Decimal
    public let actualExpense: Decimal
    public let balance: Decimal
    /// Percent of the limit used (0–100+), or nil when the budget has no limit.
    public let utilizationRate: Double?
    public let transactionsCount: Int
    public let firstTransactionDate: Date?
    public let lastTransactionDate: Date?

    private enum RootKeys: String, CodingKey { case summary }

    private enum CodingKeys: String, CodingKey {
        case actualIncome, actualExpense, balance, utilizationRate, transactionsCount
        case firstTransactionDate, lastTransactionDate
    }

    public init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let container = try root.nestedContainer(keyedBy: CodingKeys.self, forKey: .summary)
        actualIncome = try container.decodeIfPresent(Decimal.self, forKey: .actualIncome) ?? 0
        actualExpense = try container.decodeIfPresent(Decimal.self, forKey: .actualExpense) ?? 0
        balance = try container.decodeIfPresent(Decimal.self, forKey: .balance) ?? 0
        utilizationRate = try container.decodeIfPresent(Double.self, forKey: .utilizationRate)
        transactionsCount = try container.decodeIfPresent(Int.self, forKey: .transactionsCount) ?? 0
        firstTransactionDate = try? container.decodeIfPresent(Date.self, forKey: .firstTransactionDate)
        lastTransactionDate = try? container.decodeIfPresent(Date.self, forKey: .lastTransactionDate)
    }
}

public enum PlanningBudgetGranularity: String, LenientEnum, CaseIterable {
    case monthly
    case weekly
    case unknown
}

/// `GET /budgets/:id/spending-stats`.
public struct PlanningBudgetSpendingStats: Sendable, Hashable, Decodable {
    public struct CategorySpending: Sendable, Hashable, Identifiable, Decodable {
        public let categoryId: String
        public let name: String
        public let color: String?
        public let amount: Decimal
        public let children: [CategorySpending]

        public var id: String { categoryId }

        private enum CodingKeys: String, CodingKey { case categoryId, name, color, amount, children }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            categoryId = try container.decode(String.self, forKey: .categoryId)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            color = try container.decodeIfPresent(String.self, forKey: .color)
            amount = try container.decodeIfPresent(Decimal.self, forKey: .amount) ?? 0
            children = try container.decodeLossyArrayIfPresent([CategorySpending].self, forKey: .children) ?? []
        }
    }

    public struct Period: Sendable, Hashable, Identifiable, Decodable {
        public let periodStart: CalendarDate
        public let periodEnd: CalendarDate
        public let expense: Decimal
        public let income: Decimal

        public var id: CalendarDate { periodStart }
    }

    public let spendingsByCategory: [CategorySpending]
    public let granularity: PlanningBudgetGranularity
    public let periods: [Period]

    public var isEmpty: Bool { spendingsByCategory.isEmpty && periods.isEmpty }

    private enum CodingKeys: String, CodingKey { case spendingsByCategory, spendingOverTime }
    private enum OverTimeKeys: String, CodingKey { case granularity, periods }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spendingsByCategory = try container.decodeLossyArrayIfPresent(
            [CategorySpending].self, forKey: .spendingsByCategory
        ) ?? []
        if container.contains(.spendingOverTime), try !container.decodeNil(forKey: .spendingOverTime) {
            let overTime = try container.nestedContainer(keyedBy: OverTimeKeys.self, forKey: .spendingOverTime)
            granularity = try overTime.decodeLenient(PlanningBudgetGranularity.self, forKey: .granularity, default: .monthly)
            periods = try overTime.decodeLossyArrayIfPresent([Period].self, forKey: .periods) ?? []
        } else {
            granularity = .monthly
            periods = []
        }
    }
}

/// One row of `GET /budgets/:id/category-transactions`. A split transaction appears once
/// per matching split, so `id` can repeat; `effectiveRefAmount` is the split's share.
public struct PlanningBudgetCategoryTransaction: Sendable, Hashable, Decodable {
    public struct EffectiveCategory: Sendable, Hashable, Decodable {
        public let id: String
        public let name: String
        public let color: String?
    }

    public let id: String
    public let time: Date
    public let transactionType: TransactionType
    public let refAmount: Decimal
    public let amount: Decimal
    public let note: String?
    public let categoryId: String?
    public let accountId: String
    public let reviewStatus: ReviewStatus?
    public let effectiveCategory: EffectiveCategory?
    public let effectiveRefAmount: Decimal?

    /// The amount that counts toward the budget, in the base currency.
    public var budgetAmount: Decimal { effectiveRefAmount ?? refAmount }

    private enum CodingKeys: String, CodingKey {
        case id, time, transactionType, refAmount, amount, note, categoryId, accountId, reviewStatus
        case effectiveCategory, effectiveRefAmount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        time = try container.decode(Date.self, forKey: .time)
        transactionType = try container.decodeLenient(TransactionType.self, forKey: .transactionType, default: .expense)
        refAmount = try container.decodeIfPresent(Decimal.self, forKey: .refAmount) ?? 0
        amount = try container.decodeIfPresent(Decimal.self, forKey: .amount) ?? 0
        note = try container.decodeIfPresent(String.self, forKey: .note)
        categoryId = try container.decodeIfPresent(String.self, forKey: .categoryId)
        accountId = try container.decodeIfPresent(String.self, forKey: .accountId) ?? ""
        reviewStatus = try container.decodeIfPresent(ReviewStatus.self, forKey: .reviewStatus)
        effectiveCategory = try? container.decodeIfPresent(EffectiveCategory.self, forKey: .effectiveCategory)
        effectiveRefAmount = try container.decodeIfPresent(Decimal.self, forKey: .effectiveRefAmount)
    }
}

/// `GET /budgets/:id/category-transactions`: one page plus the total row count.
public struct PlanningBudgetCategoryTransactionsPage: Sendable, Hashable, Decodable {
    public let transactions: [PlanningBudgetCategoryTransaction]
    public let total: Int

    private enum CodingKeys: String, CodingKey { case transactions, total }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactions = try container.decodeLossyArrayIfPresent(
            [PlanningBudgetCategoryTransaction].self, forKey: .transactions
        ) ?? []
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? transactions.count
    }
}

/// `POST /budgets` body. Category budgets need at least one category; `autoInclude` only
/// applies to manual budgets with both dates. A nil `limitAmount` means no limit.
public struct PlanningBudgetCreateRequest: Encodable, Sendable, Hashable {
    public var name: String
    public var type: PlanningBudgetType
    public var categoryIds: [String]?
    public var startDate: Date?
    public var endDate: Date?
    public var autoInclude: Bool
    public var limitAmount: Decimal?

    public init(
        name: String,
        type: PlanningBudgetType,
        categoryIds: [String]? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        autoInclude: Bool = false,
        limitAmount: Decimal? = nil
    ) {
        self.name = name
        self.type = type
        self.categoryIds = categoryIds
        self.startDate = startDate
        self.endDate = endDate
        self.autoInclude = autoInclude
        self.limitAmount = limitAmount
    }

    private enum CodingKeys: String, CodingKey {
        case name, type, categoryIds, startDate, endDate, autoInclude, limitAmount
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(categoryIds, forKey: .categoryIds)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(autoInclude, forKey: .autoInclude)
        if let limitAmount, limitAmount > 0 {
            try container.encode(limitAmount, forKey: .limitAmount)
        } else {
            try container.encodeNil(forKey: .limitAmount)
        }
    }
}

/// `PUT /budgets/:id` body. Nil fields are left unchanged. The server can't clear a limit,
/// so a non-positive `limitAmount` is omitted. `autoInclude` defaults to false server-side
/// when absent, so send the current value to keep it.
public struct PlanningBudgetUpdateRequest: Encodable, Sendable, Hashable {
    public var name: String?
    public var categoryIds: [String]?
    public var startDate: Date?
    public var endDate: Date?
    public var autoInclude: Bool?
    public var limitAmount: Decimal?

    public init(
        name: String? = nil,
        categoryIds: [String]? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        autoInclude: Bool? = nil,
        limitAmount: Decimal? = nil
    ) {
        self.name = name
        self.categoryIds = categoryIds
        self.startDate = startDate
        self.endDate = endDate
        self.autoInclude = autoInclude
        self.limitAmount = limitAmount
    }

    private enum CodingKeys: String, CodingKey {
        case name, categoryIds, startDate, endDate, autoInclude, limitAmount
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(categoryIds, forKey: .categoryIds)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encodeIfPresent(autoInclude, forKey: .autoInclude)
        if let limitAmount, limitAmount > 0 {
            try container.encode(limitAmount, forKey: .limitAmount)
        }
    }
}

/// `POST|DELETE /budgets/:id/transactions` body.
public struct PlanningBudgetTransactionsRequest: Encodable, Sendable, Hashable {
    public var transactionIds: [String]

    public init(transactionIds: [String]) {
        self.transactionIds = transactionIds
    }
}

struct PlanningBudgetArchiveRequest: Encodable, Sendable, Hashable {
    let isArchived: Bool
}
