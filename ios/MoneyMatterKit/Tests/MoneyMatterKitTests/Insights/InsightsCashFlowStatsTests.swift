import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Insights cash flow stats")
struct InsightsCashFlowStatsTests {
    private func decode<Value>(_ endpoint: Endpoint<Value>, _ json: String) throws -> Value {
        try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
    }

    private func query(_ items: [URLQueryItem]) -> [String: String] {
        Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    private let day1 = CalendarDate(year: 2026, month: 1, day: 1)
    private let day2 = CalendarDate(year: 2026, month: 3, day: 31)

    @Test("Decodes the cash flow report, sorting periods oldest first")
    func decodesCashFlow() throws {
        let json = """
        {"status":"success","response":{
          "periods":[
            {"periodStart":"2026-02-01","periodEnd":"2026-02-28","income":100.5,"expenses":40,"netFlow":60.5},
            {"periodStart":"2026-01-01","periodEnd":"2026-01-31","income":2000,"expenses":1500.25,"netFlow":499.75,
             "categories":[{"categoryId":"c1","name":"Food","color":"#ff0000","incomeAmount":0,"expenseAmount":300}]}
          ],
          "totals":{"income":2100.5,"expenses":1540.25,"netFlow":560.25,"savingsRate":27}
        }}
        """
        let report = try decode(Endpoints.cashFlow(from: day1, to: day2, granularity: .monthly), json)

        #expect(report.periods.map(\.periodStart) == [day1, CalendarDate(year: 2026, month: 2, day: 1)])
        #expect(report.periods[0].expenses == Decimal(string: "1500.25"))
        #expect(report.periods[0].categories.first?.expenseAmount == 300)
        #expect(report.periods[1].categories.isEmpty)
        #expect(report.totals.savingsRate == 27)
        #expect(report.totals.netFlow == Decimal(string: "560.25"))
        #expect(report.isEmpty == false)
        #expect(report.categoryTotals.map(\.categoryId) == ["c1"])
    }

    @Test("Missing totals decode as zero and an all-zero report is empty")
    func decodesEmptyReport() throws {
        let json = """
        {"status":"success","response":{"periods":[
          {"periodStart":"2026-01-01","periodEnd":"2026-01-31","income":0,"expenses":0,"netFlow":0}
        ]}}
        """
        let report = try decode(Endpoints.cashFlow(from: day1, to: day2, granularity: .weekly), json)
        #expect(report.totals == .zero)
        #expect(report.isEmpty)
    }

    @Test("Cash flow query sends days, granularity, comma-joined filters, and excludePlanned only when on")
    func cashFlowQuery() {
        let filters = InsightsReportFilters(accountIds: ["a1", "a2"], excludedCategoryIds: ["c9"], tagIds: ["t1"])
        let endpoint = Endpoints.cashFlow(from: day1, to: day2, granularity: .biweekly, filters: filters)
        let items = query(endpoint.queryItems)

        #expect(endpoint.path == "/stats/cash-flow")
        #expect(items["from"] == "2026-01-01")
        #expect(items["to"] == "2026-03-31")
        #expect(items["granularity"] == "biweekly")
        #expect(items["accountIds"] == "a1,a2")
        #expect(items["excludedCategoryIds"] == "c9")
        #expect(items["tagIds"] == "t1")
        #expect(items["categoryIds"] == nil)
        #expect(items["excludePlanned"] == nil)

        let planned = Endpoints.cashFlow(from: day1, to: day2, granularity: .monthly, excludePlanned: true)
        #expect(query(planned.queryItems)["excludePlanned"] == "true")
    }

    @Test("Decodes per-type category spending, largest expense first")
    func decodesByType() throws {
        let json = """
        {"status":"success","response":{
          "c1":{"name":"Salary","color":"#00ff00","income":3000,"expense":0},
          "c2":{"name":"Food","color":"#ff0000","income":10,"expense":450.5},
          "c3":{"name":"Rent","color":"#0000ff","income":0,"expense":1200}
        }}
        """
        let rows = try decode(Endpoints.spendingsByCategoriesByType(from: day1, to: day2), json)
        #expect(rows.map(\.id) == ["c3", "c2", "c1"])
        #expect(rows[1].expense == Decimal(string: "450.5"))
        #expect(rows[2].income == 3000)
    }

    @Test("Per-type spending query mirrors the web params")
    func byTypeQuery() {
        let endpoint = Endpoints.spendingsByCategoriesByType(
            from: day1, to: day2, categoryIds: ["c1", "c2"], excludePlanned: true
        )
        let items = query(endpoint.queryItems)
        #expect(endpoint.path == "/stats/spendings-by-categories")
        #expect(items["groupByType"] == "true")
        #expect(items["categoryIds"] == "c1,c2")
        #expect(items["excludePlanned"] == "true")
        #expect(items["excludedCategoryIds"] == nil)
        #expect(query(Endpoints.spendingsByCategoriesByType().queryItems)["excludePlanned"] == nil)
    }

    @Test("Filters count active groups")
    func filterCount() {
        #expect(InsightsReportFilters().isEmpty)
        #expect(InsightsReportFilters(accountIds: ["a"], payeeIds: ["p"]).activeCount == 2)
    }
}

@Suite("Insights cash flow money flow")
struct InsightsCashFlowMoneyFlowTests {
    private let categories: [MoneyMatterKit.Category] = [
        MoneyMatterKit.Category(id: "income", name: "Income", color: "#00ff00"),
        MoneyMatterKit.Category(id: "salary", name: "Salary", parentId: "income"),
        MoneyMatterKit.Category(id: "food", name: "Food", color: "#ff0000"),
        MoneyMatterKit.Category(id: "groceries", name: "Groceries", parentId: "food"),
        MoneyMatterKit.Category(id: "rent", name: "Rent"),
        MoneyMatterKit.Category(id: "savings", name: "Savings"),
    ]

