// Trends comparison stats: `GET /stats/cumulative`, filtered category spending, and the
// report's include/exclude filters.
import Foundation

/// What the trends report measures.
public enum TrendsMetric: String, LenientEnum, CaseIterable {
    case expenses
    case income
    case savings
    case unknown

    public static var allCases: [TrendsMetric] { [.expenses, .income, .savings] }

    /// The category type the breakdown lists for this metric (savings has none).
    public var categoryType: TransactionType? {
        switch self {
        case .income: .income
        case .expenses: .expense
        case .savings, .unknown: nil
        }
    }

    /// Whether a rise in this metric is good news (more income or savings), else bad (more spending).
    public var increaseIsGood: Bool { self != .expenses }
}

/// One month of a cumulative series. `value` is the running total; `periodValue` is
/// the month on its own.
public struct CumulativeMonthPoint: Sendable, Hashable, Decodable {
    /// 1-based position within the period.
    public let month: Int
    public let monthLabel: String
    public let value: Decimal
    public let periodValue: Decimal

    public init(month: Int, monthLabel: String, value: Decimal, periodValue: Decimal) {
        self.month = month
        self.monthLabel = monthLabel
        self.value = value
        self.periodValue = periodValue
    }

    private enum CodingKeys: String, CodingKey {
        case month, monthLabel, value, periodValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        month = try container.decode(Int.self, forKey: .month)
        monthLabel = try container.decodeIfPresent(String.self, forKey: .monthLabel) ?? ""
        value = try container.decodeIfPresent(Decimal.self, forKey: .value) ?? 0
        periodValue = try container.decodeIfPresent(Decimal.self, forKey: .periodValue) ?? 0
    }
}

/// One side of the comparison: the selected period or the one before it.
public struct CumulativePeriodSeries: Sendable, Hashable, Decodable {
    public let year: Int
    public let data: [CumulativeMonthPoint]
    public let total: Decimal

    public init(year: Int, data: [CumulativeMonthPoint], total: Decimal) {
        self.year = year
        self.data = data
        self.total = total
    }

    private enum CodingKeys: String, CodingKey {
        case year, data, total
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        year = try container.decodeIfPresent(Int.self, forKey: .year) ?? 0
        data = (try container.decodeLossyArrayIfPresent([CumulativeMonthPoint].self, forKey: .data) ?? [])
            .sorted { $0.month < $1.month }
        total = try container.decodeIfPresent(Decimal.self, forKey: .total) ?? 0
    }
}

/// `GET /stats/cumulative`: running totals for the period and the equally long period
/// before it, plus the whole-number percent change between their totals.
public struct CumulativeReport: Sendable, Hashable, Decodable {
    public let currentPeriod: CumulativePeriodSeries
    public let previousPeriod: CumulativePeriodSeries
    public let percentChange: Decimal

    public init(currentPeriod: CumulativePeriodSeries, previousPeriod: CumulativePeriodSeries, percentChange: Decimal) {
        self.currentPeriod = currentPeriod
        self.previousPeriod = previousPeriod
        self.percentChange = percentChange
    }

    private enum CodingKeys: String, CodingKey {
        case currentPeriod, previousPeriod, percentChange
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentPeriod = try container.decode(CumulativePeriodSeries.self, forKey: .currentPeriod)
        previousPeriod = try container.decode(CumulativePeriodSeries.self, forKey: .previousPeriod)
        percentChange = try container.decodeIfPresent(Decimal.self, forKey: .percentChange) ?? 0
    }

    public var hasData: Bool { !currentPeriod.data.isEmpty || !previousPeriod.data.isEmpty }
}

/// An include-or-exclude id list. An empty include list means "everything".
public struct TrendsFilterGroup: Sendable, Hashable, Codable {
    public enum Mode: String, Sendable, Hashable, Codable, CaseIterable {
        case include
        case exclude
    }

    public var mode: Mode
    public var ids: [String]

    public init(mode: Mode = .include, ids: [String] = []) {
        self.mode = mode
        self.ids = ids
    }
}

/// The trends report's filters, mirroring the web `TrendsFilters`.
public struct TrendsFilterSelection: Sendable, Hashable, Codable {
    public var categories: TrendsFilterGroup
    public var payees: TrendsFilterGroup
    public var tags: TrendsFilterGroup
    public var accountIds: [String]

    public init(
        categories: TrendsFilterGroup = TrendsFilterGroup(),
        payees: TrendsFilterGroup = TrendsFilterGroup(),
        tags: TrendsFilterGroup = TrendsFilterGroup(),
        accountIds: [String] = []
    ) {
        self.categories = categories
        self.payees = payees
        self.tags = tags
        self.accountIds = accountIds
    }

    public var activeCount: Int {
        [categories.ids, payees.ids, tags.ids, accountIds].filter { !$0.isEmpty }.count
    }

    /// The query filters: each group goes to its include or exclude list.
    public var reportFilters: InsightsReportFilters {
        var filters = InsightsReportFilters(accountIds: accountIds)
        switch categories.mode {
        case .include: filters.categoryIds = categories.ids
        case .exclude: filters.excludedCategoryIds = categories.ids
        }
        switch payees.mode {
        case .include: filters.payeeIds = payees.ids
        case .exclude: filters.excludedPayeeIds = payees.ids
        }
        switch tags.mode {
        case .include: filters.tagIds = tags.ids
        case .exclude: filters.excludedTagIds = tags.ids
        }
        return filters
    }

    /// Drops one category from the report. An include list that would become empty (which
    /// means "all") flips to excluding just that category.
    public func hidingCategory(_ categoryID: String) -> TrendsFilterSelection {
        var copy = self
        switch categories.mode {
        case .exclude:
            if !categories.ids.contains(categoryID) { copy.categories.ids.append(categoryID) }
        case .include:
            let remaining = categories.ids.filter { $0 != categoryID }
            copy.categories = remaining.isEmpty
                ? TrendsFilterGroup(mode: .exclude, ids: [categoryID])
                : TrendsFilterGroup(mode: .include, ids: remaining)
        }
        return copy
    }

    /// Brings back a category hidden by an exclude list.
    public func showingCategory(_ categoryID: String) -> TrendsFilterSelection {
        guard categories.mode == .exclude else { return self }
        var copy = self
        copy.categories.ids.removeAll { $0 == categoryID }
        return copy
    }
}

extension Endpoints {
    /// `GET /stats/cumulative`.
    public static func cumulativeData(
        from: CalendarDate,
        to: CalendarDate,
        metric: TrendsMetric,
        accountId: String? = nil,
        filters: InsightsReportFilters = InsightsReportFilters()
    ) -> Endpoint<CumulativeReport> {
        var query = QueryBuilder()
        query.add("from", day: from)
        query.add("to", day: to)
        query.add("metric", metric == .unknown ? TrendsMetric.expenses.rawValue : metric.rawValue)
        query.add("accountId", accountId)
        filters.apply(to: &query)
        return Endpoint(.get, "/stats/cumulative", query: query.items)
    }

    /// `GET /stats/spendings-by-categories` with the report filters, sorted largest first.
    public static func filteredSpendingsByCategories(
        from: CalendarDate,
        to: CalendarDate,
        type: TransactionType,
        filters: InsightsReportFilters = InsightsReportFilters()
    ) -> Endpoint<[CategorySpending]> {
        var query = QueryBuilder()
        query.add("from", day: from)
        query.add("to", day: to)
        if type != .unknown { query.add("type", type.rawValue) }
        filters.apply(to: &query)
        return Endpoint<CategorySpendingMap>(.get, "/stats/spendings-by-categories", query: query.items).map(\.items)
    }
}
