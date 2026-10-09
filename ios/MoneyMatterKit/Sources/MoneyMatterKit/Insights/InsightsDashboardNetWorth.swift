import Foundation

/// Which derived components the net worth widget counts (`includeVentures`, `includeVehicles`,
/// `includeLoans` in its widget config). Missing or non-boolean values count as included.
public struct DashboardNetWorthIncludes: Sendable, Hashable {
    public var ventures: Bool
    public var vehicles: Bool
    public var loans: Bool

    public static let all = DashboardNetWorthIncludes(ventures: true, vehicles: true, loans: true)

    public init(ventures: Bool, vehicles: Bool, loans: Bool) {
        self.ventures = ventures
        self.vehicles = vehicles
        self.loans = loans
    }

    public init(config: [String: DashboardConfigValue]?) {
        func read(_ key: String) -> Bool {
            if case .bool(let value) = config?[key] { return value }
            return true
        }
        self.init(ventures: read("includeVentures"), vehicles: read("includeVehicles"), loans: read("includeLoans"))
    }

    public var configValues: [String: DashboardConfigValue] {
        ["includeVentures": .bool(ventures), "includeVehicles": .bool(vehicles), "includeLoans": .bool(loans)]
    }

    /// The point's net worth. With nothing excluded the server total is authoritative; loans are
    /// negative, so including them subtracts the debt.
    public func compose(_ point: BalancePoint) -> Decimal {
        if ventures && vehicles && loans { return point.totalBalance }
        var total = point.accountsBalance + point.portfoliosBalance
        if ventures { total += point.venturesBalance }
        if vehicles { total += point.vehiclesBalance }
        if loans { total += point.loansBalance }
        return total
    }
}

/// One month bar of the net worth widget's trend.
public struct DashboardNetWorthBar: Sendable, Hashable, Identifiable {
    public let period: MonthPeriod
    /// `nil` when the series has no point at or before the month's end.
    public let delta: Decimal?
    public let endNetWorth: Decimal?
    public let isCurrent: Bool

    public var id: MonthPeriod { period }
}

/// The net worth widget's numbers for one month (the web's `net-worth-widget/helpers.ts`).
public struct DashboardNetWorthSummary: Sendable, Hashable {
    /// How many months before the selected one the trend shows.
    public static let previousMonthCount = 5

    public let endNetWorth: Decimal?
    public let startNetWorth: Decimal?
    /// The change over the previous month; `nil` when the series has nothing before this month.
    public let previousDelta: Decimal?
    /// Oldest first; the selected month is last.
    public let bars: [DashboardNetWorthBar]
    /// The last point at or before the month's end, for the composition breakdown.
    public let endPoint: BalancePoint?

    public var currentDelta: Decimal? {
        guard let endNetWorth, let startNetWorth else { return nil }
        return endNetWorth - startNetWorth
    }

    /// `nil` when either side is unknown or the starting net worth is zero.
    public var growthPercent: Double? {
        guard let currentDelta, let startNetWorth, startNetWorth != 0 else { return nil }
        let ratio = currentDelta / abs(startNetWorth) * 100
        return NSDecimalNumber(decimal: ratio).doubleValue
    }

    /// The days to request: from the day before the earliest trend month through the month's end.
    public static func fetchRange(for period: MonthPeriod) -> (from: CalendarDate, to: CalendarDate) {
        var earliest = period
        for _ in 0..<previousMonthCount { earliest = earliest.previous }
        return (earliest.firstDay.adding(days: -1), period.lastDay())
    }

    public init(series: [BalancePoint], period: MonthPeriod, includes: DashboardNetWorthIncludes) {
        let sorted = series.sorted { $0.date < $1.date }

        func lastBefore(_ day: CalendarDate) -> BalancePoint? { sorted.last { $0.date < day } }
        func lastAtOrBefore(_ day: CalendarDate) -> BalancePoint? { sorted.last { $0.date <= day } }
        func firstIn(_ month: MonthPeriod) -> BalancePoint? {
            sorted.first { $0.date >= month.firstDay && $0.date <= month.lastDay() }
        }
        func start(_ month: MonthPeriod) -> Decimal? {
            (lastBefore(month.firstDay) ?? firstIn(month)).map(includes.compose)
        }
        func end(_ month: MonthPeriod) -> Decimal? {
            lastAtOrBefore(month.lastDay()).map(includes.compose)
        }

        startNetWorth = start(period)
        endNetWorth = end(period)
        endPoint = lastAtOrBefore(period.lastDay())

        if lastBefore(period.firstDay) != nil, let prevStart = start(period.previous), let prevEnd = end(period.previous) {
            previousDelta = prevEnd - prevStart
        } else {
            previousDelta = nil
        }

        var months: [MonthPeriod] = [period]
        for _ in 0..<Self.previousMonthCount { months.insert(months[0].previous, at: 0) }
        bars = months.map { month in
            guard let endPoint = lastAtOrBefore(month.lastDay()) else {
                return DashboardNetWorthBar(period: month, delta: nil, endNetWorth: nil, isCurrent: month == period)
            }
            let baseline = lastBefore(month.firstDay) ?? firstIn(month) ?? endPoint
            let endValue = includes.compose(endPoint)
            return DashboardNetWorthBar(
                period: month,
                delta: endValue - includes.compose(baseline),
                endNetWorth: endValue,
                isCurrent: month == period
            )
        }
    }
}
