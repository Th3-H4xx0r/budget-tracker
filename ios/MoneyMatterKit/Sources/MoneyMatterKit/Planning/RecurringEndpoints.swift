import Foundation

/// `POST /subscriptions` and `PUT /subscriptions/:id` body. On create, nil fields are left
/// out so the server applies its defaults. On update (`sendsNulls`), nil nullable fields are
/// sent as `null` to clear them, since the edit form always carries the full state.
public struct RecurringSubscriptionRequest: Encodable, Sendable, Hashable {
    public var name: String
    public var type: SubscriptionType
    public var transactionType: TransactionType
    /// Sent together with `expectedCurrencyCode`, or neither.
    public var expectedAmount: Decimal?
    public var expectedCurrencyCode: String?
    public var frequency: SubscriptionFrequency
    public var startDate: CalendarDate
    public var endDate: CalendarDate?
    public var accountId: String?
    public var categoryId: String?
    /// Stamped onto matched or booked transactions that have no payee.
    public var payeeId: String?
    /// Merged onto matched or booked transactions. Nil leaves them unchanged.
    public var tagIds: [String]?
    public var notes: String?
    public var dueDate: CalendarDate?
    /// Installments only.
    public var maxOccurrences: Int?
    public var remindBefore: [RecurringRemindPreset]?
    public var notifyEmail: Bool?
    public var autoRecord: Bool?
    public var matchingRules: RecurringMatchingRules?
    public var sendsNulls: Bool

    public init(
        name: String,
        type: SubscriptionType = .subscription,
        transactionType: TransactionType = .expense,
        expectedAmount: Decimal? = nil,
        expectedCurrencyCode: String? = nil,
        frequency: SubscriptionFrequency,
        startDate: CalendarDate,
        endDate: CalendarDate? = nil,
        accountId: String? = nil,
        categoryId: String? = nil,
        payeeId: String? = nil,
        tagIds: [String]? = nil,
        notes: String? = nil,
        dueDate: CalendarDate? = nil,
        maxOccurrences: Int? = nil,
        remindBefore: [RecurringRemindPreset]? = nil,
        notifyEmail: Bool? = nil,
        autoRecord: Bool? = nil,
        matchingRules: RecurringMatchingRules? = nil,
        sendsNulls: Bool = false
    ) {
        self.name = name
        self.type = type
        self.transactionType = transactionType
        self.expectedAmount = expectedAmount
        self.expectedCurrencyCode = expectedCurrencyCode
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.accountId = accountId
        self.categoryId = categoryId
        self.payeeId = payeeId
        self.tagIds = tagIds
        self.notes = notes
        self.dueDate = dueDate
        self.maxOccurrences = maxOccurrences
        self.remindBefore = remindBefore
        self.notifyEmail = notifyEmail
        self.autoRecord = autoRecord
        self.matchingRules = matchingRules
        self.sendsNulls = sendsNulls
    }

    /// The web quick-add payload: today as the start, an optional first due date, the amount
    /// pair only when positive, and a note rule seeded from the name so imports link to it.
    public static func quickAdd(
        name: String,
        type: SubscriptionType,
        transactionType: TransactionType,
        amount: Decimal?,
        currencyCode: String,
        frequency: SubscriptionFrequency,
        nextPaymentDate: CalendarDate?,
        maxOccurrences: Int?,
        accountId: String? = nil,
        today: CalendarDate
    ) -> RecurringSubscriptionRequest {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAmount = (amount ?? 0) > 0
        return RecurringSubscriptionRequest(
            name: trimmed,
            type: type,
            transactionType: transactionType,
            expectedAmount: hasAmount ? amount : nil,
            expectedCurrencyCode: hasAmount ? currencyCode : nil,
            frequency: frequency,
            startDate: today,
            accountId: accountId,
            dueDate: nextPaymentDate,
            maxOccurrences: type == .installment ? maxOccurrences : nil,
            matchingRules: RecurringMatchingRules(rules: [.note(keywords: [trimmed])])
        )
    }

    private enum CodingKeys: String, CodingKey {
        case name, type, transactionType, expectedAmount, expectedCurrencyCode, frequency, startDate, endDate
        case accountId, categoryId, payeeId, tagIds, notes, dueDate, maxOccurrences, remindBefore, notifyEmail, autoRecord, matchingRules
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(transactionType, forKey: .transactionType)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(startDate, forKey: .startDate)
        try encodeNullable(expectedAmount, .expectedAmount, in: &container)
        try encodeNullable(expectedCurrencyCode, .expectedCurrencyCode, in: &container)
        try encodeNullable(endDate, .endDate, in: &container)
        try encodeNullable(accountId, .accountId, in: &container)
        try encodeNullable(categoryId, .categoryId, in: &container)
        try encodeNullable(payeeId, .payeeId, in: &container)
        try container.encodeIfPresent(tagIds, forKey: .tagIds)
        try encodeNullable(notes, .notes, in: &container)
        try encodeNullable(dueDate, .dueDate, in: &container)
        try encodeNullable(maxOccurrences, .maxOccurrences, in: &container)
        try container.encodeIfPresent(remindBefore, forKey: .remindBefore)
        try container.encodeIfPresent(notifyEmail, forKey: .notifyEmail)
        try container.encodeIfPresent(autoRecord, forKey: .autoRecord)
        try container.encodeIfPresent(matchingRules, forKey: .matchingRules)
    }

    private func encodeNullable<Value: Encodable>(
        _ value: Value?,
        _ key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else if sendsNulls {
            try container.encodeNil(forKey: key)
        }
    }
}

