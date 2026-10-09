// Investment and venture contributions endpoints and models.
import Foundation

/// Bucket size for the investment reports (`/stats/investment-contributions` and
/// `/stats/net-worth-drivers`).
public enum InvestmentReportGranularity: String, Sendable, Hashable, CaseIterable, Identifiable {
    case monthly
    case quarterly
    case yearly

    public var id: String { rawValue }
}

/// One portfolio's net external cash in one bucket. Signed: negative when withdrawals won.
public struct InvestmentContributionSlice: Sendable, Hashable, Decodable {
    public let portfolioId: String
    public let amount: Decimal

    public init(portfolioId: String, amount: Decimal) {
        self.portfolioId = portfolioId
        self.amount = amount
    }
}

/// One bucket of `GET /stats/investment-contributions`, in the base currency.
public struct InvestmentContributionBucket: Sendable, Hashable, Identifiable, Decodable {
    /// Clamped to the requested range, so the first and last bucket can be partial.
    public let periodStart: CalendarDate
    public let periodEnd: CalendarDate
    /// Net contributions across the in-scope portfolios. Signed.
    public let total: Decimal
    /// Only portfolios with a non-zero net this bucket.
    public let byPortfolio: [InvestmentContributionSlice]
    /// User-wide income minus expenses (not scoped by portfolio).
    public let savingsNet: Decimal

    public var id: CalendarDate { periodStart }

    public init(
        periodStart: CalendarDate,
        periodEnd: CalendarDate,
        total: Decimal,
        byPortfolio: [InvestmentContributionSlice] = [],
        savingsNet: Decimal = 0
    ) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.total = total
        self.byPortfolio = byPortfolio
        self.savingsNet = savingsNet
    }

    private enum CodingKeys: String, CodingKey {
        case periodStart, periodEnd, total, byPortfolio, savingsNet
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        periodStart = try container.decode(CalendarDate.self, forKey: .periodStart)
        periodEnd = try container.decode(CalendarDate.self, forKey: .periodEnd)
        total = try container.decodeIfPresent(Decimal.self, forKey: .total) ?? 0
        byPortfolio = try container.decodeLossyArrayIfPresent([InvestmentContributionSlice].self, forKey: .byPortfolio) ?? []
        savingsNet = try container.decodeIfPresent(Decimal.self, forKey: .savingsNet) ?? 0
    }

    /// This bucket's amount for one portfolio, zero when it had no activity.
    public func amount(forPortfolio portfolioId: String) -> Decimal {
        byPortfolio.first { $0.portfolioId == portfolioId }?.amount ?? 0
    }
}

/// A legend entry shared by the investment reports.
public struct InsightsPortfolioMeta: Sendable, Hashable, Identifiable, Decodable {
    public let portfolioId: String
    public let name: String

    public var id: String { portfolioId }

    public init(portfolioId: String, name: String) {
        self.portfolioId = portfolioId
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case portfolioId, name
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        portfolioId = try container.decode(String.self, forKey: .portfolioId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

/// `GET /stats/investment-contributions`.
public struct InvestmentContributionsReport: Sendable, Hashable, Decodable {
    public let buckets: [InvestmentContributionBucket]
    /// Portfolios that contributed anywhere in the window, largest mover first.
    public let portfolios: [InsightsPortfolioMeta]

    public init(buckets: [InvestmentContributionBucket], portfolios: [InsightsPortfolioMeta]) {
        self.buckets = buckets
        self.portfolios = portfolios
    }

    private enum CodingKeys: String, CodingKey {
        case buckets, portfolios
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        buckets = try container.decodeIfPresent([InvestmentContributionBucket].self, forKey: .buckets) ?? []
        portfolios = try container.decodeLossyArrayIfPresent([InsightsPortfolioMeta].self, forKey: .portfolios) ?? []
    }

    /// Net contributions over the whole window.
    public var totalContributed: Decimal {
        buckets.reduce(Decimal.zero) { $0 + $1.total }
    }

    /// Income minus expenses over the whole window.
    public var totalSavings: Decimal {
        buckets.reduce(Decimal.zero) { $0 + $1.savingsNet }
    }

    /// Contributions as a whole percentage of savings, or `nil` when nothing was saved.
    public var shareOfSavingsPercent: Int? {
        guard totalSavings > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: totalContributed / totalSavings).doubleValue
        return Int((ratio * 100).rounded())
    }

    /// The window's total spread across its buckets; zero without buckets.
    public var averagePerBucket: Decimal {
        guard !buckets.isEmpty else { return 0 }
        return totalContributed / Decimal(buckets.count)
    }

    /// The average line for the chart: `nil` below three buckets, where it adds nothing.
    public var chartAverage: Decimal? {
        buckets.count < 3 ? nil : averagePerBucket
    }

    /// Whether any portfolio moved money in the window. A valid range always has
    /// buckets, so the legend is what tells activity apart from an empty window.
    public var hasActivity: Bool { !portfolios.isEmpty }
}

/// One row of `GET /stats/venture-contributions`: cash put into a deal, largest first.
public struct InsightsVentureContribution: Sendable, Hashable, Identifiable, Decodable {
    public let dealId: String
    public let name: String
    public let amount: Decimal

    public var id: String { dealId }

    public init(dealId: String, name: String, amount: Decimal) {
        self.dealId = dealId
        self.name = name
        self.amount = amount
    }

    private enum CodingKeys: String, CodingKey {
        case dealId, name, amount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dealId = try container.decode(String.self, forKey: .dealId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        amount = try container.decodeIfPresent(Decimal.self, forKey: .amount) ?? 0
    }
}

extension Endpoints {
    /// `GET /stats/investment-contributions`. An empty `portfolioIds` means every enabled portfolio.
    public static func investmentContributions(
        from: CalendarDate,
        to: CalendarDate,
        granularity: InvestmentReportGranularity,
        portfolioIds: [String] = []
    ) -> Endpoint<InvestmentContributionsReport> {
        var query = QueryBuilder()
        query.add("from", day: from)
        query.add("to", day: to)
        query.add("granularity", granularity.rawValue)
        query.add("portfolioIds", list: portfolioIds)
        return Endpoint(.get, "/stats/investment-contributions", query: query.items)
    }

    /// `GET /stats/venture-contributions`: one row per deal, largest first.
    public static func ventureContributions(from: CalendarDate, to: CalendarDate) -> Endpoint<[InsightsVentureContribution]> {
        var query = QueryBuilder()
        query.add("from", day: from)
        query.add("to", day: to)
        return Endpoint(.get, "/stats/venture-contributions", query: query.items)
    }
}
