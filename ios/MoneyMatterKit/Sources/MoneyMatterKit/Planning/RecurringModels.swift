import Foundation

/// `sortBy` on `GET /subscriptions`. The server returns the list already sorted.
public enum RecurringSortKey: String, Sendable, Hashable, CaseIterable {
    case dueDate
    case amount
    case name
    case recent
}

/// `remindBefore` presets. At most three per subscription.
public enum RecurringRemindPreset: String, LenientEnum, CaseIterable {
    case onDueDate = "0_days"
    case oneDay = "1_day"
    case twoDays = "2_days"
    case threeDays = "3_days"
    case fiveDays = "5_days"
    case oneWeek = "1_week"
    case twoWeeks = "2_weeks"
    case oneMonth = "1_month"
    case unknown

    public static let maxSelected = 3
    public static var selectable: [RecurringRemindPreset] { allCases.filter { $0 != .unknown } }
}

/// How a subscription settles its periods: auto-record books the transaction on the due date,
/// matching links imported transactions by rules, manual leaves both to the user.
public enum RecurringAutomationMode: String, Sendable, Hashable, CaseIterable {
    case match
    case record
    case manual

    public init(autoRecord: Bool, rules: [RecurringMatchingRule]) {
        if autoRecord {
            self = .record
        } else if !rules.isEmpty {
            self = .match
        } else {
            self = .manual
        }
    }
}

/// One auto-matching rule; all rules must pass (AND).
public enum RecurringMatchingRule: Sendable, Hashable, Codable {
    /// Note contains any of the keywords.
    case note(keywords: [String])
    /// Amount between `min` and `max`, optionally in `currencyCode`.
    case amount(min: Decimal, max: Decimal, currencyCode: String?)
    case transactionType(String)
    case accountId(String)
    case unknown

    private enum CodingKeys: String, CodingKey { case field, `operator`, value, currencyCode }
    private struct Range: Codable { let min: Decimal; let max: Decimal }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let field = try container.decodeIfPresent(String.self, forKey: .field)
        switch field {
        case "note":
            self = .note(keywords: (try? container.decode([String].self, forKey: .value)) ?? [])
        case "amount":
            let range = try? container.decode(Range.self, forKey: .value)
            self = .amount(
                min: range?.min ?? 0,
                max: range?.max ?? 0,
                currencyCode: try? container.decodeIfPresent(String.self, forKey: .currencyCode)
            )
        case "transactionType":
            self = .transactionType((try? container.decode(String.self, forKey: .value)) ?? "")
        case "accountId":
            self = .accountId((try? container.decode(String.self, forKey: .value)) ?? "")
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .note(let keywords):
            try container.encode("note", forKey: .field)
            try container.encode("contains_any", forKey: .`operator`)
            try container.encode(keywords, forKey: .value)
        case .amount(let min, let max, let currencyCode):
            try container.encode("amount", forKey: .field)
            try container.encode("between", forKey: .`operator`)
            try container.encode(Range(min: min, max: max), forKey: .value)
            try container.encodeIfPresent(currencyCode, forKey: .currencyCode)
        case .transactionType(let value):
            try container.encode("transactionType", forKey: .field)
            try container.encode("equals", forKey: .`operator`)
            try container.encode(value, forKey: .value)
        case .accountId(let value):
            try container.encode("accountId", forKey: .field)
            try container.encode("equals", forKey: .`operator`)
            try container.encode(value, forKey: .value)
        case .unknown:
            break
        }
    }

    /// Drops rules with nothing to match: blank keywords, a zero range, or an empty value.
    public static func nonEmpty(_ rules: [RecurringMatchingRule]) -> [RecurringMatchingRule] {
        rules.compactMap { rule in
            switch rule {
            case .note(let keywords):
                let kept = keywords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                return kept.isEmpty ? nil : .note(keywords: kept)
            case .amount(let min, let max, _):
                return (min > 0 || max > 0) ? rule : nil
            case .transactionType(let value), .accountId(let value):
                return value.isEmpty ? nil : rule
            case .unknown:
                return nil
            }
        }
    }
}

public struct RecurringMatchingRules: Sendable, Hashable, Codable {
    public var rules: [RecurringMatchingRule]

    public init(rules: [RecurringMatchingRule] = []) {
        self.rules = rules
    }

    private enum CodingKeys: String, CodingKey { case rules }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = (try container.decodeLossyArrayIfPresent([RecurringMatchingRule].self, forKey: .rules) ?? [])
            .filter { $0 != .unknown }
    }
}

