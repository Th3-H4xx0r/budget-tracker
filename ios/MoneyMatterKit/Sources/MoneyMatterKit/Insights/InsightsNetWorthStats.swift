// Net worth history and net worth drivers: endpoints, models, and the derivations the
// reports show (filtered series, period change, cumulative drivers, growth crossover).
import Foundation

// MARK: - Net worth history

/// Bucket size for `/stats/net-worth-history`.
public enum NetWorthHistoryGranularity: String, Sendable, Hashable, CaseIterable, Identifiable {
    case weekly
    case monthly
    case quarterly
    case yearly

    public var id: String { rawValue }

    /// Ranges producing more buckets than this are rejected by the API with 422.
    public static let maxBuckets = 500

    /// Calendar buckets the range spans, mirroring how the API buckets.
    public func bucketCount(from: CalendarDate, to: CalendarDate) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let start = from.startDate(in: calendar)
        let end = to.startDate(in: calendar)
        switch self {
        case .weekly:
            let startWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
            let endWeek = calendar.dateInterval(of: .weekOfYear, for: end)?.start ?? end
            return (calendar.dateComponents([.day], from: startWeek, to: endWeek).day ?? 0) / 7 + 1
        case .monthly:
            return (to.year - from.year) * 12 + (to.month - from.month) + 1
        case .quarterly:
            let fromQuarter = from.year * 4 + (from.month - 1) / 3
            let toQuarter = to.year * 4 + (to.month - 1) / 3
            return toQuarter - fromQuarter + 1
        case .yearly:
            return to.year - from.year + 1
        }
    }

    /// Fine enough to show shape, coarse enough to stay under the bucket cap.
    public static func automatic(from: CalendarDate, to: CalendarDate) -> NetWorthHistoryGranularity {
        let days = NetWorthDateMath.daysBetween(from, to) + 1
        if days <= 370 { return .weekly }
        if days <= 1850 { return .monthly }
        return .quarterly
    }

    /// Granularities the range would push past the API's bucket cap.
    public static func disabled(from: CalendarDate, to: CalendarDate) -> Set<NetWorthHistoryGranularity> {
        Set(allCases.filter { $0.bucketCount(from: from, to: to) > maxBuckets })
    }
}

/// Asset classes the history report splits assets into.
public enum NetWorthAssetKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case cash
    case investments
    case vehicles
    case ventures

    public var id: String { rawValue }
}

/// Account categories the history report treats as debt.
public enum NetWorthLiabilityKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case creditCard = "credit-card"
    case loan
    case overdraft

    public var id: String { rawValue }
}

/// One end-of-bucket snapshot of `GET /stats/net-worth-history`, in the base currency.
public struct NetWorthHistoryPoint: Sendable, Hashable, Identifiable, Decodable {
    public let date: CalendarDate
    /// Signed balance per asset kind. Missing kinds read as zero.
    public let assets: [NetWorthAssetKind: Decimal]
    public let assetsTotal: Decimal
    /// Signed balance per liability kind; negative = owed.
    public let liabilities: [NetWorthLiabilityKind: Decimal]
    public let liabilitiesTotal: Decimal
    public let netWorth: Decimal

    public var id: CalendarDate { date }

    public init(
        date: CalendarDate,
        assets: [NetWorthAssetKind: Decimal],
        liabilities: [NetWorthLiabilityKind: Decimal]
    ) {
        self.date = date
        self.assets = assets
        self.liabilities = liabilities
        assetsTotal = assets.values.reduce(0, +)
        liabilitiesTotal = liabilities.values.reduce(0, +)
        netWorth = assetsTotal + liabilitiesTotal
    }

