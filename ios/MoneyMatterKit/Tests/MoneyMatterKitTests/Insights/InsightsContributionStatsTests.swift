import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Insights contribution stats")
struct InsightsContributionStatsTests {
    private func decode<Value>(_ endpoint: Endpoint<Value>, _ json: String) throws -> Value {
        try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
    }

    private func query(_ items: [URLQueryItem]) -> [String: String] {
        Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    private let from = CalendarDate(year: 2026, month: 1, day: 1)
    private let to = CalendarDate(year: 2026, month: 6, day: 30)

    @Test("Builds the investment contributions query with comma-joined portfolios")
    func contributionsQuery() {
        let endpoint = Endpoints.investmentContributions(from: from, to: to, granularity: .quarterly, portfolioIds: ["p1", "p2"])
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "/stats/investment-contributions")
        #expect(query(endpoint.queryItems) == [
            "from": "2026-01-01",
            "to": "2026-06-30",
            "granularity": "quarterly",
            "portfolioIds": "p1,p2",
        ])
    }

    @Test("Omits portfolioIds when every portfolio is in scope")
    func contributionsQueryWithoutPortfolios() {
        let endpoint = Endpoints.investmentContributions(from: from, to: to, granularity: .monthly)
        #expect(query(endpoint.queryItems)["portfolioIds"] == nil)
        #expect(query(endpoint.queryItems)["granularity"] == "monthly")
    }

    @Test("Decodes contributions buckets, portfolios, and summary figures")
    func decodesContributions() throws {
        let json = """
        {"status":"success","response":{
          "buckets":[
            {"periodStart":"2026-01-01","periodEnd":"2026-01-31","total":300,"byPortfolio":[{"portfolioId":"p1","amount":200},{"portfolioId":"p2","amount":100}],"savingsNet":1000},
            {"periodStart":"2026-02-01","periodEnd":"2026-02-28","total":-50.5,"byPortfolio":[{"portfolioId":"p1","amount":-50.5}],"savingsNet":500},
            {"periodStart":"2026-03-01","periodEnd":"2026-03-15","total":0,"byPortfolio":[],"savingsNet":0}
          ],
          "portfolios":[{"portfolioId":"p1","name":"Brokerage"},{"portfolioId":"p2","name":"IRA"}]
        }}
        """
        let report = try decode(Endpoints.investmentContributions(from: from, to: to, granularity: .monthly), json)

        #expect(report.buckets.count == 3)
        #expect(report.buckets[0].amount(forPortfolio: "p2") == 100)
        #expect(report.buckets[1].amount(forPortfolio: "p2") == 0)
        #expect(report.buckets[1].total == Decimal(string: "-50.5"))
        #expect(report.buckets[2].periodEnd == CalendarDate(year: 2026, month: 3, day: 15))
        #expect(report.portfolios.map(\.name) == ["Brokerage", "IRA"])
        #expect(report.totalContributed == Decimal(string: "249.5"))
        #expect(report.totalSavings == 1500)
        #expect(report.shareOfSavingsPercent == 17)
        #expect(report.chartAverage != nil)
        #expect(report.hasActivity)
    }

    @Test("Reports no share of savings and no average when they would mislead")
    func summaryEdgeCases() throws {
        let json = """
        {"status":"success","response":{
          "buckets":[{"periodStart":"2026-01-01","periodEnd":"2026-01-31","total":0,"byPortfolio":[],"savingsNet":-20}],
          "portfolios":[]
        }}
        """
        let report = try decode(Endpoints.investmentContributions(from: from, to: to, granularity: .monthly), json)
        #expect(report.shareOfSavingsPercent == nil)
        #expect(report.chartAverage == nil)
        #expect(report.averagePerBucket == 0)
        #expect(report.hasActivity == false)
    }

    @Test("Decodes venture contributions and builds the range query")
    func ventureContributions() throws {
        let endpoint = Endpoints.ventureContributions(from: from, to: to)
        #expect(endpoint.path == "/stats/venture-contributions")
        #expect(query(endpoint.queryItems) == ["from": "2026-01-01", "to": "2026-06-30"])

        let json = """
        {"status":"success","response":[{"dealId":"d1","name":"Seed round","amount":2500.75},{"dealId":"d2","amount":100}]}
        """
        let rows = try decode(endpoint, json)
        #expect(rows.map(\.id) == ["d1", "d2"])
        #expect(rows[0].amount == Decimal(string: "2500.75"))
        #expect(rows[1].name == "")
    }
}
