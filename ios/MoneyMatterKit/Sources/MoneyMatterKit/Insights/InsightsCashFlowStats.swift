// Cash flow stats: `GET /stats/cash-flow` and the per-type
// `GET /stats/spendings-by-categories?groupByType=true`.
import Foundation

/// The scope filters shared by the stats reports (`statsScopeQuery` plus the category
/// lists on the server). Empty lists send nothing.
public struct InsightsReportFilters: Sendable, Hashable {
    public var accountIds: [String]
    public var categoryIds: [String]
    public var excludedCategoryIds: [String]
    public var payeeIds: [String]
    public var excludedPayeeIds: [String]
    public var tagIds: [String]
    public var excludedTagIds: [String]

    public init(
        accountIds: [String] = [],
        categoryIds: [String] = [],
        excludedCategoryIds: [String] = [],
        payeeIds: [String] = [],
        excludedPayeeIds: [String] = [],
        tagIds: [String] = [],
        excludedTagIds: [String] = []
    ) {
        self.accountIds = accountIds
        self.categoryIds = categoryIds
        self.excludedCategoryIds = excludedCategoryIds
        self.payeeIds = payeeIds
        self.excludedPayeeIds = excludedPayeeIds
        self.tagIds = tagIds
        self.excludedTagIds = excludedTagIds
    }

    /// How many filter groups are set, for a badge on the filters button.
    public var activeCount: Int {
        [accountIds, categoryIds, excludedCategoryIds, payeeIds, excludedPayeeIds, tagIds, excludedTagIds]
            .filter { !$0.isEmpty }
            .count
    }

    public var isEmpty: Bool { activeCount == 0 }

    func apply(to query: inout QueryBuilder) {
        query.add("accountIds", list: accountIds)
        query.add("categoryIds", list: categoryIds)
        query.add("excludedCategoryIds", list: excludedCategoryIds)
        query.add("payeeIds", list: payeeIds)
        query.add("excludedPayeeIds", list: excludedPayeeIds)
        query.add("tagIds", list: tagIds)
        query.add("excludedTagIds", list: excludedTagIds)
    }
}

/// The bucket size of `GET /stats/cash-flow`.
public enum CashFlowGranularity: String, LenientEnum, CaseIterable {
    case monthly
    case biweekly
    case weekly
    case unknown

    public static var allCases: [CashFlowGranularity] { [.monthly, .biweekly, .weekly] }
}

/// One category's share of a cash flow period. Amounts are positive.
public struct CashFlowCategoryAmount: Sendable, Hashable, Identifiable, Decodable {
    public let categoryId: String
    public let name: String
    /// `#rrggbb`.
    public let color: String
    public let incomeAmount: Decimal
    public let expenseAmount: Decimal

    public var id: String { categoryId }

    public init(categoryId: String, name: String, color: String, incomeAmount: Decimal, expenseAmount: Decimal) {
        self.categoryId = categoryId
        self.name = name
        self.color = color
        self.incomeAmount = incomeAmount
        self.expenseAmount = expenseAmount
    }

    private enum CodingKeys: String, CodingKey {
        case categoryId, name, color, incomeAmount, expenseAmount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryId = try container.decode(String.self, forKey: .categoryId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#8e8e93"
        incomeAmount = try container.decodeIfPresent(Decimal.self, forKey: .incomeAmount) ?? 0
        expenseAmount = try container.decodeIfPresent(Decimal.self, forKey: .expenseAmount) ?? 0
    }
}

/// One bucket of `GET /stats/cash-flow`, in the base currency. `expenses` is positive.
public struct CashFlowPeriod: Sendable, Hashable, Identifiable, Decodable {
    public let periodStart: CalendarDate
    public let periodEnd: CalendarDate
    public let income: Decimal
    public let expenses: Decimal
    public let netFlow: Decimal
    public let categories: [CashFlowCategoryAmount]

    public var id: CalendarDate { periodStart }