    private enum CodingKeys: String, CodingKey {
        case date, assets, assetsTotal, liabilities, liabilitiesTotal, netWorth
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(CalendarDate.self, forKey: .date)
        let rawAssets = try container.decodeIfPresent([String: Decimal].self, forKey: .assets) ?? [:]
        let rawLiabilities = try container.decodeIfPresent([String: Decimal].self, forKey: .liabilities) ?? [:]
        var assets: [NetWorthAssetKind: Decimal] = [:]
        for (key, value) in rawAssets {
            if let kind = NetWorthAssetKind(rawValue: key) { assets[kind] = value }
        }
        var liabilities: [NetWorthLiabilityKind: Decimal] = [:]
        for (key, value) in rawLiabilities {
            if let kind = NetWorthLiabilityKind(rawValue: key) { liabilities[kind] = value }
        }
        self.assets = assets
        self.liabilities = liabilities
        assetsTotal = try container.decodeIfPresent(Decimal.self, forKey: .assetsTotal) ?? rawAssets.values.reduce(0, +)
        liabilitiesTotal = try container.decodeIfPresent(Decimal.self, forKey: .liabilitiesTotal)
            ?? rawLiabilities.values.reduce(0, +)
        netWorth = try container.decodeIfPresent(Decimal.self, forKey: .netWorth) ?? assetsTotal + liabilitiesTotal
    }

    public func value(for kind: NetWorthAssetKind) -> Decimal { assets[kind] ?? 0 }
    public func value(for kind: NetWorthLiabilityKind) -> Decimal { liabilities[kind] ?? 0 }
}

/// A security the report had to carry at cost because it had no price.
public struct NetWorthUnpricedSecurity: Sendable, Hashable, Identifiable, Decodable {
    public let securityId: String
    public let symbol: String?
    public let name: String?

    public var id: String { securityId }

    /// `symbol ?? name ?? securityId`.
    public var label: String { symbol ?? name ?? securityId }