/// One billing period of a subscription.
public struct RecurringPeriod: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let subscriptionId: String?
    public let dueDate: CalendarDate?
    public let status: SubscriptionPeriodStatus
    public let paidAt: Date?
    public let transactionId: String?
    /// True when the app generated `transactionId` while marking the period paid.
    public let transactionAutoCreated: Bool
    public let notes: String?

    private enum CodingKeys: String, CodingKey {
        case id, subscriptionId, dueDate, status, paidAt, transactionId, transactionAutoCreated, notes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        subscriptionId = try container.decodeIfPresent(String.self, forKey: .subscriptionId)
        dueDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .dueDate)
        status = try container.decodeLenient(SubscriptionPeriodStatus.self, forKey: .status, default: .unknown)
        paidAt = try? container.decodeIfPresent(Date.self, forKey: .paidAt)
        transactionId = try container.decodeIfPresent(String.self, forKey: .transactionId)
        transactionAutoCreated = try container.decodeIfPresent(Bool.self, forKey: .transactionAutoCreated) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    public var isOpen: Bool { status == .upcoming || status == .overdue }
}

/// A transaction linked to a subscription, with the link's metadata.
public struct RecurringLinkedTransaction: Sendable, Hashable, Identifiable, Decodable {
    public let transaction: Transaction
    public let matchSource: String?
    public let matchedAt: Date?
    /// `active` or `unlinked`; unlinked rows stay for history and are hidden.
    public let linkStatus: String?

    public var id: String { transaction.id }
    public var isActive: Bool { linkStatus == nil || linkStatus == "active" }

    private enum CodingKeys: String, CodingKey { case link = "SubscriptionTransactions" }
    private struct Link: Decodable {
        let matchSource: String?
        let matchedAt: Date?
        let status: String?
    }

    public init(from decoder: any Decoder) throws {
        transaction = try Transaction(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let link = try? container.decodeIfPresent(Link.self, forKey: .link)
        matchSource = link?.matchSource
        matchedAt = link?.matchedAt
        linkStatus = link?.status
    }
}

/// `GET /subscriptions/:id`.
public struct RecurringSubscriptionDetail: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let type: SubscriptionType
    public let transactionType: TransactionType
    public let expectedAmount: Decimal?
    public let expectedCurrencyCode: String?
    public let frequency: SubscriptionFrequency
    public let startDate: CalendarDate?
    public let endDate: CalendarDate?
    public let accountId: String?
    public let categoryId: String?
    public let payeeId: String?
    public let tagIds: [String]
    public let matchingRules: RecurringMatchingRules
    public let isActive: Bool
    public let notes: String?
    public let dueDate: CalendarDate?
    public let maxOccurrences: Int?
    public let completedAt: Date?
    public let autoRecord: Bool
    public let remindBefore: [RecurringRemindPreset]
    public let notifyEmail: Bool
    public let logoDomain: String?
    public let logoInitials: String?
    public let logoColor: String?
    public let nextExpectedDate: CalendarDate?
    public let periods: [RecurringPeriod]
    public let account: SubscriptionListItem.AccountRef?
    public let category: SubscriptionListItem.CategoryRef?
    public let transactions: [RecurringLinkedTransaction]

