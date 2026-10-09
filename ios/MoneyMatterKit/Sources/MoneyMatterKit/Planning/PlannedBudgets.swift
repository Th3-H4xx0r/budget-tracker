import Foundation

// MARK: - Enums

/// How often a salary or plan-only entry repeats. `custom` uses an explicit day interval.
public enum PlannedBudgetFrequency: String, LenientEnum, CaseIterable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case semiAnnual = "semi_annual"
    case annual
    case custom
    case unknown
}

public enum PlannedBudgetKind: String, LenientEnum, CaseIterable {
    case manual
    case category
    case unknown
}

public enum PlannedBudgetStatus: String, LenientEnum, CaseIterable {
    case active
    case archived
    case unknown
}

/// Where a projected occurrence comes from: the plan's salary, an active bank-derived
/// recurring payment, or a plan-only entry.
public enum PlannedBudgetSource: String, LenientEnum, CaseIterable {
    case salary
    case recurring
    case manual
    case unknown
}

// MARK: - Models

/// `GET /future-budgets` item and the `plan` of `GET /future-budgets/:id`.
public struct PlannedBudgetPlan: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let type: PlannedBudgetKind
    public let status: PlannedBudgetStatus
    public let startDate: CalendarDate
    public let endDate: CalendarDate
    public let salaryAmount: Decimal
    public let salaryFrequency: PlannedBudgetFrequency
    public let salaryIntervalDays: Int?
    public let salaryAnchorDate: CalendarDate?
    public let salaryCategoryId: String?
    public let salaryProfileRevision: Int?
    public let dismissedSalaryProfileRevision: Int?
    public let autoAddSyncedTransactions: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, type, status, startDate, endDate, salaryAmount, salaryFrequency, salaryIntervalDays
        case salaryAnchorDate, salaryCategoryId, salaryProfileRevision, dismissedSalaryProfileRevision
        case autoAddSyncedTransactions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeLenient(PlannedBudgetKind.self, forKey: .type, default: .manual)
        status = try container.decodeLenient(PlannedBudgetStatus.self, forKey: .status, default: .active)
        startDate = try container.decode(CalendarDate.self, forKey: .startDate)
        endDate = try container.decode(CalendarDate.self, forKey: .endDate)
        salaryAmount = try container.decodeIfPresent(Decimal.self, forKey: .salaryAmount) ?? 0
        salaryFrequency = try container.decodeLenient(PlannedBudgetFrequency.self, forKey: .salaryFrequency, default: .monthly)
        salaryIntervalDays = try container.decodeIfPresent(Int.self, forKey: .salaryIntervalDays)
        salaryAnchorDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .salaryAnchorDate)
        salaryCategoryId = try container.decodeIfPresent(String.self, forKey: .salaryCategoryId)
        salaryProfileRevision = try container.decodeIfPresent(Int.self, forKey: .salaryProfileRevision)
        dismissedSalaryProfileRevision = try container.decodeIfPresent(Int.self, forKey: .dismissedSalaryProfileRevision)
        autoAddSyncedTransactions = try container.decodeIfPresent(Bool.self, forKey: .autoAddSyncedTransactions) ?? false
    }

    public var isArchived: Bool { status == .archived }
}

/// `GET /future-budgets/salary-settings`: the default salary profile for new plans.
public struct PlannedBudgetSalarySettings: Sendable, Hashable, Decodable {
    public let salaryAmount: Decimal
    public let salaryFrequency: PlannedBudgetFrequency
    public let salaryIntervalDays: Int?
    public let salaryAnchorDate: CalendarDate?
    public let salaryCategoryId: String?
    public let revision: Int

    private enum CodingKeys: String, CodingKey {
        case salaryAmount, salaryFrequency, salaryIntervalDays, salaryAnchorDate, salaryCategoryId, revision
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        salaryAmount = try container.decodeIfPresent(Decimal.self, forKey: .salaryAmount) ?? 0
        salaryFrequency = try container.decodeLenient(PlannedBudgetFrequency.self, forKey: .salaryFrequency, default: .monthly)
        salaryIntervalDays = try container.decodeIfPresent(Int.self, forKey: .salaryIntervalDays)
        salaryAnchorDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .salaryAnchorDate)
        salaryCategoryId = try container.decodeIfPresent(String.self, forKey: .salaryCategoryId)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 1
    }
}