    public init(
        periodStart: CalendarDate,
        periodEnd: CalendarDate,
        income: Decimal,
        expenses: Decimal,
        netFlow: Decimal,
        categories: [CashFlowCategoryAmount] = []
    ) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.income = income
        self.expenses = expenses
        self.netFlow = netFlow
        self.categories = categories
    }

    private enum CodingKeys: String, CodingKey {
        case periodStart, periodEnd, income, expenses, netFlow, categories
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        periodStart = try container.decode(CalendarDate.self, forKey: .periodStart)
        periodEnd = try container.decodeIfPresent(CalendarDate.self, forKey: .periodEnd) ?? periodStart
        income = try container.decodeIfPresent(Decimal.self, forKey: .income) ?? 0
        expenses = try container.decodeIfPresent(Decimal.self, forKey: .expenses) ?? 0
        netFlow = try container.decodeIfPresent(Decimal.self, forKey: .netFlow) ?? (income - expenses)
        categories = try container.decodeLossyArrayIfPresent([CashFlowCategoryAmount].self, forKey: .categories) ?? []
    }
}

/// The report's totals. `savingsRate` is a whole percentage (net flow over income), 0
/// when there was no income.
public struct CashFlowTotals: Sendable, Hashable, Decodable {
    public let income: Decimal
    public let expenses: Decimal
    public let netFlow: Decimal
    public let savingsRate: Decimal

    public init(income: Decimal, expenses: Decimal, netFlow: Decimal, savingsRate: Decimal) {
        self.income = income
        self.expenses = expenses
        self.netFlow = netFlow
        self.savingsRate = savingsRate
    }

    public static let zero = CashFlowTotals(income: 0, expenses: 0, netFlow: 0, savingsRate: 0)

    private enum CodingKeys: String, CodingKey {
        case income, expenses, netFlow, savingsRate
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        income = try container.decodeIfPresent(Decimal.self, forKey: .income) ?? 0
        expenses = try container.decodeIfPresent(Decimal.self, forKey: .expenses) ?? 0
        netFlow = try container.decodeIfPresent(Decimal.self, forKey: .netFlow) ?? (income - expenses)
        savingsRate = try container.decodeIfPresent(Decimal.self, forKey: .savingsRate) ?? 0
    }
}

/// `GET /stats/cash-flow`: income and expenses per bucket, oldest first, plus totals.
public struct CashFlowReport: Sendable, Hashable, Decodable {
    public let periods: [CashFlowPeriod]
    public let totals: CashFlowTotals

    public init(periods: [CashFlowPeriod], totals: CashFlowTotals) {
        self.periods = periods
        self.totals = totals
    }

    private enum CodingKeys: String, CodingKey {
        case periods, totals
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        periods = (try container.decodeLossyArrayIfPresent([CashFlowPeriod].self, forKey: .periods) ?? [])
            .sorted { $0.periodStart < $1.periodStart }
        totals = try container.decodeIfPresent(CashFlowTotals.self, forKey: .totals) ?? .zero
    }

    /// No income and no expenses in any bucket.
    public var isEmpty: Bool {
        periods.allSatisfy { $0.income == 0 && $0.expenses == 0 } && totals.income == 0 && totals.expenses == 0
    }

    /// Category amounts summed across every bucket, keyed by category id.
    public var categoryTotals: [CashFlowCategoryAmount] {
        var merged: [String: CashFlowCategoryAmount] = [:]
        var order: [String] = []
        for period in periods {
            for category in period.categories {
                if let existing = merged[category.categoryId] {
                    merged[category.categoryId] = CashFlowCategoryAmount(
                        categoryId: category.categoryId,
                        name: existing.name,
                        color: existing.color,
                        incomeAmount: existing.incomeAmount + category.incomeAmount,
                        expenseAmount: existing.expenseAmount + category.expenseAmount
                    )
                } else {
                    merged[category.categoryId] = category
                    order.append(category.categoryId)
                }
            }
        }
        return order.compactMap { merged[$0] }
    }
}

