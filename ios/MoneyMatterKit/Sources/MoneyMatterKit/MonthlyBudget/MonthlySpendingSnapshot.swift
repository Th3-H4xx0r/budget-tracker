import Foundation

/// A calendar month, e.g. October 2026.
public struct BudgetMonth: Sendable, Hashable, Codable, Comparable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// The month containing `date` in `calendar`.
    public init(containing date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1)
    }

    /// `2026-10`, used in storage keys.
    public var key: String {
        String(format: "%04d-%02d", year, month)
    }

    /// Local midnight on the 1st.
    public func startDate(calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
    }

    public func dayCount(calendar: Calendar = .autoupdatingCurrent) -> Int {
        calendar.range(of: .day, in: .month, for: startDate(calendar: calendar))?.count ?? 30
    }

    public static func < (lhs: BudgetMonth, rhs: BudgetMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// How far spending has got through the budget.
public enum BudgetThreshold: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case none
    /// At least 80 % of the budget spent.
    case warning
    /// More than 100 % of the budget spent.
    case over

    public static let warningFraction: Decimal = 0.8

    /// `.none` without a positive budget.
    public static func of(spent: Decimal, budget: Decimal?) -> BudgetThreshold {
        guard let budget, budget > 0 else { return .none }
        if spent > budget { return .over }
        if spent >= budget * warningFraction { return .warning }
        return .none
    }

    private var rank: Int {
        switch self {
        case .none: 0
        case .warning: 1
        case .over: 2
        }
    }

    public static func < (lhs: BudgetThreshold, rhs: BudgetThreshold) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// This month's spending against the monthly budget, as shown by the widget. Shared between
/// the app and the widget through the App Group.
public struct MonthlySpendingSnapshot: Sendable, Hashable, Codable {
    public let month: BudgetMonth
    /// Expenses so far this month in the base currency, positive.
    public let spent: Decimal
    /// `nil` when no budget is set.
    public let budget: Decimal?
    /// Running total at the end of each day so far: index 0 is the 1st.
    public let dailyCumulative: [Decimal]
    public let currencyCode: String
    public let updatedAt: Date

    public init(
        month: BudgetMonth,
        spent: Decimal,
        budget: Decimal?,
        dailyCumulative: [Decimal],
        currencyCode: String,
        updatedAt: Date
    ) {
        self.month = month
        self.spent = spent
        self.budget = budget
        self.dailyCumulative = dailyCumulative
        self.currencyCode = currencyCode
        self.updatedAt = updatedAt
    }

    public var hasBudget: Bool {
        guard let budget else { return false }
        return budget > 0
    }

    /// What's left before reaching the budget, never negative; `nil` without a budget.
    public var remaining: Decimal? {
        guard let budget, hasBudget else { return nil }
        return max(budget - spent, 0)
    }

    /// How much spending exceeds the budget, never negative; `nil` without a budget.
    public var overBy: Decimal? {
        guard let budget, hasBudget else { return nil }
        return max(spent - budget, 0)
    }

    /// Spent over budget, unclamped (1.25 means 25 % over); `nil` without a budget.
    public var fraction: Double? {
        guard let budget, hasBudget else { return nil }
        return NSDecimalNumber(decimal: spent / budget).doubleValue
    }

    public var threshold: BudgetThreshold {
        BudgetThreshold.of(spent: spent, budget: budget)
    }

    public var isOverBudget: Bool { threshold == .over }

    /// Sums each transaction's `refAmount` into its local day of `month` and returns the
    /// running total for days 1 through `throughDay`. Rows outside that range are ignored.
    public static func dailyCumulative(
        of transactions: [Transaction],
        month: BudgetMonth,
        throughDay: Int,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Decimal] {
        let days = max(throughDay, 0)
        guard days > 0 else { return [] }
        var perDay = [Decimal](repeating: 0, count: days)
        for transaction in transactions {
            guard BudgetMonth(containing: transaction.time, calendar: calendar) == month else { continue }
            let day = calendar.component(.day, from: transaction.time)
            guard (1...days).contains(day) else { continue }
            perDay[day - 1] += transaction.refAmount
        }
        var running: Decimal = 0
        return perDay.map { amount in
            running += amount
            return running
        }
    }
}

/// How long ago a snapshot was refreshed, bucketed for a short label such as
/// "Over half a day ago".
public enum BudgetFreshness: Sendable, Hashable {
    case justNow
    case minutes(Int)
    case hours(Int)
    case overHalfADay
    case overADay
    case days(Int)

    public init(since updatedAt: Date, now: Date) {
        let seconds = max(now.timeIntervalSince(updatedAt), 0)
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        switch hours {
        case _ where minutes < 1: self = .justNow
        case 0: self = .minutes(minutes)
        case 1..<12: self = .hours(hours)
        case 12..<24: self = .overHalfADay
        case 24..<48: self = .overADay
        default: self = .days(hours / 24)
        }
    }
}