    private enum CodingKeys: String, CodingKey {
        case id, name, type, transactionType, expectedAmount, expectedCurrencyCode, frequency, startDate, endDate
        case accountId, categoryId, payeeId, tagIds, matchingRules, isActive, notes, dueDate, maxOccurrences
        case completedAt, autoRecord, remindBefore, notifyEmail, logoDomain, logoInitials, logoColor
        case nextExpectedDate, periods, account, category, transactions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeLenient(SubscriptionType.self, forKey: .type, default: .subscription)
        transactionType = try container.decodeLenient(TransactionType.self, forKey: .transactionType, default: .expense)
        expectedAmount = try container.decodeIfPresent(Decimal.self, forKey: .expectedAmount)
        expectedCurrencyCode = try container.decodeIfPresent(String.self, forKey: .expectedCurrencyCode)
        frequency = try container.decodeLenient(SubscriptionFrequency.self, forKey: .frequency, default: .unknown)
        startDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .startDate)
        endDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .endDate)
        accountId = try container.decodeIfPresent(String.self, forKey: .accountId)
        categoryId = try container.decodeIfPresent(String.self, forKey: .categoryId)
        payeeId = try container.decodeIfPresent(String.self, forKey: .payeeId)
        tagIds = try container.decodeIfPresent([String].self, forKey: .tagIds) ?? []
        matchingRules = (try? container.decodeIfPresent(RecurringMatchingRules.self, forKey: .matchingRules)) ?? RecurringMatchingRules()
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        dueDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .dueDate)
        maxOccurrences = try container.decodeIfPresent(Int.self, forKey: .maxOccurrences)
        completedAt = try? container.decodeIfPresent(Date.self, forKey: .completedAt)
        autoRecord = try container.decodeIfPresent(Bool.self, forKey: .autoRecord) ?? false
        remindBefore = (try container.decodeIfPresent([RecurringRemindPreset].self, forKey: .remindBefore) ?? [])
            .filter { $0 != .unknown }
        notifyEmail = try container.decodeIfPresent(Bool.self, forKey: .notifyEmail) ?? false
        logoDomain = try container.decodeIfPresent(String.self, forKey: .logoDomain)
        logoInitials = try container.decodeIfPresent(String.self, forKey: .logoInitials)
        logoColor = try container.decodeIfPresent(String.self, forKey: .logoColor)
        nextExpectedDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .nextExpectedDate)
        periods = try container.decodeLossyArrayIfPresent([RecurringPeriod].self, forKey: .periods) ?? []
        account = try? container.decodeIfPresent(SubscriptionListItem.AccountRef.self, forKey: .account)
        category = try? container.decodeIfPresent(SubscriptionListItem.CategoryRef.self, forKey: .category)
        transactions = try container.decodeLossyArrayIfPresent([RecurringLinkedTransaction].self, forKey: .transactions) ?? []
    }

    public var automationMode: RecurringAutomationMode {
        RecurringAutomationMode(autoRecord: autoRecord, rules: matchingRules.rules)
    }

    /// A finished installment: deactivated by the server once its schedule ran out.
    public var isCompleted: Bool { completedAt != nil }

    /// The earliest open (upcoming or overdue) period, which mark-paid and skip act on.
    public var currentPeriod: RecurringPeriod? {
        periods.filter(\.isOpen).min { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    public var activeTransactions: [RecurringLinkedTransaction] { transactions.filter(\.isActive) }

    public var paidPeriodsCount: Int { periods.filter { $0.status == .paid }.count }
}

extension CalendarDate {
    fileprivate static let distantFuture = CalendarDate(year: 9999, month: 12, day: 31)
}

/// The bare subscription row returned by create, update, and toggle.
public struct RecurringSubscriptionRef: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let isActive: Bool

    private enum CodingKeys: String, CodingKey { case id, name, isActive }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }
}

/// `GET /subscriptions/:id/pay-preview`.
public struct RecurringPayPreview: Sendable, Hashable, Decodable {
    public let isCrossCurrency: Bool
    public let accountCurrencyCode: String?
    public let subscriptionCurrencyCode: String?
    public let expectedAmount: Decimal?
    /// The billed amount in the account currency at today's rate.
    public let convertedAmount: Decimal?

    private enum CodingKeys: String, CodingKey {
        case isCrossCurrency, accountCurrencyCode, subscriptionCurrencyCode, expectedAmount, convertedAmount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isCrossCurrency = try container.decodeIfPresent(Bool.self, forKey: .isCrossCurrency) ?? false
        accountCurrencyCode = try container.decodeIfPresent(String.self, forKey: .accountCurrencyCode)
        subscriptionCurrencyCode = try container.decodeIfPresent(String.self, forKey: .subscriptionCurrencyCode)
        expectedAmount = try container.decodeIfPresent(Decimal.self, forKey: .expectedAmount)
        convertedAmount = try container.decodeIfPresent(Decimal.self, forKey: .convertedAmount)
    }

    /// The amount to pre-fill when booking the payment.
    public var suggestedAmount: Decimal? { convertedAmount ?? expectedAmount }
}

public enum RecurringCandidateStatus: String, LenientEnum, CaseIterable {
    case pending
    case accepted
    case dismissed
    case unknown
}

/// A recurring pattern detected in the user's transactions.
public struct RecurringCandidate: Sendable, Hashable, Identifiable, Decodable {
    public struct PossibleMatch: Sendable, Hashable, Decodable {
        public let id: String
        public let name: String
    }

    public let id: String
    public let suggestedName: String
    public let detectedFrequency: SubscriptionFrequency
    public let averageAmount: Decimal
    public let currencyCode: String
    public let accountId: String?
    public let sampleTransactionIds: [String]
    public let occurrenceCount: Int
    /// 0...1.
    public let confidenceScore: Double
    public let medianIntervalDays: Int
    public let status: RecurringCandidateStatus
    public let detectedAt: Date?
    /// An existing subscription the pattern probably belongs to.
    public let possibleMatch: PossibleMatch?
    /// The pattern stopped recurring; shown separately.
    public let isOutdated: Bool

