import Foundation

/// Inputs of the investment calculator. Rates are percentages (`7` means 7%).
public struct InsightsProjectionParams: Sendable, Hashable {
    public var initialBalance: Double
    public var monthlyContribution: Double
    public var timeHorizonYears: Double
    public var annualReturnRate: Double
    public var annualInflationRate: Double

    public init(
        initialBalance: Double,
        monthlyContribution: Double,
        timeHorizonYears: Double,
        annualReturnRate: Double,
        annualInflationRate: Double
    ) {
        self.initialBalance = initialBalance
        self.monthlyContribution = monthlyContribution
        self.timeHorizonYears = timeHorizonYears
        self.annualReturnRate = annualReturnRate
        self.annualInflationRate = annualInflationRate
    }

    /// Rates at or below -100% make the monthly rate and the inflation deflator undefined.
    public static let rateRange: ClosedRange<Double> = -99.99...1_000
    public static let yearsRange: ClosedRange<Double> = 0...100
    public static let amountRange: ClosedRange<Double> = -1e15...1e15

    /// The inputs bounded so the projection stays finite: non-finite values become 0, rates stay
    /// above -100%, the horizon within 0–100 years.
    public var clamped: InsightsProjectionParams {
        func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : 0
        }
        return InsightsProjectionParams(
            initialBalance: clamp(initialBalance, Self.amountRange),
            monthlyContribution: clamp(monthlyContribution, Self.amountRange),
            timeHorizonYears: clamp(timeHorizonYears, Self.yearsRange),
            annualReturnRate: clamp(annualReturnRate, Self.rateRange),
            annualInflationRate: clamp(annualInflationRate, Self.rateRange)
        )
    }
}

/// One month of the projection.
public struct InsightsProjectionPoint: Sendable, Hashable, Identifiable {
    public let month: Int
    public let year: Double
    public let nominal: Double
    /// `nominal` in today's money.
    public let real: Double
    public let totalInvested: Double

    public var id: Int { month }
}

public struct InsightsProjectionSummary: Sendable, Hashable {
    public let initialBalance: Double
    public let totalContributions: Double
    public let monthlyContribution: Double
    public let totalInvested: Double
    public let nominalFinalValue: Double
    public let nominalGrowth: Double
    public let realFinalValue: Double
    public let realGrowth: Double
    /// Real final value per unit invested.
    public let realMultiplier: Double
}

/// The web's `use-projection-calc.ts`: monthly compounding at the monthly equivalent of the
/// annual rate, with the contribution added at each month's end, deflated by inflation.
public enum InsightsProjection {
    public static func points(_ params: InsightsProjectionParams) -> [InsightsProjectionPoint] {
        let params = params.clamped
        let totalMonths = Int((params.timeHorizonYears * 12).rounded())
        let monthlyRate = pow(1 + params.annualReturnRate / 100, 1.0 / 12) - 1
        var points = [InsightsProjectionPoint(
            month: 0, year: 0, nominal: params.initialBalance, real: params.initialBalance, totalInvested: params.initialBalance
        )]
        guard totalMonths > 0 else { return points }
        var nominal = params.initialBalance
        for month in 1...totalMonths {
            nominal = nominal * (1 + monthlyRate) + params.monthlyContribution
            let years = Double(month) / 12
            points.append(InsightsProjectionPoint(
                month: month,
                year: years,
                nominal: nominal,
                real: nominal / pow(1 + params.annualInflationRate / 100, years),
                totalInvested: params.initialBalance + params.monthlyContribution * Double(month)
            ))
        }
        return points
    }

    public static func summary(_ params: InsightsProjectionParams, points: [InsightsProjectionPoint]) -> InsightsProjectionSummary {
        let params = params.clamped
        guard points.count > 1, let last = points.last else {
            return InsightsProjectionSummary(
                initialBalance: params.initialBalance,
                totalContributions: 0,
                monthlyContribution: params.monthlyContribution,
                totalInvested: params.initialBalance,
                nominalFinalValue: params.initialBalance,
                nominalGrowth: 0,
                realFinalValue: params.initialBalance,
                realGrowth: 0,
                realMultiplier: params.initialBalance > 0 ? 1 : 0
            )
        }
        return InsightsProjectionSummary(
            initialBalance: params.initialBalance,
            totalContributions: last.totalInvested - params.initialBalance,
            monthlyContribution: params.monthlyContribution,
            totalInvested: last.totalInvested,
            nominalFinalValue: last.nominal,
            nominalGrowth: last.nominal - last.totalInvested,
            realFinalValue: last.real,
            realGrowth: last.real - last.totalInvested,
            realMultiplier: last.totalInvested > 0 ? last.real / last.totalInvested : 0
        )
    }
}

/// A preset annual return for the calculator (the web's `market-indicators.ts`).
public struct InsightsMarketIndicator: Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let averageAnnualReturn: Double

    public static let all: [InsightsMarketIndicator] = [
        InsightsMarketIndicator(id: "sp500", label: "S&P 500", averageAnnualReturn: 10),
        InsightsMarketIndicator(id: "nasdaq", label: "NASDAQ Composite", averageAnnualReturn: 12),
        InsightsMarketIndicator(id: "djia", label: "Dow Jones", averageAnnualReturn: 7.5),
        InsightsMarketIndicator(id: "world-stock", label: "Total World Stock", averageAnnualReturn: 8),
        InsightsMarketIndicator(id: "us-treasury", label: "US Treasury Bonds", averageAnnualReturn: 5),
        InsightsMarketIndicator(id: "corporate-bonds", label: "Corporate Bonds", averageAnnualReturn: 6),
    ]
}

/// How far back the calculator averages net income to seed the monthly contribution.
public enum InsightsNetIncomeWindow: String, Sendable, CaseIterable, Identifiable {
    case threeMonths = "3mo"
    case sixMonths = "6mo"
    case twelveMonths = "12mo"
    case all

    public var id: String { rawValue }

    public var months: Int? {
        switch self {
        case .threeMonths: 3
        case .sixMonths: 6
        case .twelveMonths: 12
        case .all: nil
        }
    }

    /// The months to request: back to the window's first month (or 2000 for all history)
    /// through the end of the current month.
    public func range(today: CalendarDate) -> (from: CalendarDate, to: CalendarDate) {
        let current = MonthPeriod(year: today.year, month: today.month)
        guard let months else { return (CalendarDate(year: 2000, month: 1, day: 1), current.lastDay()) }
        var first = current
        for _ in 1..<months { first = first.previous }
        return (first.firstDay, current.lastDay())
    }

    /// Average monthly net flow over the report's buckets, rounded to cents, never negative.
    public static func averageNetIncome(_ report: CashFlowReport) -> Double {
        guard !report.periods.isEmpty else { return 0 }
        let average = NSDecimalNumber(decimal: report.totals.netFlow).doubleValue / Double(report.periods.count)
        return max(0, (average * 100).rounded() / 100)
    }
}
