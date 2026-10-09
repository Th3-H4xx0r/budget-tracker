import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Insights trends stats")
struct InsightsTrendsStatsTests {
    private let from = CalendarDate(year: 2025, month: 10, day: 9)
    private let to = CalendarDate(year: 2026, month: 10, day: 9)

    private func query(_ items: [URLQueryItem]) -> [String: String] {
        Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    @Test("Decodes the cumulative report with both periods")
    func decodesCumulative() throws {
        let json = """
        {"status":"success","response":{
          "currentPeriod":{"year":2026,"total":350.5,"data":[
            {"month":2,"monthLabel":"Nov","value":350.5,"periodValue":150.5},
            {"month":1,"monthLabel":"Oct","value":200,"periodValue":200}
          ]},
          "previousPeriod":{"year":2025,"total":0,"data":[]},
          "percentChange":-12
        }}
        """
        let report = try Endpoints.cumulativeData(from: from, to: to, metric: .expenses)
            .decodeBody(Data(json.utf8), JSONCoding.makeDecoder())

        #expect(report.currentPeriod.data.map(\.month) == [1, 2])
        #expect(report.currentPeriod.data.last?.value == Decimal(string: "350.5"))
        #expect(report.currentPeriod.data.last?.periodValue == Decimal(string: "150.5"))
        #expect(report.previousPeriod.data.isEmpty)
        #expect(report.percentChange == -12)
        #expect(report.hasData)
    }

    @Test("Cumulative query sends the metric and filters")
    func cumulativeQuery() {
        let selection = TrendsFilterSelection(
            categories: TrendsFilterGroup(mode: .exclude, ids: ["c1"]),
            payees: TrendsFilterGroup(mode: .include, ids: ["p1", "p2"]),
            accountIds: ["a1"]
        )
        let endpoint = Endpoints.cumulativeData(from: from, to: to, metric: .savings, filters: selection.reportFilters)
        let items = query(endpoint.queryItems)

        #expect(endpoint.path == "/stats/cumulative")
        #expect(items["from"] == "2025-10-09")
        #expect(items["to"] == "2026-10-09")
        #expect(items["metric"] == "savings")
        #expect(items["excludedCategoryIds"] == "c1")
        #expect(items["categoryIds"] == nil)
        #expect(items["payeeIds"] == "p1,p2")
        #expect(items["accountIds"] == "a1")
    }

    @Test("Filtered category spending sends the type and filter lists")
    func filteredSpendingQuery() throws {
        let filters = InsightsReportFilters(categoryIds: ["c1"], excludedTagIds: ["t1"])
        let endpoint = Endpoints.filteredSpendingsByCategories(from: from, to: to, type: .income, filters: filters)
        let items = query(endpoint.queryItems)
        #expect(items["type"] == "income")
        #expect(items["categoryIds"] == "c1")
        #expect(items["excludedTagIds"] == "t1")

        let json = ##"{"status":"success","response":{"c1":{"name":"A","color":"#111111","amount":5},"c2":{"name":"B","color":"#222222","amount":9}}}"##
        let rows = try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
        #expect(rows.map(\.id) == ["c2", "c1"])
    }

    @Test("Hiding the last included category flips to excluding it")
    func hideCategory() {
        let empty = TrendsFilterSelection()
        #expect(empty.hidingCategory("c1").categories == TrendsFilterGroup(mode: .exclude, ids: ["c1"]))

        let included = TrendsFilterSelection(categories: TrendsFilterGroup(mode: .include, ids: ["c1", "c2"]))
        #expect(included.hidingCategory("c1").categories == TrendsFilterGroup(mode: .include, ids: ["c2"]))

        let excluded = TrendsFilterSelection(categories: TrendsFilterGroup(mode: .exclude, ids: ["c1"]))
        #expect(excluded.hidingCategory("c1") == excluded)
        #expect(excluded.hidingCategory("c2").categories.ids == ["c1", "c2"])
        #expect(excluded.showingCategory("c1").categories == TrendsFilterGroup(mode: .exclude, ids: []))
        #expect(included.showingCategory("c1") == included)
    }

    @Test("Counts active filter groups and maps metrics to category types")
    func countsAndMetrics() {
        #expect(TrendsFilterSelection().activeCount == 0)
        #expect(TrendsFilterSelection(tags: TrendsFilterGroup(ids: ["t"]), accountIds: ["a"]).activeCount == 2)
        #expect(TrendsMetric.income.categoryType == .income)
        #expect(TrendsMetric.expenses.categoryType == .expense)
        #expect(TrendsMetric.savings.categoryType == nil)
        #expect(TrendsMetric(rawValue: "bogus") == nil)
    }
}