    public init(securityId: String, symbol: String? = nil, name: String? = nil) {
        self.securityId = securityId
        self.symbol = symbol
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case securityId, symbol, name
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? container.decode(String.self, forKey: .securityId) {
            securityId = string
        } else {
            securityId = String(try container.decode(Int.self, forKey: .securityId))
        }
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

/// What a net worth report could not value truthfully. Absent when everything valued cleanly.
public struct NetWorthDegraded: Sendable, Hashable, Decodable {
    public let unpricedSecurities: [NetWorthUnpricedSecurity]
    /// ISO codes converted at a 1:1 placeholder rate.
    public let fxFallbackCurrencies: [String]

    public init(unpricedSecurities: [NetWorthUnpricedSecurity] = [], fxFallbackCurrencies: [String] = []) {
        self.unpricedSecurities = unpricedSecurities
        self.fxFallbackCurrencies = fxFallbackCurrencies
    }

    private enum CodingKeys: String, CodingKey {
        case unpricedSecurities, fxFallbackCurrencies
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unpricedSecurities = try container.decodeLossyArrayIfPresent([NetWorthUnpricedSecurity].self, forKey: .unpricedSecurities) ?? []
        fxFallbackCurrencies = try container.decodeIfPresent([String].self, forKey: .fxFallbackCurrencies) ?? []
    }

    public var isEmpty: Bool { unpricedSecurities.isEmpty && fxFallbackCurrencies.isEmpty }
}

/// `GET /stats/net-worth-history`.
public struct NetWorthHistoryReport: Sendable, Hashable, Decodable {
    public let points: [NetWorthHistoryPoint]
    public let degraded: NetWorthDegraded?

    public init(points: [NetWorthHistoryPoint], degraded: NetWorthDegraded? = nil) {
        self.points = points
        self.degraded = degraded
    }

    private enum CodingKeys: String, CodingKey {
        case points, degraded
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try container.decodeLossyArrayIfPresent([NetWorthHistoryPoint].self, forKey: .points) ?? []
        let degraded = try container.decodeIfPresent(NetWorthDegraded.self, forKey: .degraded)
        self.degraded = degraded?.isEmpty == true ? nil : degraded
    }

    /// The API returns all-zero buckets for a user without balances, so only non-zero
    /// values count as data.
    public var hasData: Bool {
        points.contains { $0.assetsTotal != 0 || $0.liabilitiesTotal != 0 }
    }

    /// Asset kinds with a non-zero balance anywhere, in canonical order.
    public var assetKindsWithActivity: [NetWorthAssetKind] {
        NetWorthAssetKind.allCases.filter { kind in points.contains { $0.value(for: kind) != 0 } }
    }

    /// Liability kinds with a non-zero balance anywhere, in canonical order.
    public var liabilityKindsWithActivity: [NetWorthLiabilityKind] {
        NetWorthLiabilityKind.allCases.filter { kind in points.contains { $0.value(for: kind) != 0 } }
    }

    /// The points restricted to the selected kinds. Pass every kind for the server totals.
    public func displayPoints(
        assetKinds: [NetWorthAssetKind],
        liabilityKinds: [NetWorthLiabilityKind]
    ) -> [NetWorthDisplayPoint] {
        points.map { point in
            var assets: [NetWorthAssetKind: Decimal] = [:]
            for kind in assetKinds { assets[kind] = point.value(for: kind) }
            var liabilities: [NetWorthLiabilityKind: Decimal] = [:]
            for kind in liabilityKinds { liabilities[kind] = point.value(for: kind) }
            return NetWorthDisplayPoint(date: point.date, assetsByKind: assets, liabilitiesByKind: liabilities)
        }
    }
}

/// A history point restricted to the kinds the user selected.
public struct NetWorthDisplayPoint: Sendable, Hashable, Identifiable {
    public let date: CalendarDate
    public let assetsByKind: [NetWorthAssetKind: Decimal]
    public let assetsTotal: Decimal
    public let liabilitiesByKind: [NetWorthLiabilityKind: Decimal]
    /// Negative = owed.
    public let liabilitiesTotal: Decimal
    public let netWorth: Decimal

    public var id: CalendarDate { date }

    public init(
        date: CalendarDate,
        assetsByKind: [NetWorthAssetKind: Decimal],
        liabilitiesByKind: [NetWorthLiabilityKind: Decimal]
    ) {
        self.date = date
        self.assetsByKind = assetsByKind
        self.liabilitiesByKind = liabilitiesByKind
        assetsTotal = assetsByKind.values.reduce(0, +)
        liabilitiesTotal = liabilitiesByKind.values.reduce(0, +)
        netWorth = assetsTotal + liabilitiesTotal
    }
}

/// Summary figures for the displayed history series.
public enum NetWorthHistoryMath {
    /// An empty selection means every available kind. Stored kinds without activity are
    /// dropped; when none remain, every available kind is used.
    public static func resolveSelection<Kind: Hashable>(stored: [Kind], available: [Kind]) -> [Kind] {
        if stored.isEmpty { return available }
        let valid = available.filter { stored.contains($0) }
        return valid.isEmpty ? available : valid
    }

    /// Mean displayed liabilities as a positive owed amount; zero when not owing on average.
    public static func averageOwed(_ points: [NetWorthDisplayPoint]) -> Decimal {
        guard !points.isEmpty else { return 0 }
        let mean = points.reduce(Decimal.zero) { $0 + $1.liabilitiesTotal } / Decimal(points.count)
        return mean < 0 ? -mean : 0
    }

    /// Last minus first net worth. The percentage is nil when the first point is zero.
    public static func periodChange(_ points: [NetWorthDisplayPoint]) -> (amount: Decimal, percent: Double?) {
        guard let first = points.first, let last = points.last else { return (0, nil) }
        let amount = last.netWorth - first.netWorth
        guard first.netWorth != 0 else { return (amount, nil) }
        let percent = NetWorthDateMath.double(amount) / abs(NetWorthDateMath.double(first.netWorth)) * 100
        return (amount, percent)
    }

    /// Compound annual growth rate as a percentage. Nil for spans under a year or when
    /// either end is at or below zero.
    public static func annualizedGrowthPercent(_ points: [NetWorthDisplayPoint]) -> Double? {
        guard let first = points.first, let last = points.last, points.count > 1 else { return nil }
        guard first.netWorth > 0, last.netWorth > 0 else { return nil }
        let years = Double(NetWorthDateMath.daysBetween(first.date, last.date)) / 365.25
        guard years >= 1 else { return nil }
        let ratio = NetWorthDateMath.double(last.netWorth) / NetWorthDateMath.double(first.netWorth)
        return (pow(ratio, 1 / years) - 1) * 100
    }
}

// MARK: - Net worth drivers

/// One portfolio's share of a bucket's growth. Signed.
public struct NetWorthDriversSlice: Sendable, Hashable, Decodable {
    public let portfolioId: String
    public let growth: Decimal

    public init(portfolioId: String, growth: Decimal) {
        self.portfolioId = portfolioId
        self.growth = growth
    }
}

/// One bucket of `GET /stats/net-worth-drivers`, in the base currency.
public struct NetWorthDriversBucket: Sendable, Hashable, Identifiable, Decodable {
    public struct Savings: Sendable, Hashable, Decodable {
        public let income: Decimal
        /// Positive: the amount spent.
        public let expenses: Decimal
        public let net: Decimal

        public init(income: Decimal = 0, expenses: Decimal = 0, net: Decimal) {
            self.income = income
            self.expenses = expenses
            self.net = net
        }

        private enum CodingKeys: String, CodingKey { case income, expenses, net }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            income = try container.decodeIfPresent(Decimal.self, forKey: .income) ?? 0
            expenses = try container.decodeIfPresent(Decimal.self, forKey: .expenses) ?? 0
            net = try container.decodeIfPresent(Decimal.self, forKey: .net) ?? income - expenses
        }
    }

    public struct Investments: Sendable, Hashable, Decodable {
        /// priceEffect + dividends - feesAndTaxes. Signed.
        public let growth: Decimal
        public let priceEffect: Decimal
        public let dividends: Decimal
        /// Positive: a cost.
        public let feesAndTaxes: Decimal
        /// Only portfolios with non-zero growth this bucket.
        public let byPortfolio: [NetWorthDriversSlice]

        public init(
            growth: Decimal,
            priceEffect: Decimal = 0,
            dividends: Decimal = 0,
            feesAndTaxes: Decimal = 0,
            byPortfolio: [NetWorthDriversSlice] = []
        ) {
            self.growth = growth
            self.priceEffect = priceEffect
            self.dividends = dividends
            self.feesAndTaxes = feesAndTaxes
            self.byPortfolio = byPortfolio
        }

        private enum CodingKeys: String, CodingKey { case growth, priceEffect, dividends, feesAndTaxes, byPortfolio }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            growth = try container.decodeIfPresent(Decimal.self, forKey: .growth) ?? 0
            priceEffect = try container.decodeIfPresent(Decimal.self, forKey: .priceEffect) ?? 0
            dividends = try container.decodeIfPresent(Decimal.self, forKey: .dividends) ?? 0
            feesAndTaxes = try container.decodeIfPresent(Decimal.self, forKey: .feesAndTaxes) ?? 0
            byPortfolio = try container.decodeLossyArrayIfPresent([NetWorthDriversSlice].self, forKey: .byPortfolio) ?? []
        }
    }