    private enum CodingKeys: String, CodingKey {
        case id, suggestedName, detectedFrequency, averageAmount, currencyCode, accountId, sampleTransactionIds
        case occurrenceCount, confidenceScore, medianIntervalDays, status, detectedAt, possibleMatch, isOutdated
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        suggestedName = try container.decodeIfPresent(String.self, forKey: .suggestedName) ?? ""
        detectedFrequency = try container.decodeLenient(SubscriptionFrequency.self, forKey: .detectedFrequency, default: .unknown)
        averageAmount = try container.decodeIfPresent(Decimal.self, forKey: .averageAmount) ?? 0
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? ""
        accountId = try container.decodeIfPresent(String.self, forKey: .accountId)
        sampleTransactionIds = try container.decodeIfPresent([String].self, forKey: .sampleTransactionIds) ?? []
        occurrenceCount = try container.decodeIfPresent(Int.self, forKey: .occurrenceCount) ?? 0
        confidenceScore = try container.decodeIfPresent(Double.self, forKey: .confidenceScore) ?? 0
        medianIntervalDays = Int(try container.decodeIfPresent(Double.self, forKey: .medianIntervalDays) ?? 0)
        status = try container.decodeLenient(RecurringCandidateStatus.self, forKey: .status, default: .pending)
        detectedAt = try? container.decodeIfPresent(Date.self, forKey: .detectedAt)
        possibleMatch = try? container.decodeIfPresent(PossibleMatch.self, forKey: .possibleMatch)
        isOutdated = try container.decodeIfPresent(Bool.self, forKey: .isOutdated) ?? false
    }
}

/// `GET /subscriptions/detect-candidates`.
public struct RecurringCandidatesResponse: Sendable, Hashable, Decodable {
    public let candidates: [RecurringCandidate]
    public let lastRunAt: Date?
    public let isFromCache: Bool

    private enum CodingKeys: String, CodingKey { case candidates, lastRunAt, isFromCache }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        candidates = try container.decodeLossyArrayIfPresent([RecurringCandidate].self, forKey: .candidates) ?? []
        lastRunAt = try? container.decodeIfPresent(Date.self, forKey: .lastRunAt)
        isFromCache = try container.decodeIfPresent(Bool.self, forKey: .isFromCache) ?? false
    }
}

/// `{id, status}` from accepting or dismissing a candidate.
public struct RecurringCandidateResolution: Sendable, Hashable, Decodable {
    public let id: String
    public let status: RecurringCandidateStatus
}

/// List sections, mirroring the web's grouping: by due date when sorted by due date, otherwise
/// a flat active list; paused subscriptions always come last.
public enum RecurringGroupKey: String, Sendable, Hashable, CaseIterable {
    case overdue
    case dueSoon
    case thisMonth
    case later
    case noSchedule
    case active
    case paused
}

public struct RecurringGroup: Sendable, Hashable, Identifiable {
    public let key: RecurringGroupKey
    public let items: [SubscriptionListItem]
    public var id: RecurringGroupKey { key }
}

public enum RecurringGrouping {
    static let dueSoonMaxDays = 7

    public static func days(until due: CalendarDate, today: CalendarDate, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: today.startDate(in: calendar), to: due.startDate(in: calendar)).day ?? 0
    }

    /// Overdue when the open period is stored overdue or the next date already passed.
    public static func isOverdue(_ item: SubscriptionListItem, today: CalendarDate, calendar: Calendar = .current) -> Bool {
        if item.currentPeriod?.status == .overdue { return true }
        guard let due = item.nextDueDate else { return false }
        return due < today
    }

    public static func key(
        for item: SubscriptionListItem,
        sortBy: RecurringSortKey,
        today: CalendarDate,
        calendar: Calendar = .current
    ) -> RecurringGroupKey {
        if !item.isActive { return .paused }
        guard sortBy == .dueDate else { return .active }
        if isOverdue(item, today: today, calendar: calendar) { return .overdue }
        guard let due = item.nextDueDate else { return .noSchedule }
        if days(until: due, today: today, calendar: calendar) <= dueSoonMaxDays { return .dueSoon }
        if due.year == today.year && due.month == today.month { return .thisMonth }
        return .later
    }

    /// Groups in display order, keeping the server's order inside each group and dropping empties.
    public static func group(
        _ items: [SubscriptionListItem],
        sortBy: RecurringSortKey,
        today: CalendarDate,
        calendar: Calendar = .current
    ) -> [RecurringGroup] {
        let order: [RecurringGroupKey] = sortBy == .dueDate
            ? [.overdue, .dueSoon, .thisMonth, .later, .noSchedule, .paused]
            : [.active, .paused]
        let keyed = items.map { ($0, key(for: $0, sortBy: sortBy, today: today, calendar: calendar)) }
        return order.compactMap { groupKey in
            let members = keyed.filter { $0.1 == groupKey }.map(\.0)
            return members.isEmpty ? nil : RecurringGroup(key: groupKey, items: members)
        }
    }
}
