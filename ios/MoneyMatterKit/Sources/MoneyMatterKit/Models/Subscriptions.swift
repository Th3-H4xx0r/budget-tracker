import Foundation

/// `GET /subscriptions/upcoming`.
public struct UpcomingPayment: Sendable, Hashable, Identifiable, Decodable {
    public let subscriptionId: String
    public let subscriptionName: String
    public let logoDomain: String?
    public let logoInitials: String?
    public let logoColor: String?
    public let expectedAmount: Decimal?
    public let expectedCurrencyCode: String?
    public let transactionType: TransactionType
    public let nextPaymentDate: CalendarDate?
    public let frequency: SubscriptionFrequency
    public let categoryName: String?
    public let categoryColor: String?

    public var id: String { subscriptionId }

    private enum CodingKeys: String, CodingKey {
        case subscriptionId, subscriptionName, logoDomain, logoInitials, logoColor, expectedAmount
        case expectedCurrencyCode, transactionType, nextPaymentDate, frequency, categoryName, categoryColor
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        subscriptionName = try container.decodeIfPresent(String.self, forKey: .subscriptionName) ?? ""
        logoDomain = try container.decodeIfPresent(String.self, forKey: .logoDomain)
        logoInitials = try container.decodeIfPresent(String.self, forKey: .logoInitials)
        logoColor = try container.decodeIfPresent(String.self, forKey: .logoColor)
        expectedAmount = try container.decodeIfPresent(Decimal.self, forKey: .expectedAmount)
        expectedCurrencyCode = try container.decodeIfPresent(String.self, forKey: .expectedCurrencyCode)
        transactionType = try container.decodeLenient(TransactionType.self, forKey: .transactionType, default: .expense)
        nextPaymentDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .nextPaymentDate)
        frequency = try container.decodeLenient(SubscriptionFrequency.self, forKey: .frequency, default: .unknown)
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        categoryColor = try container.decodeIfPresent(String.self, forKey: .categoryColor)
    }
}

/// `GET /subscriptions` item, trimmed to what the app shows.
public struct SubscriptionListItem: Sendable, Hashable, Identifiable, Decodable {
    public struct AccountRef: Sendable, Hashable, Decodable {
        public let id: String
        public let name: String
        public let currencyCode: String?
    }

    public struct CategoryRef: Sendable, Hashable, Decodable {
        public let id: String
        public let name: String
        public let color: String?
        public let icon: String?
    }

    /// The earliest open period.
    public struct Period: Sendable, Hashable, Decodable {
        public let id: String
        public let dueDate: CalendarDate
        public let status: SubscriptionPeriodStatus
    }

    public let id: String
    public let name: String
    public let type: SubscriptionType
    public let isActive: Bool
    public let expectedAmount: Decimal?
    public let expectedCurrencyCode: String?
    public let frequency: SubscriptionFrequency
    public let transactionType: TransactionType
    public let logoDomain: String?
    public let logoInitials: String?
    public let logoColor: String?
    public let account: AccountRef?
    public let category: CategoryRef?
    public let currentPeriod: Period?
    public let nextDueDate: CalendarDate?
    public let paidPeriodsCount: Int?
    public let maxOccurrences: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, type, isActive, expectedAmount, expectedCurrencyCode, frequency, transactionType
        case logoDomain, logoInitials, logoColor, account, category, currentPeriod, nextDueDate
        case paidPeriodsCount, maxOccurrences
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeLenient(SubscriptionType.self, forKey: .type, default: .subscription)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        expectedAmount = try container.decodeIfPresent(Decimal.self, forKey: .expectedAmount)
        expectedCurrencyCode = try container.decodeIfPresent(String.self, forKey: .expectedCurrencyCode)
        frequency = try container.decodeLenient(SubscriptionFrequency.self, forKey: .frequency, default: .unknown)
        transactionType = try container.decodeLenient(TransactionType.self, forKey: .transactionType, default: .expense)
        logoDomain = try container.decodeIfPresent(String.self, forKey: .logoDomain)
        logoInitials = try container.decodeIfPresent(String.self, forKey: .logoInitials)
        logoColor = try container.decodeIfPresent(String.self, forKey: .logoColor)
        account = try? container.decodeIfPresent(AccountRef.self, forKey: .account)
        category = try? container.decodeIfPresent(CategoryRef.self, forKey: .category)
        currentPeriod = try? container.decodeIfPresent(Period.self, forKey: .currentPeriod)
        nextDueDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .nextDueDate)
        paidPeriodsCount = try container.decodeIfPresent(Int.self, forKey: .paidPeriodsCount)
        maxOccurrences = try container.decodeIfPresent(Int.self, forKey: .maxOccurrences)
    }

    public var isOverdue: Bool { currentPeriod?.status == .overdue }

    /// Overdue, or upcoming within `days` of `today`: the Home "upcoming payments" rule.
    public func needsAttention(today: CalendarDate, withinDays days: Int = 3, calendar: Calendar = .current) -> Bool {
        if isOverdue { return true }
        guard let due = currentPeriod?.dueDate ?? nextDueDate else { return false }
        return due <= today.adding(days: days, calendar: calendar)
    }
}

/// `GET /subscriptions/summary`. Amounts are in `currencyCode` (the base currency).
public struct SubscriptionsSummary: Sendable, Hashable, Decodable {
    public struct ActiveCount: Sendable, Hashable, Decodable {
        public let expense: Int
        public let income: Int
    }

    public let estimatedMonthlyCost: Decimal
    public let projectedYearlyCost: Decimal
    public let expectedMonthlyIncome: Decimal
    public let activeCount: ActiveCount
    public let currencyCode: String
    public let averageMonthlyIncome: Decimal?
    public let percentOfIncome: Decimal?
    public let lookbackMonths: Int?
}