/// A plan-only future transaction. It never touches real transactions.
public struct PlannedBudgetEntry: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let transactionType: TransactionType
    public let amount: Decimal
    public let date: CalendarDate
    public let categoryId: String?
    public let note: String?
    /// Nil for a one-time entry.
    public let frequency: PlannedBudgetFrequency?
    public let intervalDays: Int?

    private enum CodingKeys: String, CodingKey {
        case id, transactionType, amount, date, categoryId, note, frequency, intervalDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        transactionType = try container.decodeLenient(TransactionType.self, forKey: .transactionType, default: .expense)
        amount = try container.decodeIfPresent(Decimal.self, forKey: .amount) ?? 0
        date = try container.decode(CalendarDate.self, forKey: .date)
        categoryId = try container.decodeIfPresent(String.self, forKey: .categoryId)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        frequency = try container.decodeIfPresent(PlannedBudgetFrequency.self, forKey: .frequency)
        intervalDays = try container.decodeIfPresent(Int.self, forKey: .intervalDays)
    }
}

/// One projected occurrence inside the plan's date range. Salary rows have no `id`;
/// recurring rows carry `subscriptionId` and `name`; manual rows carry the entry's `id`.
public struct PlannedBudgetOccurrence: Sendable, Hashable, Decodable {
    public let source: PlannedBudgetSource
    public let id: String?
    public let subscriptionId: String?
    public let name: String?
    public let note: String?
    public let transactionType: TransactionType
    public let amount: Decimal
    public let date: CalendarDate
    public let categoryId: String?
    public let frequency: PlannedBudgetFrequency?
    public let intervalDays: Int?

    private enum CodingKeys: String, CodingKey {
        case source, id, subscriptionId, name, note, transactionType, amount, date, categoryId, frequency, intervalDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeLenient(PlannedBudgetSource.self, forKey: .source, default: .unknown)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        subscriptionId = try container.decodeIfPresent(String.self, forKey: .subscriptionId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        transactionType = try container.decodeLenient(TransactionType.self, forKey: .transactionType, default: .expense)
        amount = try container.decodeIfPresent(Decimal.self, forKey: .amount) ?? 0
        date = try container.decode(CalendarDate.self, forKey: .date)
        categoryId = try container.decodeIfPresent(String.self, forKey: .categoryId)
        frequency = try? container.decodeIfPresent(PlannedBudgetFrequency.self, forKey: .frequency)
        intervalDays = try container.decodeIfPresent(Int.self, forKey: .intervalDays)
    }

    /// Income is positive, expense negative: the web's sort key for amounts.
    public var signedAmount: Decimal { transactionType == .income ? amount : -amount }
}

/// A plan's adjustment to one recurring payment's projection.
public struct PlannedBudgetRecurringOverride: Sendable, Hashable, Decodable {
    public let subscriptionId: String
    public let isIncluded: Bool
    public let amount: Decimal?
    public let categoryId: String?
    public let nextOccurrenceDate: CalendarDate?

    private enum CodingKeys: String, CodingKey {
        case subscriptionId, isIncluded, amount, categoryId, nextOccurrenceDate
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        isIncluded = try container.decodeIfPresent(Bool.self, forKey: .isIncluded) ?? true
        amount = try container.decodeIfPresent(Decimal.self, forKey: .amount)
        categoryId = try container.decodeIfPresent(String.self, forKey: .categoryId)
        nextOccurrenceDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .nextOccurrenceDate)
    }
}

/// `GET /future-budgets/:id`.
public struct PlannedBudgetDetails: Sendable, Hashable, Decodable {
    public struct Summary: Sendable, Hashable, Decodable {
        public let income: Decimal
        public let expense: Decimal
        public let net: Decimal
    }

    public let plan: PlannedBudgetPlan
    public let categoryIds: [String]
    public let entries: [PlannedBudgetEntry]
    public let overrides: [PlannedBudgetRecurringOverride]
    public let occurrences: [PlannedBudgetOccurrence]
    public let summary: Summary
    public let salaryProfileChanged: Bool
    public let salarySettings: PlannedBudgetSalarySettings?

