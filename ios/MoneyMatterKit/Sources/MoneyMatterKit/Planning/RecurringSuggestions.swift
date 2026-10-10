import Foundation

// MARK: - Match reasons

/// Why the scoring matcher ranked a transaction against a recurring payment. Codes the app
/// doesn't know yet decode as `.unknown` and are hidden.
public enum RecurringMatchReasonCode: String, LenientEnum, CaseIterable {
    case payeeMatch = "payee_match"
    case merchantSimilar = "merchant_similar"
    case learnedMerchant = "learned_merchant"
    case keywordMatch = "keyword_match"
    case ruleMatch = "rule_match"
    case nearDueDate = "near_due_date"
    case farFromDueDate = "far_from_due_date"
    case amountClose = "amount_close"
    case amountDiffers = "amount_differs"
    case sameAccount = "same_account"
    case differentAccount = "different_account"
    case sameCategory = "same_category"
    case periodAlreadyCovered = "period_already_covered"
    case ambiguousWithOtherSubscription = "ambiguous_with_other_subscription"
    case unknown
}

/// One `MatchReason`: a scored signal plus its optional detail.
public struct RecurringMatchReason: Sendable, Hashable, Decodable {
    public let code: RecurringMatchReasonCode
    /// The signal's weight in the total score; 0 for caps.
    public let weight: Double
    /// 0...1.
    public let value: Double
    /// `near_due_date` / `far_from_due_date`: the date the transaction was compared against.
    public let dueDate: CalendarDate?
    /// `near_due_date` / `far_from_due_date`: absolute days from `dueDate`.
    public let days: Int?
    /// `amount_close` / `amount_differs`: signed deviation from the expected amount, in percent.
    public let deviationPct: Double?
    /// `ambiguous_with_other_subscription`: the competing payment.
    public let otherSubscriptionId: String?

    private enum CodingKeys: String, CodingKey { case code, weight, value, detail }
    private enum DetailKeys: String, CodingKey { case dueDate, days, deviationPct, otherSubscriptionId }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeLenient(RecurringMatchReasonCode.self, forKey: .code, default: .unknown)
        weight = (try? container.decodeIfPresent(Double.self, forKey: .weight)) ?? 0
        value = (try? container.decodeIfPresent(Double.self, forKey: .value)) ?? 0
        let detail = try? container.nestedContainer(keyedBy: DetailKeys.self, forKey: .detail)
        dueDate = try? detail?.decodeIfPresent(CalendarDate.self, forKey: .dueDate)
        days = (try? detail?.decodeIfPresent(Double.self, forKey: .days)).map { Int($0.rounded()) }
        deviationPct = try? detail?.decodeIfPresent(Double.self, forKey: .deviationPct)
        otherSubscriptionId = try? detail?.decodeIfPresent(String.self, forKey: .otherSubscriptionId)
    }

    /// Reasons a client shows as chips: identity, timing, amount and account evidence. Caps
    /// and unknown codes stay out.
    public var isDisplayable: Bool {
        switch code {
        case .unknown, .periodAlreadyCovered, .ambiguousWithOtherSubscription: false
        default: true
        }
    }
}

/// `high` when the score reaches the auto-link tier (0.8), otherwise `medium`.
public enum RecurringMatchConfidence: String, LenientEnum, CaseIterable {
    case high
    case medium
    case unknown
}

// MARK: - Suggestions

/// One ranked suggestion from `GET /subscriptions/:id/suggestions`.
public struct RecurringSuggestion: Sendable, Hashable, Identifiable, Decodable {
    public let transaction: Transaction
    /// 0...1.
    public let score: Double
    public let confidence: RecurringMatchConfidence
    public let reasons: [RecurringMatchReason]
    public let nearestDueDate: CalendarDate?
    public let daysFromDue: Int?
    public let amountDeviationPct: Double?

    public var id: String { transaction.id }

    private enum CodingKeys: String, CodingKey {
        case transaction, score, confidence, reasons, nearestDueDate, daysFromDue, amountDeviationPct
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transaction = try container.decode(Transaction.self, forKey: .transaction)
        score = (try? container.decodeIfPresent(Double.self, forKey: .score)) ?? 0
        confidence = try container.decodeLenient(RecurringMatchConfidence.self, forKey: .confidence, default: .unknown)
        reasons = (try? container.decodeLossyArrayIfPresent([RecurringMatchReason].self, forKey: .reasons)) ?? []
        nearestDueDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .nearestDueDate)
        daysFromDue = (try? container.decodeIfPresent(Double.self, forKey: .daysFromDue)).map { Int($0.rounded()) }
        amountDeviationPct = try? container.decodeIfPresent(Double.self, forKey: .amountDeviationPct)
    }
}

/// `GET /subscriptions/:id/suggestions`.
public struct RecurringSuggestionsResponse: Sendable, Hashable, Decodable {
    public let suggestions: [RecurringSuggestion]
    public let dismissedCount: Int

    private enum CodingKeys: String, CodingKey { case suggestions, dismissedCount }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        suggestions = try container.decodeLossyArrayIfPresent([RecurringSuggestion].self, forKey: .suggestions) ?? []
        dismissedCount = (try? container.decodeIfPresent(Int.self, forKey: .dismissedCount)) ?? 0
    }
}

// MARK: - Linkable transactions

/// `sort` on `GET /subscriptions/:id/linkable-transactions`.
public enum RecurringLinkableSort: String, Sendable, Hashable, CaseIterable {
    case date
    case relevance
}