    public struct Composition: Sendable, Hashable, Decodable {
        public let holdingsValue: Decimal
        /// Cash accounts (card negatives included) plus uninvested portfolio cash.
        public let cashValue: Decimal

        public init(holdingsValue: Decimal, cashValue: Decimal) {
            self.holdingsValue = holdingsValue
            self.cashValue = cashValue
        }

        private enum CodingKeys: String, CodingKey { case holdingsValue, cashValue }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            holdingsValue = try container.decodeIfPresent(Decimal.self, forKey: .holdingsValue) ?? 0
            cashValue = try container.decodeIfPresent(Decimal.self, forKey: .cashValue) ?? 0
        }

        /// Holdings as a percentage of holdings plus cash; nil when that total isn't positive.
        public var holdingsSharePercent: Double? {
            let total = holdingsValue + cashValue
            guard total > 0 else { return nil }
            return NetWorthDateMath.double(holdingsValue) / NetWorthDateMath.double(total) * 100
        }
    }

    public let periodStart: CalendarDate
    public let periodEnd: CalendarDate
    public let savings: Savings
    public let investments: Investments
    public let composition: Composition

    public var id: CalendarDate { periodStart }

    public init(
        periodStart: CalendarDate,
        periodEnd: CalendarDate,
        savings: Savings,
        investments: Investments,
        composition: Composition
    ) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.savings = savings
        self.investments = investments
        self.composition = composition
    }

    private enum CodingKeys: String, CodingKey { case periodStart, periodEnd, savings, investments, composition }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        periodStart = try container.decode(CalendarDate.self, forKey: .periodStart)
        periodEnd = try container.decode(CalendarDate.self, forKey: .periodEnd)
        savings = try container.decodeIfPresent(Savings.self, forKey: .savings) ?? Savings(net: 0)
        investments = try container.decodeIfPresent(Investments.self, forKey: .investments) ?? Investments(growth: 0)
        composition = try container.decodeIfPresent(Composition.self, forKey: .composition)
            ?? Composition(holdingsValue: 0, cashValue: 0)
    }
}