    private enum CodingKeys: String, CodingKey {
        case plan, categoryIds, entries, overrides, occurrences, summary, salaryProfileChanged, salarySettings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decode(PlannedBudgetPlan.self, forKey: .plan)
        categoryIds = try container.decodeIfPresent([String].self, forKey: .categoryIds) ?? []
        entries = try container.decodeLossyArrayIfPresent([PlannedBudgetEntry].self, forKey: .entries) ?? []
        overrides = try container.decodeLossyArrayIfPresent([PlannedBudgetRecurringOverride].self, forKey: .overrides) ?? []
        occurrences = try container.decodeLossyArrayIfPresent([PlannedBudgetOccurrence].self, forKey: .occurrences) ?? []
        summary = try container.decodeIfPresent(Summary.self, forKey: .summary) ?? Summary(income: 0, expense: 0, net: 0)
        salaryProfileChanged = try container.decodeIfPresent(Bool.self, forKey: .salaryProfileChanged) ?? false
        salarySettings = try? container.decodeIfPresent(PlannedBudgetSalarySettings.self, forKey: .salarySettings)
    }

    public func entry(id: String?) -> PlannedBudgetEntry? {
        guard let id else { return nil }
        return entries.first { $0.id == id }
    }
}

// MARK: - Requests

/// The salary fields shared by plan creation and `PUT /future-budgets/salary-settings`.
public struct PlannedBudgetSalaryProfile: Sendable, Hashable {
    public var salaryAmount: Decimal
    public var salaryFrequency: PlannedBudgetFrequency
    /// Only sent for `custom`.
    public var salaryIntervalDays: Int?
    public var salaryAnchorDate: CalendarDate?
    public var salaryCategoryId: String?

    public init(
        salaryAmount: Decimal = 0,
        salaryFrequency: PlannedBudgetFrequency = .monthly,
        salaryIntervalDays: Int? = nil,
        salaryAnchorDate: CalendarDate? = nil,
        salaryCategoryId: String? = nil
    ) {
        self.salaryAmount = salaryAmount
        self.salaryFrequency = salaryFrequency
        self.salaryIntervalDays = salaryIntervalDays
        self.salaryAnchorDate = salaryAnchorDate
        self.salaryCategoryId = salaryCategoryId
    }

    public init(_ settings: PlannedBudgetSalarySettings) {
        self.init(
            salaryAmount: settings.salaryAmount,
            salaryFrequency: settings.salaryFrequency == .unknown ? .monthly : settings.salaryFrequency,
            salaryIntervalDays: settings.salaryIntervalDays,
            salaryAnchorDate: settings.salaryAnchorDate,
            salaryCategoryId: settings.salaryCategoryId
        )
    }

    fileprivate func encode<Key: CodingKey>(into container: inout KeyedEncodingContainer<Key>, keys: SalaryKeys<Key>) throws {
        try container.encode(salaryAmount, forKey: keys.amount)
        try container.encode(salaryFrequency, forKey: keys.frequency)
        if salaryFrequency == .custom, let salaryIntervalDays {
            try container.encode(salaryIntervalDays, forKey: keys.intervalDays)
        } else {
            try container.encodeNil(forKey: keys.intervalDays)
        }
        try container.encode(salaryAnchorDate, forKey: keys.anchorDate)
        try container.encode(salaryCategoryId, forKey: keys.categoryId)
    }
}

fileprivate struct SalaryKeys<Key: CodingKey> {
    let amount: Key
    let frequency: Key
    let intervalDays: Key
    let anchorDate: Key
    let categoryId: Key
}

/// `PUT /future-budgets/salary-settings` body. Nil optional fields are sent as `null`.
public struct PlannedBudgetSalarySettingsRequest: Encodable, Sendable, Hashable {
    public var profile: PlannedBudgetSalaryProfile

    public init(profile: PlannedBudgetSalaryProfile) {
        self.profile = profile
    }

    private enum CodingKeys: String, CodingKey {
        case salaryAmount, salaryFrequency, salaryIntervalDays, salaryAnchorDate, salaryCategoryId
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try profile.encode(into: &container, keys: SalaryKeys(
            amount: .salaryAmount, frequency: .salaryFrequency, intervalDays: .salaryIntervalDays,
            anchorDate: .salaryAnchorDate, categoryId: .salaryCategoryId
        ))
    }
}