    @Test("Rolls spending up to the chosen level and keeps net savings as cash")
    func rollsUp() {
        let flow = CashFlowMoneyFlowBuilder.build(
            data: [
                CategorySpendingByType(id: "salary", name: "Salary", color: "#0f0", income: 3000, expense: 0),
                CategorySpendingByType(id: "groceries", name: "Groceries", color: "#f00", income: 0, expense: 400),
                CategorySpendingByType(id: "food", name: "Food", color: "#f00", income: 0, expense: 100),
                CategorySpendingByType(id: "rent", name: "Rent", color: "#00f", income: 0, expense: 1500),
            ],
            categories: categories,
            sourceLevel: 2,
            expenseLevel: 1
        )

        #expect(flow.income == 3000)
        #expect(flow.expenses == 2000)
        #expect(flow.net == 1000)
        #expect(flow.deficit == 0)
        #expect(flow.sources.map(\.id) == ["salary"])
        #expect(flow.sources.first?.parentName == "Income")
        #expect(flow.expenseNodes.map(\.id) == ["rent", "food"])
        #expect(flow.expenseNodes.last?.value == 500)
        #expect(flow.savingsNodes.map(\.kind) == [.keptAsCash])
        #expect(flow.savingsNodes.first?.value == 1000)
    }

    @Test("Savings categories and investments become destinations, with a deficit when they exceed income")
    func destinationsAndDeficit() {
        let flow = CashFlowMoneyFlowBuilder.build(
            data: [
                CategorySpendingByType(id: "salary", name: "Salary", color: "#0f0", income: 1000, expense: 0),
                CategorySpendingByType(id: "rent", name: "Rent", color: "#00f", income: 0, expense: 800),
                CategorySpendingByType(id: "savings", name: "Savings", color: "#ccc", income: 50, expense: 250),
            ],
            categories: categories,
            destinations: [
                CashFlowMoneyFlowDestination(id: "p1", name: "Brokerage", value: 300),
                CashFlowMoneyFlowDestination(id: "p2", name: "Withdrawn", value: -100),
            ],
            savingsCategoryIds: ["savings"]
        )

        #expect(flow.expenses == 800)
        #expect(flow.savings == 500)
        #expect(flow.deficit == 300)
        #expect(flow.sources.last?.kind == .deficit)
        #expect(flow.savingsNodes.map(\.id) == ["p1", "savings"])
        #expect(flow.savingsNodes.first?.share == 0.6)
    }

    @Test("Folds everything past the top N into one other node")
    func foldsOther() {
        let data = (1...5).map {
            CategorySpendingByType(id: "e\($0)", name: "E\($0)", color: "#000", income: 0, expense: Decimal(100 * $0))
        }
        let flow = CashFlowMoneyFlowBuilder.build(data: data, categories: [], topN: 2)
        #expect(flow.expenseNodes.map(\.id) == ["e5", "e4", "other"])
        #expect(flow.expenseNodes.last?.value == 600)
        #expect(flow.expenseNodes.last?.children.count == 3)
    }

    @Test("Decodes only the savings categories from user settings")
    func savingsSettings() throws {
        let json = #"{"status":"success","response":{"savingsCategoryIds":["s1"],"other":{"x":1}}}"#
        let settings = try Endpoints.cashFlowSavingsSettings().decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
        #expect(settings.savingsCategoryIds == ["s1"])

        let missing = try Endpoints.cashFlowSavingsSettings()
            .decodeBody(Data(#"{"status":"success","response":{}}"#.utf8), JSONCoding.makeDecoder())
        #expect(missing.savingsCategoryIds.isEmpty)
    }
}