/// Running totals of saved and grown since the window opened.
public struct NetWorthDriversCumulativePoint: Sendable, Hashable, Identifiable {
    public let periodStart: CalendarDate
    public let periodEnd: CalendarDate
    public let savedCumulative: Decimal
    public let grownCumulative: Decimal
    public let savingsNet: Decimal
    public let growth: Decimal

    public var id: CalendarDate { periodStart }
}

/// The holdings share at the end of the window, and the same share about a year back.
public struct NetWorthAllocationContext: Sendable, Hashable {
    public let currentSharePercent: Double?
    public let referenceSharePercent: Double?
    public let referencePeriodEnd: CalendarDate?
}

/// `GET /stats/net-worth-drivers`.
public struct NetWorthDriversReport: Sendable, Hashable, Decodable {
    public let buckets: [NetWorthDriversBucket]
    /// Portfolios with investment activity, ordered by absolute total growth.
    public let portfolios: [InsightsPortfolioMeta]
    public let degraded: NetWorthDegraded?

    public init(buckets: [NetWorthDriversBucket], portfolios: [InsightsPortfolioMeta] = [], degraded: NetWorthDegraded? = nil) {
        self.buckets = buckets
        self.portfolios = portfolios
        self.degraded = degraded
    }

    private enum CodingKeys: String, CodingKey { case buckets, portfolios, degraded }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        buckets = try container.decodeLossyArrayIfPresent([NetWorthDriversBucket].self, forKey: .buckets) ?? []
        portfolios = try container.decodeLossyArrayIfPresent([InsightsPortfolioMeta].self, forKey: .portfolios) ?? []
        let degraded = try container.decodeIfPresent(NetWorthDegraded.self, forKey: .degraded)
        self.degraded = degraded?.isEmpty == true ? nil : degraded
    }

    /// All-zero windows read as no data.
    public var hasData: Bool {
        buckets.contains {
            $0.savings.net != 0 || $0.investments.growth != 0
                || $0.composition.holdingsValue != 0 || $0.composition.cashValue != 0
        }
    }

    /// Whether any bucket shows investment activity (holdings, growth, or fees).
    public var hasPortfolioActivity: Bool {
        buckets.contains {
            $0.composition.holdingsValue != 0 || $0.investments.growth != 0 || $0.investments.priceEffect != 0
                || $0.investments.dividends != 0 || $0.investments.feesAndTaxes != 0
        }
    }

    public var cumulativeSeries: [NetWorthDriversCumulativePoint] {
        var saved = Decimal.zero
        var grown = Decimal.zero
        return buckets.map { bucket in
            saved += bucket.savings.net
            grown += bucket.investments.growth
            return NetWorthDriversCumulativePoint(
                periodStart: bucket.periodStart,
                periodEnd: bucket.periodEnd,
                savedCumulative: saved,
                grownCumulative: grown,
                savingsNet: bucket.savings.net,
                growth: bucket.investments.growth
            )
        }
    }

    /// The latest holdings value, and saving averaged over the calendar months spanned.
    public var targetSeeds: (currentPortfolioValue: Decimal, averageMonthlySavings: Decimal) {
        let current = buckets.last?.composition.holdingsValue ?? 0
        guard let first = buckets.first, let last = buckets.last else { return (current, 0) }
        let saved = buckets.reduce(Decimal.zero) { $0 + $1.savings.net }
        let months = max((last.periodEnd.year - first.periodStart.year) * 12 + last.periodEnd.month - first.periodStart.month + 1, 1)
        return (current, saved / Decimal(months))
    }

    /// The current holdings share plus the share nearest `yearsBack` earlier.
    public func allocationContext(yearsBack: Double = 1) -> NetWorthAllocationContext {
        let withShare = buckets.compactMap { bucket -> (CalendarDate, Double)? in
            guard let share = bucket.composition.holdingsSharePercent else { return nil }
            return (bucket.periodEnd, share)
        }
        guard let latest = withShare.last else {
            return NetWorthAllocationContext(currentSharePercent: nil, referenceSharePercent: nil, referencePeriodEnd: nil)
        }
        guard withShare.count >= 2 else {
            return NetWorthAllocationContext(currentSharePercent: latest.1, referenceSharePercent: nil, referencePeriodEnd: nil)
        }
        let target = yearsBack * 365.25
        let candidates = withShare.dropLast()
        var reference = candidates.first!
        for candidate in candidates {
            let distance = abs(Double(NetWorthDateMath.daysBetween(candidate.0, latest.0)) - target)
            let best = abs(Double(NetWorthDateMath.daysBetween(reference.0, latest.0)) - target)
            if distance < best { reference = candidate }
        }
        return NetWorthAllocationContext(
            currentSharePercent: latest.1,
            referenceSharePercent: reference.1,
            referencePeriodEnd: reference.0
        )
    }
}