/// `POST /future-budgets` body. Category plans need at least one category.
public struct PlannedBudgetCreateRequest: Encodable, Sendable, Hashable {
    public var name: String
    public var type: PlannedBudgetKind
    public var categoryIds: [String]
    public var startDate: CalendarDate
    public var endDate: CalendarDate
    public var salary: PlannedBudgetSalaryProfile

    public init(
        name: String,
        type: PlannedBudgetKind,
        categoryIds: [String],
        startDate: CalendarDate,
        endDate: CalendarDate,
        salary: PlannedBudgetSalaryProfile
    ) {
        self.name = name
        self.type = type
        self.categoryIds = categoryIds
        self.startDate = startDate
        self.endDate = endDate
        self.salary = salary
    }

    private enum CodingKeys: String, CodingKey {
        case name, type, categoryIds, startDate, endDate
        case salaryAmount, salaryFrequency, salaryIntervalDays, salaryAnchorDate, salaryCategoryId
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(type == .category ? categoryIds : [], forKey: .categoryIds)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try salary.encode(into: &container, keys: SalaryKeys(
            amount: .salaryAmount, frequency: .salaryFrequency, intervalDays: .salaryIntervalDays,
            anchorDate: .salaryAnchorDate, categoryId: .salaryCategoryId
        ))
    }
}

/// `PUT /future-budgets/:id` body. Nil fields are left out.
public struct PlannedBudgetUpdateRequest: Encodable, Sendable, Hashable {
    public var name: String?
    public var status: PlannedBudgetStatus?
    public var autoAddSyncedTransactions: Bool?

    public init(name: String? = nil, status: PlannedBudgetStatus? = nil, autoAddSyncedTransactions: Bool? = nil) {
        self.name = name
        self.status = status
        self.autoAddSyncedTransactions = autoAddSyncedTransactions
    }
}

/// `POST /future-budgets/:id/entries` and `PUT /future-budgets/:id/entries/:entryId` body.
/// Every field is sent; nil optionals go out as `null` so an edit can clear them.
public struct PlannedBudgetEntryRequest: Encodable, Sendable, Hashable {
    public var transactionType: TransactionType
    public var amount: Decimal
    public var date: CalendarDate
    public var categoryId: String?
    public var note: String?
    /// Nil for a one-time entry.
    public var frequency: PlannedBudgetFrequency?
    /// Only sent for `custom`.
    public var intervalDays: Int?

    public init(
        transactionType: TransactionType,
        amount: Decimal,
        date: CalendarDate,
        categoryId: String? = nil,
        note: String? = nil,
        frequency: PlannedBudgetFrequency? = nil,
        intervalDays: Int? = nil
    ) {
        self.transactionType = transactionType
        self.amount = amount
        self.date = date
        self.categoryId = categoryId
        self.note = note
        self.frequency = frequency
        self.intervalDays = intervalDays
    }

    private enum CodingKeys: String, CodingKey {
        case transactionType, amount, date, categoryId, note, frequency, intervalDays
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transactionType, forKey: .transactionType)
        try container.encode(amount, forKey: .amount)
        try container.encode(date, forKey: .date)
        try container.encode(categoryId, forKey: .categoryId)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try container.encode(trimmedNote?.isEmpty == false ? trimmedNote : nil, forKey: .note)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(frequency == .custom ? intervalDays : nil, forKey: .intervalDays)
    }
}

/// `PUT /future-budgets/:id/recurring/:subscriptionId` body: one adjustment at a time.
public struct PlannedBudgetRecurringOverrideRequest: Encodable, Sendable, Hashable {
    public var isIncluded: Bool?
    public var amount: FieldUpdate<Decimal>
    public var categoryId: FieldUpdate<String>
    public var nextOccurrenceDate: FieldUpdate<CalendarDate>

    public init(
        isIncluded: Bool? = nil,
        amount: FieldUpdate<Decimal> = .unchanged,
        categoryId: FieldUpdate<String> = .unchanged,
        nextOccurrenceDate: FieldUpdate<CalendarDate> = .unchanged
    ) {
        self.isIncluded = isIncluded
        self.amount = amount
        self.categoryId = categoryId
        self.nextOccurrenceDate = nextOccurrenceDate
    }