/// Query of `GET /subscriptions/:id/linkable-transactions`.
public struct RecurringLinkableQuery: Sendable, Hashable {
    /// Matched against the note and payee name, and against the amount when numeric. The
    /// server ignores fewer than two characters.
    public var search: String?
    public var from: CalendarDate?
    public var to: CalendarDate?
    public var accountIds: [String]
    public var sort: RecurringLinkableSort
    /// 1...100.
    public var limit: Int
    public var offset: Int

    public static let pageSize = 30

    public init(
        search: String? = nil,
        from: CalendarDate? = nil,
        to: CalendarDate? = nil,
        accountIds: [String] = [],
        sort: RecurringLinkableSort = .date,
        limit: Int = RecurringLinkableQuery.pageSize,
        offset: Int = 0
    ) {
        self.search = search
        self.from = from
        self.to = to
        self.accountIds = accountIds
        self.sort = sort
        self.limit = limit
        self.offset = offset
    }

    var queryItems: [URLQueryItem] {
        var query = QueryBuilder()
        let trimmed = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        query.add("search", trimmed.count >= 2 ? trimmed : nil)
        query.add("from", day: from)
        query.add("to", day: to)
        query.add("accountIds", list: accountIds)
        query.add("sort", sort.rawValue)
        query.add("limit", min(max(limit, 1), 100))
        query.add("offset", offset > 0 ? offset : nil)
        return query.items
    }
}

/// One row of `GET /subscriptions/:id/linkable-transactions`.
public struct RecurringLinkableItem: Sendable, Hashable, Identifiable, Decodable {
    public struct LinkedSubscription: Sendable, Hashable, Decodable {
        public let id: String
        public let name: String
    }

    public let transaction: Transaction
    public let score: Double
    public let reasons: [RecurringMatchReason]
    /// Set when the transaction is linked to another recurring payment; such rows can't be picked.
    public let linkedSubscription: LinkedSubscription?
    public let isDismissed: Bool

    public var id: String { transaction.id }

    private enum CodingKeys: String, CodingKey { case transaction, score, reasons, linkedSubscription, isDismissed }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transaction = try container.decode(Transaction.self, forKey: .transaction)
        score = (try? container.decodeIfPresent(Double.self, forKey: .score)) ?? 0
        reasons = (try? container.decodeLossyArrayIfPresent([RecurringMatchReason].self, forKey: .reasons)) ?? []
        linkedSubscription = try? container.decodeIfPresent(LinkedSubscription.self, forKey: .linkedSubscription)
        isDismissed = (try? container.decodeIfPresent(Bool.self, forKey: .isDismissed)) ?? false
    }
}

/// A page of `GET /subscriptions/:id/linkable-transactions`.
public struct RecurringLinkablePage: Sendable, Hashable, Decodable {
    public let items: [RecurringLinkableItem]
    public let hasMore: Bool

    private enum CodingKeys: String, CodingKey { case items, hasMore }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeLossyArrayIfPresent([RecurringLinkableItem].self, forKey: .items) ?? []
        hasMore = (try? container.decodeIfPresent(Bool.self, forKey: .hasMore)) ?? false
    }
}

/// `POST /subscriptions/:id/suggestions/dismiss`.
public struct RecurringDismissResult: Sendable, Hashable, Decodable {
    public let dismissed: Int

    private enum CodingKeys: String, CodingKey { case dismissed }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dismissed = (try? container.decodeIfPresent(Int.self, forKey: .dismissed)) ?? 0
    }
}

// MARK: - List counts

/// A `GET /subscriptions` row with its count of pending match suggestions.
public struct RecurringListEntry: Sendable, Hashable, Identifiable, Decodable {
    public let item: SubscriptionListItem
    public let pendingSuggestionsCount: Int

    public var id: String { item.id }

    private enum CodingKeys: String, CodingKey { case pendingSuggestionsCount }

    public init(from decoder: any Decoder) throws {
        item = try SubscriptionListItem(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pendingSuggestionsCount = (try? container.decodeIfPresent(Int.self, forKey: .pendingSuggestionsCount)) ?? 0
    }
}

// MARK: - Endpoints

private struct RecurringDismissBody: Encodable, Sendable {
    let transactionIds: [String]
}

extension Endpoints {
    /// `GET /subscriptions` rows with `pendingSuggestionsCount`.
    public static func recurringSubscriptionEntries(sortBy: RecurringSortKey) -> Endpoint<[RecurringListEntry]> {
        var query = QueryBuilder()
        query.add("sortBy", sortBy.rawValue)
        return Endpoint(.get, "/subscriptions", query: query.items)
    }

    /// Ranked transactions that look like payments of this subscription, with reasons.
    public static func recurringSuggestions(id: String, limit: Int? = nil) -> Endpoint<RecurringSuggestionsResponse> {
        var query = QueryBuilder()
        query.add("limit", limit)
        return Endpoint(.get, "/subscriptions/\(id)/suggestions", query: query.items)
    }

    /// Every transaction of the subscription's direction, filtered and paged, annotated with
    /// its score and any other payment it's linked to.
    public static func recurringLinkableTransactions(
        id: String,
        query: RecurringLinkableQuery
    ) -> Endpoint<RecurringLinkablePage> {
        Endpoint(.get, "/subscriptions/\(id)/linkable-transactions", query: query.queryItems)
    }

    /// Hides these suggestions for this subscription. Linking one later overrides it.
    public static func dismissRecurringSuggestions(id: String, transactionIds: [String]) -> Endpoint<RecurringDismissResult> {
        Endpoint(.post, "/subscriptions/\(id)/suggestions/dismiss", body: RecurringDismissBody(transactionIds: transactionIds))
    }
}