// MARK: - Growth crossover target

/// Inputs and result of the growth-crossover target: the portfolio value at which market
/// growth covers a target share of each month's net-worth gain.
public enum NetWorthFireTarget {
    public enum Result: Sendable, Hashable {
        /// The return isn't positive, so no target value exists.
        case unreachable(currentGrowthSharePercent: Double)
        /// Growth already covers the target share at today's value.
        case reached(portfolioValueNeeded: Double, currentGrowthSharePercent: Double)
        /// Below target today; the gap and years to close it.
        case projected(portfolioValueNeeded: Double, gap: Double, yearsToTarget: Double, currentGrowthSharePercent: Double)

        public var currentGrowthSharePercent: Double {
            switch self {
            case .unreachable(let share): share
            case .reached(_, let share): share
            case .projected(_, _, _, let share): share
            }
        }

        public var portfolioValueNeeded: Double? {
            switch self {
            case .unreachable: nil
            case .reached(let value, _): value
            case .projected(let value, _, _, _): value
            }
        }
    }

    /// Held below 100%: at a full share the needed value is infinite.
    static let maxTargetFraction = 0.99

    /// - Parameters:
    ///   - annualReturnPercent: e.g. `10` for 10%.
    ///   - targetGrowthSharePercent: e.g. `80` for 80%.
    public static func compute(
        currentPortfolioValue: Double,
        monthlySavings: Double,
        annualReturnPercent: Double,
        targetGrowthSharePercent: Double
    ) -> Result {
        let monthlyReturn = annualReturnPercent / 100 / 12
        let target = min(max(targetGrowthSharePercent / 100, 0), maxTargetFraction)
        let growthNow = currentPortfolioValue * monthlyReturn
        let gainNow = growthNow + monthlySavings

        let currentShare: Double
        if gainNow > 0 {
            currentShare = growthNow / gainNow * 100
        } else if growthNow > 0 {
            currentShare = 100
        } else {
            currentShare = 0
        }

        guard monthlyReturn > 0 else { return .unreachable(currentGrowthSharePercent: currentShare) }
        guard monthlySavings > 0 else { return .reached(portfolioValueNeeded: 0, currentGrowthSharePercent: currentShare) }

        let needed = target / (1 - target) * (monthlySavings / monthlyReturn)
        if currentPortfolioValue >= needed {
            return .reached(portfolioValueNeeded: needed, currentGrowthSharePercent: currentShare)
        }
        let contributionOverReturn = monthlySavings / monthlyReturn
        let factor = (needed + contributionOverReturn) / (currentPortfolioValue + contributionOverReturn)
        let months = log(factor) / log(1 + monthlyReturn)
        return .projected(
            portfolioValueNeeded: needed,
            gap: needed - currentPortfolioValue,
            yearsToTarget: months / 12,
            currentGrowthSharePercent: currentShare
        )
    }
}

