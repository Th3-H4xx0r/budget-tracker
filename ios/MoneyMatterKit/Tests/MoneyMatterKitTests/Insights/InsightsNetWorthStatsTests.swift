import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Insights net worth stats")
struct InsightsNetWorthStatsTests {
    private func decode<Value>(_ endpoint: Endpoint<Value>, _ json: String) throws -> Value {
        try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
    }

    private func query(_ items: [URLQueryItem]) -> [String: String] {
        Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    private let from = CalendarDate(year: 2025, month: 1, day: 1)
    private let to = CalendarDate(year: 2026, month: 1, day: 31)

    // MARK: History

    @Test("Builds the net worth history query")
    func historyQuery() {
        let endpoint = Endpoints.netWorthHistory(from: from, to: to, granularity: .weekly)
        #expect(endpoint.path == "/stats/net-worth-history")
        #expect(query(endpoint.queryItems) == ["from": "2025-01-01", "to": "2026-01-31", "granularity": "weekly"])
    }

    private let historyJSON = """
    {"status":"success","response":{
      "points":[
        {"date":"2025-01-01","assets":{"cash":1000,"investments":500,"vehicles":0,"ventures":0,"crypto":7},
         "assetsTotal":1500,"liabilities":{"credit-card":-200,"loan":0,"overdraft":0},"liabilitiesTotal":-200,"netWorth":1300},
        {"date":"2026-01-31","assets":{"cash":2000,"investments":1000,"vehicles":0,"ventures":0},
         "assetsTotal":3000,"liabilities":{"credit-card":0,"loan":-400,"overdraft":0},"liabilitiesTotal":-400,"netWorth":2600}
      ],
      "degraded":{"unpricedSecurities":[{"securityId":12,"symbol":null,"name":"Acme"}],"fxFallbackCurrencies":["XYZ"]}
    }}
    """

    @Test("Decodes history points, ignoring unknown kinds, and the degraded notice")
    func decodesHistory() throws {
        let report = try decode(Endpoints.netWorthHistory(from: from, to: to, granularity: .monthly), historyJSON)

        #expect(report.points.count == 2)
        #expect(report.points[0].value(for: NetWorthAssetKind.cash) == 1000)
        #expect(report.points[0].value(for: NetWorthLiabilityKind.creditCard) == -200)
        #expect(report.points[1].netWorth == 2600)
        #expect(report.hasData)
        #expect(report.assetKindsWithActivity == [.cash, .investments])
        #expect(report.liabilityKindsWithActivity == [.creditCard, .loan])
        #expect(report.degraded?.unpricedSecurities.first?.label == "Acme")
        #expect(report.degraded?.unpricedSecurities.first?.securityId == "12")
        #expect(report.degraded?.fxFallbackCurrencies == ["XYZ"])
    }

    @Test("Filters kinds and derives the period change, CAGR, and average owed")
    func historyDerivations() throws {
        let report = try decode(Endpoints.netWorthHistory(from: from, to: to, granularity: .monthly), historyJSON)

        let all = report.displayPoints(assetKinds: NetWorthAssetKind.allCases, liabilityKinds: NetWorthLiabilityKind.allCases)
        #expect(all.map(\.netWorth) == [1300, 2600])
        let change = NetWorthHistoryMath.periodChange(all)
        #expect(change.amount == 1300)
        #expect(change.percent == 100)
        let cagr = try #require(NetWorthHistoryMath.annualizedGrowthPercent(all))
        // 395 days from 1,300 to 2,600.
        #expect(abs(cagr - 89.83) < 0.5)
        #expect(NetWorthHistoryMath.averageOwed(all) == 300)

        let cashOnly = report.displayPoints(assetKinds: [.cash], liabilityKinds: [.loan])
        #expect(cashOnly.map(\.netWorth) == [1000, 1600])
        #expect(NetWorthHistoryMath.averageOwed(cashOnly) == 200)
    }

    @Test("Treats an all-zero series as no data and an empty degraded object as clean")
    func emptyHistory() throws {
        let json = """
        {"status":"success","response":{"points":[{"date":"2026-01-31","assets":{},"assetsTotal":0,"liabilities":{},"liabilitiesTotal":0,"netWorth":0}],"degraded":{}}}
        """
        let report = try decode(Endpoints.netWorthHistory(from: from, to: to, granularity: .monthly), json)
        #expect(report.hasData == false)
        #expect(report.degraded == nil)
        let points = report.displayPoints(assetKinds: [], liabilityKinds: [])
        #expect(NetWorthHistoryMath.periodChange(points).percent == nil)
        #expect(NetWorthHistoryMath.annualizedGrowthPercent(points) == nil)
    }

    @Test("Resolves stored kind selections against the available kinds")
    func resolveSelection() {
        #expect(NetWorthHistoryMath.resolveSelection(stored: [String](), available: ["a", "b"]) == ["a", "b"])
        #expect(NetWorthHistoryMath.resolveSelection(stored: ["b", "z"], available: ["a", "b"]) == ["b"])
        #expect(NetWorthHistoryMath.resolveSelection(stored: ["z"], available: ["a", "b"]) == ["a", "b"])
    }

    @Test("Picks the automatic granularity and disables ones past the bucket cap")
    func granularityRules() {
        let short = (CalendarDate(year: 2026, month: 1, day: 1), CalendarDate(year: 2026, month: 12, day: 31))
        #expect(NetWorthHistoryGranularity.automatic(from: short.0, to: short.1) == .weekly)
        #expect(NetWorthHistoryGranularity.monthly.bucketCount(from: short.0, to: short.1) == 12)
        #expect(NetWorthHistoryGranularity.quarterly.bucketCount(from: short.0, to: short.1) == 4)
        #expect(NetWorthHistoryGranularity.yearly.bucketCount(from: short.0, to: short.1) == 1)

        let mid = (CalendarDate(year: 2022, month: 1, day: 1), CalendarDate(year: 2026, month: 12, day: 31))
        #expect(NetWorthHistoryGranularity.automatic(from: mid.0, to: mid.1) == .monthly)

        let long = (CalendarDate(year: 2010, month: 1, day: 1), CalendarDate(year: 2026, month: 12, day: 31))
        #expect(NetWorthHistoryGranularity.automatic(from: long.0, to: long.1) == .quarterly)
        #expect(NetWorthHistoryGranularity.disabled(from: long.0, to: long.1) == [.weekly])
    }

    // MARK: Drivers

    @Test("Builds the net worth drivers query")
    func driversQuery() {
        let endpoint = Endpoints.netWorthDrivers(from: from, to: to, granularity: .yearly, portfolioIds: ["p1"])
        #expect(endpoint.path == "/stats/net-worth-drivers")
        #expect(query(endpoint.queryItems) == [
            "from": "2025-01-01",
            "to": "2026-01-31",
            "granularity": "yearly",
            "portfolioIds": "p1",
        ])
    }

    private let driversJSON = """
    {"status":"success","response":{
      "buckets":[
        {"periodStart":"2025-01-01","periodEnd":"2025-01-31",
         "savings":{"income":3000,"expenses":2000,"net":1000},
         "investments":{"growth":150,"priceEffect":140,"dividends":20,"feesAndTaxes":10,"byPortfolio":[{"portfolioId":"p1","growth":150}]},
         "composition":{"holdingsValue":10000,"cashValue":10000}},
        {"periodStart":"2025-02-01","periodEnd":"2026-01-31",
         "savings":{"income":2000,"expenses":1500,"net":500},
         "investments":{"growth":-50,"priceEffect":-50,"dividends":0,"feesAndTaxes":0,"byPortfolio":[]},
         "composition":{"holdingsValue":15000,"cashValue":5000}}
      ],
      "portfolios":[{"portfolioId":"p1","name":"Brokerage"}]
    }}
    """

    @Test("Decodes drivers buckets and derives cumulative totals and seeds")
    func decodesDrivers() throws {
        let report = try decode(Endpoints.netWorthDrivers(from: from, to: to, granularity: .monthly), driversJSON)

        #expect(report.buckets.count == 2)
        #expect(report.buckets[0].savings.expenses == 2000)
        #expect(report.buckets[0].investments.byPortfolio.first?.growth == 150)
        #expect(report.portfolios.first?.name == "Brokerage")
        #expect(report.degraded == nil)
        #expect(report.hasData)
        #expect(report.hasPortfolioActivity)

        let series = report.cumulativeSeries
        #expect(series.map(\.savedCumulative) == [1000, 1500])
        #expect(series.map(\.grownCumulative) == [150, 100])

        let seeds = report.targetSeeds
        #expect(seeds.currentPortfolioValue == 15000)
        // 1,500 saved over the 13 calendar months the window spans.
        #expect(seeds.averageMonthlySavings == Decimal(1500) / Decimal(13))

        #expect(report.buckets[0].composition.holdingsSharePercent == 50)
        let context = report.allocationContext()
        #expect(context.currentSharePercent == 75)
        #expect(context.referenceSharePercent == 50)
        #expect(context.referencePeriodEnd == CalendarDate(year: 2025, month: 1, day: 31))
    }

    // MARK: Growth crossover target

    @Test("Solves the needed value and gap for the worked example")
    func fireWorkedExample() {
        let result = NetWorthFireTarget.compute(
            currentPortfolioValue: 187_062,
            monthlySavings: 800,
            annualReturnPercent: 12,
            targetGrowthSharePercent: 90
        )
        guard case let .projected(needed, gap, years, _) = result else {
            Issue.record("Expected a projected result, got \(result)")
            return
        }
        #expect(abs(needed - 720_000) < 0.01)
        #expect(abs(gap - 532_938) < 0.01)
        #expect(abs(years - 9.19) < 0.05)

        let near = NetWorthFireTarget.compute(
            currentPortfolioValue: 600_000,
            monthlySavings: 800,
            annualReturnPercent: 12,
            targetGrowthSharePercent: 90
        )
        guard case let .projected(_, _, nearYears, _) = near else {
            Issue.record("Expected a projected result")
            return
        }
        #expect(nearYears < years)
    }

    @Test("Reports the target reached once the current value clears it")
    func fireReached() {
        let result = NetWorthFireTarget.compute(
            currentPortfolioValue: 800_000,
            monthlySavings: 800,
            annualReturnPercent: 12,
            targetGrowthSharePercent: 90
        )
        guard case let .reached(needed, _) = result else {
            Issue.record("Expected reached, got \(result)")
            return
        }
        #expect(abs(needed - 720_000) < 0.01)
    }

    @Test("Is unreachable without a positive return")
    func fireNoReturn() {
        let result = NetWorthFireTarget.compute(
            currentPortfolioValue: 100_000,
            monthlySavings: 800,
            annualReturnPercent: 0,
            targetGrowthSharePercent: 90
        )
        #expect(result == .unreachable(currentGrowthSharePercent: 0))
        #expect(result.portfolioValueNeeded == nil)
    }

    @Test("Treats zero or negative saving as already past the crossover")
    func fireNoSaving() {
        let zero = NetWorthFireTarget.compute(
            currentPortfolioValue: 100_000,
            monthlySavings: 0,
            annualReturnPercent: 12,
            targetGrowthSharePercent: 90
        )
        #expect(zero == .reached(portfolioValueNeeded: 0, currentGrowthSharePercent: 100))

        let drawdown = NetWorthFireTarget.compute(
            currentPortfolioValue: 100_000,
            monthlySavings: -2_000,
            annualReturnPercent: 12,
            targetGrowthSharePercent: 90
        )
        #expect(drawdown == .reached(portfolioValueNeeded: 0, currentGrowthSharePercent: 100))
    }

    @Test("Clamps a 100% or higher target so the needed value stays finite")
    func fireClampsTarget() {
        for target in [100.0, 150.0] {
            let result = NetWorthFireTarget.compute(
                currentPortfolioValue: 187_062,
                monthlySavings: 800,
                annualReturnPercent: 12,
                targetGrowthSharePercent: target
            )
            let needed = result.portfolioValueNeeded ?? .infinity
            #expect(needed.isFinite)
            #expect(abs(needed - 7_920_000) < 0.01)
        }
    }

    @Test("Measures the current growth share at today's value")
    func fireCurrentShare() {
        let result = NetWorthFireTarget.compute(
            currentPortfolioValue: 120_000,
            monthlySavings: 800,
            annualReturnPercent: 12,
            targetGrowthSharePercent: 90
        )
        #expect(abs(result.currentGrowthSharePercent - 60) < 0.00001)
    }

    // MARK: Portfolios

    @Test("Decodes the portfolio list page and annualized returns")
    func portfolios() throws {
        let list = Endpoints.insightsPortfolios()
        #expect(list.path == "/investments/portfolios")
        #expect(query(list.queryItems) == ["limit": "100"])
        let page = """
        {"status":"success","response":{"data":[{"id":"p1","name":"Brokerage","isEnabled":true,"userId":1},{"id":"p2","name":"Old","isEnabled":false}],"pagination":{"limit":100,"offset":0,"page":1}}}
        """
        let portfolios = try decode(list, page)
        #expect(portfolios.map(\.id) == ["p1", "p2"])
        #expect(portfolios[1].isEnabled == false)

        let returns = """
        {"status":"success","response":[{"portfolioId":"p1","portfolioName":"Brokerage","annualizedReturn":12.34,"hasSufficientHistory":true},{"portfolioId":"p2","portfolioName":"New","annualizedReturn":null}]}
        """
        let rows = try decode(Endpoints.insightsPortfolioReturns(), returns)
        #expect(rows[0].annualizedReturn == 12.34)
        #expect(rows[1].annualizedReturn == nil)
    }
}
