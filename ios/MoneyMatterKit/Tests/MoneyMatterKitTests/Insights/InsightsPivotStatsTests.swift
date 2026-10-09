import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Insights pivot stats")
struct InsightsPivotStatsTests {
    private func decode<Value>(_ endpoint: Endpoint<Value>, _ json: String) throws -> Value {
        try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
    }

    private func query(_ items: [URLQueryItem]) -> [String: String] {
        Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    private let from = CalendarDate(year: 2026, month: 1, day: 1)
    private let to = CalendarDate(year: 2026, month: 3, day: 31)

    @Test("Builds the pivot query, comma-joining filters and omitting empty ones")
    func pivotQuery() {
        let endpoint = Endpoints.pivotReport(
            from: from, to: to, granularity: .quarterly, rowDimension: .subcategory, measure: .income,
            accountIds: ["a1", "a2"]
        )
        #expect(endpoint.path == "/stats/pivot")
        #expect(query(endpoint.queryItems) == [
            "from": "2026-01-01", "to": "2026-03-31", "granularity": "quarterly",
            "rowDimension": "subcategory", "measure": "income", "accountIds": "a1,a2",
        ])
    }

    @Test("Decodes the pivot report and orders parents with their expanded children")
    func decodesPivot() throws {
        let json = """
        {"status":"success","response":{
          "columns":[
            {"key":"2026-01","periodStart":"2026-01-01","periodEnd":"2026-01-31","label":"Jan 2026"},
            {"key":"2026-02","periodStart":"2026-02-01","periodEnd":"2026-02-28","label":"Feb 2026"}
          ],
          "rows":[
            {"id":"small","label":"Fun","color":"#00ff00","parentId":null,"kind":"flat","values":{"2026-01":5},"total":5},
            {"id":"food","label":"Food","color":"#ff0000","parentId":null,"kind":"parent","values":{"2026-01":100,"2026-02":50.5},"total":150.5},
            {"id":"cafe","label":"Cafe","color":null,"parentId":"food","kind":"child","values":{"2026-02":50.5},"total":50.5},
            {"id":"uncategorized","label":"Uncategorized","color":null,"parentId":null,"kind":"mystery","values":{},"total":0}
          ],
          "columnTotals":{"2026-01":105,"2026-02":50.5},
          "grandTotal":155.5,
          "currencyCode":"EUR"
        }}
        """
        let report = try decode(Endpoints.pivotReport(from: from, to: to, granularity: .monthly, rowDimension: .category, measure: .expense), json)

        #expect(report.columns.map(\.key) == ["2026-01", "2026-02"])
        #expect(report.columns[1].periodStart == CalendarDate(year: 2026, month: 2, day: 1))
        #expect(report.currencyCode == "EUR")
        #expect(report.grandTotal == Decimal(string: "155.5"))
        #expect(report.columnTotal(for: report.columns[0]) == 105)
        #expect(report.rows[3].kind == .unknown)
        #expect(report.rows[1].value(for: report.columns[1]) == Decimal(string: "50.5"))
        #expect(report.rows[0].value(for: report.columns[1]) == 0)
        #expect(report.isEmpty == false)

        #expect(report.visibleRows(expanded: []).map(\.id) == ["food", "small", "uncategorized"])
        #expect(report.visibleRows(expanded: ["food"]).map(\.id) == ["food", "cafe", "small", "uncategorized"])
    }

    @Test("Decodes saved views leniently and skips malformed entries")
    func decodesSavedViews() throws {
        let json = """
        {"status":"success","response":{"locale":"en","savedPivotViews":[
          {"id":"v1","name":"Quarterly food","config":{"rowDimension":"category","granularity":"quarterly","measure":"expense",
            "from":"2025-01-01","to":"2025-12-31","categoryIds":["food"],"heatmap":true,"showDelta":false}},
          {"id":"broken","name":"No config"}
        ]}}
        """
        let views = try decode(Endpoints.savedPivotViews(), json).views
        #expect(views.count == 1)
        #expect(views[0].config.granularity == .quarterly)
        #expect(views[0].config.categoryIds == ["food"])
        #expect(views[0].config.from == CalendarDate(year: 2025, month: 1, day: 1))
        #expect(views[0].config.heatmap)

        let none = try decode(Endpoints.savedPivotViews(), #"{"status":"success","response":{}}"#)
        #expect(none.views.isEmpty)
    }

    @Test("Saving views PATCHes the full list with day strings and no empty filters")
    func encodesSavedViews() throws {
        let view = InsightsSavedPivotView(
            id: "v1",
            name: "Payees",
            config: InsightsSavedPivotViewConfig(rowDimension: .payee, granularity: .monthly, measure: .expense, from: from, to: to)
        )
        let endpoint = Endpoints.saveSavedPivotViews([view])
        #expect(endpoint.method == .patch)
        #expect(endpoint.path == "/user/settings")

        let client = APIClient(server: try ServerEndpoint(validating: "https://budget.example.com"))
        let data = try #require(try client.makeRequest(for: endpoint).0.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json.keys.sorted() == ["savedPivotViews"])
        let list = try #require(json["savedPivotViews"] as? [[String: Any]])
        let config = try #require(list.first?["config"] as? [String: Any])
        #expect(list.first?["name"] as? String == "Payees")
        #expect(config["rowDimension"] as? String == "payee")
        #expect(config["from"] as? String == "2026-01-01")
        #expect(config["to"] as? String == "2026-03-31")
        #expect(config["heatmap"] as? Bool == false)
        #expect(config["accountIds"] == nil)
    }
}