/// One category of `GET /stats/spendings-by-categories?groupByType=true`, in the base
/// currency. Both amounts are positive.
public struct CategorySpendingByType: Sendable, Hashable, Identifiable {
    /// The category id (the key of the response object).
    public let id: String
    public let name: String
    /// `#rrggbb`.
    public let color: String
    public let income: Decimal
    public let expense: Decimal

    public init(id: String, name: String, color: String, income: Decimal, expense: Decimal) {
        self.id = id
        self.name = name
        self.color = color
        self.income = income
        self.expense = expense
    }
}

/// Decodes the `{[categoryId]: {name, color, income, expense}}` object into an array sorted
/// by expense, then income, largest first, with ties broken by name.
struct CategorySpendingByTypeMap: Decodable {
    let items: [CategorySpendingByType]

    private struct Entry: Decodable {
        let name: String?
        let color: String?
        let income: Decimal?
        let expense: Decimal?
    }

    init(from decoder: any Decoder) throws {
        let entries = try decoder.singleValueContainer().decode([String: Entry].self)
        items = entries
            .map {
                CategorySpendingByType(
                    id: $0.key,
                    name: $0.value.name ?? "",
                    color: $0.value.color ?? "#8e8e93",
                    income: $0.value.income ?? 0,
                    expense: $0.value.expense ?? 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.expense != rhs.expense { return lhs.expense > rhs.expense }
                if lhs.income != rhs.income { return lhs.income > rhs.income }
                return lhs.name < rhs.name
            }
    }
}

/// `GET /stats/earliest-transaction-date`: `yyyy-MM-dd`, or `null` without transactions.
struct CashFlowEarliestDate: Decodable {
    let day: CalendarDate?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard !container.decodeNil(), let text = try? container.decode(String.self) else {
            day = nil
            return
        }
        day = CalendarDate(string: String(text.prefix(10)))
    }
}

extension Endpoints {
    /// `GET /stats/earliest-transaction-date`, for an "All time" period.
    public static func cashFlowEarliestTransactionDate() -> Endpoint<CalendarDate?> {
        Endpoint<CashFlowEarliestDate>(.get, "/stats/earliest-transaction-date").map(\.day)
    }

    /// `GET /stats/cash-flow`. `excludePlanned` is only sent when on (the server coerces
    /// booleans loosely).
    public static func cashFlow(
        from: CalendarDate,
        to: CalendarDate,
        granularity: CashFlowGranularity,
        accountId: String? = nil,
        filters: InsightsReportFilters = InsightsReportFilters(),
        excludePlanned: Bool = false
    ) -> Endpoint<CashFlowReport> {
        var query = QueryBuilder()
        query.add("from", day: from)
        query.add("to", day: to)
        query.add("granularity", granularity == .unknown ? CashFlowGranularity.monthly.rawValue : granularity.rawValue)
        query.add("accountId", accountId)
        filters.apply(to: &query)
        query.addFlag("excludePlanned", excludePlanned)
        return Endpoint(.get, "/stats/cash-flow", query: query.items)
    }

    /// `GET /stats/spendings-by-categories?groupByType=true`: income and expense per
    /// category in one call. Mirrors the web `getSpendingsByCategoriesByType`.
    public static func spendingsByCategoriesByType(
        from: CalendarDate? = nil,
        to: CalendarDate? = nil,
        accountId: String? = nil,
        categoryIds: [String] = [],
        excludedCategoryIds: [String] = [],
        excludePlanned: Bool = false
    ) -> Endpoint<[CategorySpendingByType]> {
        var query = QueryBuilder()
        query.add("groupByType", "true")
        query.add("accountId", accountId)
        query.add("from", day: from)
        query.add("to", day: to)
        query.add("categoryIds", list: categoryIds)
        query.add("excludedCategoryIds", list: excludedCategoryIds)
        query.addFlag("excludePlanned", excludePlanned)
        return Endpoint<CategorySpendingByTypeMap>(.get, "/stats/spendings-by-categories", query: query.items)
            .map(\.items)
    }
}