    private enum CodingKeys: String, CodingKey {
        case isIncluded, amount, categoryId, nextOccurrenceDate
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(isIncluded, forKey: .isIncluded)
        try container.encodePlannedUpdate(amount, forKey: .amount)
        try container.encodePlannedUpdate(categoryId, forKey: .categoryId)
        try container.encodePlannedUpdate(nextOccurrenceDate, forKey: .nextOccurrenceDate)
    }
}

private struct PlannedBudgetSalaryChoice: Encodable, Sendable, Hashable {
    let apply: Bool
}

extension KeyedEncodingContainer {
    fileprivate mutating func encodePlannedUpdate<Value>(_ update: FieldUpdate<Value>, forKey key: Key) throws {
        switch update {
        case .unchanged: break
        case .clear: try encodeNil(forKey: key)
        case .set(let value): try encode(value, forKey: key)
        }
    }
}

// MARK: - Endpoints

extension Endpoints {
    /// `GET /future-budgets`, newest start date first.
    public static func plannedBudgets() -> Endpoint<[PlannedBudgetPlan]> {
        Endpoint(.get, "/future-budgets")
    }

    /// `POST /future-budgets`.
    public static func createPlannedBudget(_ request: PlannedBudgetCreateRequest) -> Endpoint<PlannedBudgetPlan> {
        Endpoint(.post, "/future-budgets", body: request)
    }

    /// `GET /future-budgets/:id`: the plan with its projected occurrences and summary.
    public static func plannedBudgetDetails(id: String) -> Endpoint<PlannedBudgetDetails> {
        Endpoint(.get, "/future-budgets/\(id)")
    }

    /// `PUT /future-budgets/:id`: rename, archive, or toggle auto-add.
    public static func updatePlannedBudget(id: String, _ request: PlannedBudgetUpdateRequest) -> Endpoint<PlannedBudgetPlan> {
        Endpoint(.put, "/future-budgets/\(id)", body: request)
    }

    /// `DELETE /future-budgets/:id`: removes the plan and its entries.
    public static func deletePlannedBudget(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/future-budgets/\(id)")
    }

    /// `GET /future-budgets/salary-settings`.
    public static func plannedBudgetSalarySettings() -> Endpoint<PlannedBudgetSalarySettings> {
        Endpoint(.get, "/future-budgets/salary-settings")
    }

    /// `PUT /future-budgets/salary-settings`. A changed profile bumps its revision, which
    /// existing plans then offer to apply.
    public static func updatePlannedBudgetSalarySettings(
        _ request: PlannedBudgetSalarySettingsRequest
    ) -> Endpoint<PlannedBudgetSalarySettings> {
        Endpoint(.put, "/future-budgets/salary-settings", body: request)
    }

    /// `POST /future-budgets/:id/salary-profile`: `apply` copies the current salary profile
    /// into the plan; otherwise this revision is dismissed for the plan.
    public static func resolvePlannedBudgetSalaryChange(id: String, apply: Bool) -> Endpoint<PlannedBudgetPlan> {
        Endpoint(.post, "/future-budgets/\(id)/salary-profile", body: PlannedBudgetSalaryChoice(apply: apply))
    }

    /// `POST /future-budgets/:id/entries`.
    public static func createPlannedBudgetEntry(planId: String, _ request: PlannedBudgetEntryRequest) -> Endpoint<PlannedBudgetEntry> {
        Endpoint(.post, "/future-budgets/\(planId)/entries", body: request)
    }

    /// `PUT /future-budgets/:id/entries/:entryId`.
    public static func updatePlannedBudgetEntry(
        planId: String,
        entryId: String,
        _ request: PlannedBudgetEntryRequest
    ) -> Endpoint<PlannedBudgetEntry> {
        Endpoint(.put, "/future-budgets/\(planId)/entries/\(entryId)", body: request)
    }

    /// `DELETE /future-budgets/:id/entries/:entryId`.
    public static func deletePlannedBudgetEntry(planId: String, entryId: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/future-budgets/\(planId)/entries/\(entryId)")
    }

    /// `PUT /future-budgets/:id/recurring/:subscriptionId`.
    public static func updatePlannedBudgetRecurring(
        planId: String,
        subscriptionId: String,
        _ request: PlannedBudgetRecurringOverrideRequest
    ) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/future-budgets/\(planId)/recurring/\(subscriptionId)", body: request)
    }
}