@Suite("Insights calculator math")
struct InsightsCalculatorMathTests {
    @Test("Zero horizon returns only the starting point and a flat summary")
    func zeroHorizon() {
        let params = InsightsProjectionParams(initialBalance: 1000, monthlyContribution: 100, timeHorizonYears: 0, annualReturnRate: 7, annualInflationRate: 3)
        let points = InsightsProjection.points(params)
        #expect(points.count == 1)
        let summary = InsightsProjection.summary(params, points: points)
        #expect(summary.totalContributions == 0)
        #expect(summary.nominalFinalValue == 1000)
        #expect(summary.realMultiplier == 1)
    }

    @Test("Without return or inflation the value equals what was invested")
    func noGrowth() {
        let params = InsightsProjectionParams(initialBalance: 500, monthlyContribution: 100, timeHorizonYears: 2, annualReturnRate: 0, annualInflationRate: 0)
        let points = InsightsProjection.points(params)
        #expect(points.count == 25)
        let summary = InsightsProjection.summary(params, points: points)
        #expect(abs(summary.nominalFinalValue - 2900) < 0.0001)
        #expect(abs(summary.totalInvested - 2900) < 0.0001)
        #expect(abs(summary.totalContributions - 2400) < 0.0001)
        #expect(abs(summary.nominalGrowth) < 0.0001)
        #expect(abs(summary.realMultiplier - 1) < 0.0001)
    }

    @Test("A lump sum compounds to the annual rate after a year and deflates by inflation")
    func lumpSum() {
        let params = InsightsProjectionParams(initialBalance: 10000, monthlyContribution: 0, timeHorizonYears: 1, annualReturnRate: 10, annualInflationRate: 2)
        let summary = InsightsProjection.summary(params, points: InsightsProjection.points(params))
        #expect(abs(summary.nominalFinalValue - 11000) < 0.01)
        #expect(abs(summary.realFinalValue - 11000 / 1.02) < 0.01)
        #expect(abs(summary.nominalGrowth - 1000) < 0.01)
    }

    @Test("Monthly contributions are added at each month's end")
    func contributions() {
        let params = InsightsProjectionParams(initialBalance: 0, monthlyContribution: 100, timeHorizonYears: 1.0 / 12, annualReturnRate: 12, annualInflationRate: 0)
        let points = InsightsProjection.points(params)
        #expect(points.count == 2)
        #expect(abs(points[1].nominal - 100) < 0.0001)
    }

    @Test("Average net income spreads the total over the buckets, never below zero")
    func averageNetIncome() {
        let periods = (1...3).map { month in
            CashFlowPeriod(
                periodStart: CalendarDate(year: 2026, month: month, day: 1),
                periodEnd: CalendarDate(year: 2026, month: month, day: 28),
                income: 1000, expenses: 900, netFlow: 100, categories: []
            )
        }
        let report = CashFlowReport(periods: periods, totals: CashFlowTotals(income: 3000, expenses: 2900, netFlow: 100, savingsRate: 3))
        #expect(InsightsNetIncomeWindow.averageNetIncome(report) == 33.33)

        let negative = CashFlowReport(periods: periods, totals: CashFlowTotals(income: 0, expenses: 300, netFlow: -300, savingsRate: 0))
        #expect(InsightsNetIncomeWindow.averageNetIncome(negative) == 0)
        #expect(InsightsNetIncomeWindow.averageNetIncome(CashFlowReport(periods: [], totals: .zero)) == 0)
    }

    @Test("Net income windows cover whole months through the current one")
    func windows() {
        let today = CalendarDate(year: 2026, month: 3, day: 15)
        let six = InsightsNetIncomeWindow.sixMonths.range(today: today)
        #expect(six.from == CalendarDate(year: 2025, month: 10, day: 1))
        #expect(six.to == CalendarDate(year: 2026, month: 3, day: 31))
        #expect(InsightsNetIncomeWindow.all.range(today: today).from == CalendarDate(year: 2000, month: 1, day: 1))
        #expect(InsightsMarketIndicator.all.first?.averageAnnualReturn == 10)
    }
}