/// `POST /subscriptions/:id/periods/:periodId/pay` body. Either link `transactionId` or set
/// `createTransaction` (never both); nil fields are omitted.
public struct RecurringMarkPaidRequest: Encodable, Sendable, Hashable {
    public var transactionId: String?
    public var notes: String?
    public var createTransaction: Bool?
    /// Overrides the expected amount of the created transaction.
    public var amount: Decimal?
    public var time: Date?
    /// Books the created transaction here and links the account to the subscription.
    public var accountId: String?

    public init(
        transactionId: String? = nil,
        notes: String? = nil,
        createTransaction: Bool? = nil,
        amount: Decimal? = nil,
        time: Date? = nil,
        accountId: String? = nil
    ) {
        self.transactionId = transactionId
        self.notes = notes
        self.createTransaction = createTransaction
        self.amount = amount
        self.time = time
        self.accountId = accountId
    }
}

private struct RecurringTransactionIDsBody: Encodable, Sendable {
    let transactionIds: [String]
}

private struct RecurringToggleActiveBody: Encodable, Sendable {
    let isActive: Bool
}

private struct RecurringAcceptCandidateBody: Encodable, Sendable {
    let subscriptionId: String
}

public struct RecurringLinkResult: Sendable, Hashable, Decodable {
    public let linked: Int?
    public let unlinked: Int?
}

extension Endpoints {
    /// `GET /subscriptions` with every subscription (active and paused), sorted server-side.
    public static func recurringSubscriptions(sortBy: RecurringSortKey) -> Endpoint<[SubscriptionListItem]> {
        var query = QueryBuilder()
        query.add("sortBy", sortBy.rawValue)
        return Endpoint(.get, "/subscriptions", query: query.items)
    }

    /// `GET /subscriptions/summary`. `lookbackMonths` is one of 1, 3, 6, 12.
    public static func recurringSummary(lookbackMonths: Int? = nil) -> Endpoint<SubscriptionsSummary> {
        var query = QueryBuilder()
        query.add("lookbackMonths", lookbackMonths)
        return Endpoint(.get, "/subscriptions/summary", query: query.items)
    }

    public static func recurringSubscription(id: String) -> Endpoint<RecurringSubscriptionDetail> {
        Endpoint(.get, "/subscriptions/\(id)")
    }

    public static func createRecurringSubscription(_ request: RecurringSubscriptionRequest) -> Endpoint<RecurringSubscriptionRef> {
        Endpoint(.post, "/subscriptions", body: request)
    }

    public static func updateRecurringSubscription(id: String, _ request: RecurringSubscriptionRequest) -> Endpoint<RecurringSubscriptionRef> {
        Endpoint(.put, "/subscriptions/\(id)", body: request)
    }

    public static func deleteRecurringSubscription(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/subscriptions/\(id)")
    }

    public static func toggleRecurringSubscription(id: String, isActive: Bool) -> Endpoint<RecurringSubscriptionRef> {
        Endpoint(.patch, "/subscriptions/\(id)/toggle-active", body: RecurringToggleActiveBody(isActive: isActive))
    }

    public static func linkRecurringTransactions(id: String, transactionIds: [String]) -> Endpoint<RecurringLinkResult> {
        Endpoint(.post, "/subscriptions/\(id)/transactions", body: RecurringTransactionIDsBody(transactionIds: transactionIds))
    }

    public static func unlinkRecurringTransactions(id: String, transactionIds: [String]) -> Endpoint<RecurringLinkResult> {
        Endpoint(.delete, "/subscriptions/\(id)/transactions", body: RecurringTransactionIDsBody(transactionIds: transactionIds))
    }

    /// Unlinked transactions that look like payments of this subscription.
    public static func recurringSuggestedMatches(id: String) -> Endpoint<[Transaction]> {
        Endpoint(.get, "/subscriptions/\(id)/suggest-matches")
    }

    public static func recurringPayPreview(id: String) -> Endpoint<RecurringPayPreview> {
        Endpoint(.get, "/subscriptions/\(id)/pay-preview")
    }

    public static func markRecurringPeriodPaid(
        id: String,
        periodId: String,
        _ request: RecurringMarkPaidRequest
    ) -> Endpoint<RecurringPeriod> {
        Endpoint(.post, "/subscriptions/\(id)/periods/\(periodId)/pay", body: request)
    }

    public static func skipRecurringPeriod(id: String, periodId: String) -> Endpoint<RecurringPeriod> {
        Endpoint(.post, "/subscriptions/\(id)/periods/\(periodId)/skip")
    }

    /// Detaches the period's transaction and reopens the period.
    public static func unlinkRecurringPeriod(id: String, periodId: String) -> Endpoint<RecurringPeriod> {
        Endpoint(.post, "/subscriptions/\(id)/periods/\(periodId)/unlink")
    }

    /// Reopens a paid or skipped period.
    public static func revertRecurringPeriod(id: String, periodId: String) -> Endpoint<RecurringPeriod> {
        Endpoint(.post, "/subscriptions/\(id)/periods/\(periodId)/revert")
    }

    public static func detectRecurringCandidates() -> Endpoint<RecurringCandidatesResponse> {
        Endpoint(.get, "/subscriptions/detect-candidates")
    }

    /// Marks the candidate accepted and links its sample transactions to `subscriptionId`.
    public static func acceptRecurringCandidate(id: String, subscriptionId: String?) -> Endpoint<RecurringCandidateResolution> {
        Endpoint(
            .post,
            "/subscriptions/candidates/\(id)/accept",
            body: subscriptionId.map { RecurringAcceptCandidateBody(subscriptionId: $0) }
        )
    }

    public static func dismissRecurringCandidate(id: String) -> Endpoint<RecurringCandidateResolution> {
        Endpoint(.post, "/subscriptions/candidates/\(id)/dismiss")
    }
}