// MARK: - Portfolios used by the investment reports

/// A row of `GET /investments/portfolios`, reduced to what the report filters need.
public struct InsightsPortfolioOption: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let isEnabled: Bool

    public init(id: String, name: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey { case id, name, isEnabled }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? container.decode(String.self, forKey: .id) {
            id = string
        } else {
            id = String(try container.decode(Int.self, forKey: .id))
        }
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

struct InsightsPortfolioPage: Decodable {
    let data: [InsightsPortfolioOption]
}

/// A row of `GET /investments/portfolios/annualized-returns`.
public struct InsightsPortfolioReturn: Sendable, Hashable, Identifiable, Decodable {
    public let portfolioId: String
    public let portfolioName: String
    /// Annualized percentage, e.g. `12.34`; nil without enough history.
    public let annualizedReturn: Double?

    public var id: String { portfolioId }

    public init(portfolioId: String, portfolioName: String, annualizedReturn: Double?) {
        self.portfolioId = portfolioId
        self.portfolioName = portfolioName
        self.annualizedReturn = annualizedReturn
    }

    private enum CodingKeys: String, CodingKey { case portfolioId, portfolioName, annualizedReturn }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        portfolioId = try container.decode(String.self, forKey: .portfolioId)
        portfolioName = try container.decodeIfPresent(String.self, forKey: .portfolioName) ?? ""
        annualizedReturn = try container.decodeIfPresent(Double.self, forKey: .annualizedReturn)
    }
}

// MARK: - Endpoints

extension Endpoints {
    /// `GET /stats/net-worth-history`.
    public static func netWorthHistory(
        from: CalendarDate,
        to: CalendarDate,
        granularity: NetWorthHistoryGranularity
    ) -> Endpoint<NetWorthHistoryReport> {
        var query = QueryBuilder()
        query.add("from", day: from)
        query.add("to", day: to)
        query.add("granularity", granularity.rawValue)
        return Endpoint(.get, "/stats/net-worth-history", query: query.items)
    }

    /// `GET /stats/net-worth-drivers`. An empty `portfolioIds` means every enabled portfolio.
    public static func netWorthDrivers(
        from: CalendarDate,
        to: CalendarDate,
        granularity: InvestmentReportGranularity,
        portfolioIds: [String] = []
    ) -> Endpoint<NetWorthDriversReport> {
        var query = QueryBuilder()
        query.add("from", day: from)
        query.add("to", day: to)
        query.add("granularity", granularity.rawValue)
        query.add("portfolioIds", list: portfolioIds)
        return Endpoint(.get, "/stats/net-worth-drivers", query: query.items)
    }

    /// `GET /investments/portfolios`: the user's live portfolios (first 100).
    public static func insightsPortfolios() -> Endpoint<[InsightsPortfolioOption]> {
        Endpoint<InsightsPortfolioPage>(
            .get,
            "/investments/portfolios",
            query: [URLQueryItem(name: "limit", value: "100")]
        ).map(\.data)
    }

    /// `GET /investments/portfolios/annualized-returns`.
    public static func insightsPortfolioReturns() -> Endpoint<[InsightsPortfolioReturn]> {
        Endpoint(.get, "/investments/portfolios/annualized-returns")
    }
}

// MARK: - Helpers

enum NetWorthDateMath {
    static func daysBetween(_ from: CalendarDate, _ to: CalendarDate) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.dateComponents([.day], from: from.startDate(in: calendar), to: to.startDate(in: calendar)).day ?? 0
    }

    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
