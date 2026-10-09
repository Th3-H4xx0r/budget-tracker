import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Insights dashboard settings")
struct InsightsDashboardSettingsTests {
    private func decode<Value>(_ endpoint: Endpoint<Value>, _ json: String) throws -> Value {
        try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
    }

    private func body<Value>(_ endpoint: Endpoint<Value>) throws -> [String: Any] {
        let client = APIClient(server: try ServerEndpoint(validating: "https://budget.example.com"))
        let data = try #require(try client.makeRequest(for: endpoint).0.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Decodes the dashboard slice of user settings, keeping unknown config keys")
    func decodesSettings() throws {
        let json = """
        {"status":"success","response":{
          "locale":"en",
          "includeCreditLimitInStats":true,
          "dashboard":{"widgets":[
            {"widgetId":"balance-trend","colSpan":2,"rowSpan":1,"config":{"spikesEnabled":true,"spikeMaxCount":5}},
            {"widgetId":"category-spending-tracker","colSpan":1,"config":{"selectedCategoryIds":["c1","c2"],"includePlanned":false}},
            {"colSpan":1},
            {"widgetId":"future-widget"}
          ]}
        }}
        """
        let settings = try decode(Endpoints.dashboardSettings(), json)

        #expect(settings.includeCreditLimitInStats)
        let widgets = try #require(settings.widgets)
        #expect(widgets.map(\.widgetId) == ["balance-trend", "category-spending-tracker", "future-widget"])
        #expect(widgets[0].config?["spikeMaxCount"] == .number(5))
        #expect(widgets[0].includePlanned)
        #expect(widgets[1].selectedCategoryIds == ["c1", "c2"])
        #expect(widgets[1].includePlanned == false)
        #expect(widgets[1].rowSpan == nil)
        #expect(widgets[2].colSpan == 1)
    }

    @Test("Settings without a dashboard decode to no saved layout")
    func decodesMissingDashboard() throws {
        let settings = try decode(Endpoints.dashboardSettings(), #"{"status":"success","response":{}}"#)
        #expect(settings.widgets == nil)
        #expect(settings.includeCreditLimitInStats == false)
    }

    @Test("Empty or missing layouts resolve to the web default; unknown ids and repeats drop")
    func resolvesLayout() {
        let defaults = ["balance-trend", "latest-records", "subscriptions-overview", "spending-categories"]
        #expect(DashboardLayout.resolve(saved: nil).map(\.widgetId) == defaults)
        #expect(DashboardLayout.resolve(saved: []).map(\.widgetId) == defaults)
        #expect(DashboardLayout.defaultWidgets[1].rowSpan == 2)

        let saved = [
            DashboardWidgetConfig(widgetId: "net-worth", colSpan: 1),
            DashboardWidgetConfig(widgetId: "nope", colSpan: 1),
            DashboardWidgetConfig(widgetId: "net-worth", colSpan: 2),
            DashboardWidgetConfig(widgetId: "cash-flow", colSpan: 1),
        ]
        #expect(DashboardLayout.resolve(saved: saved).map(\.widgetId) == ["net-worth", "cash-flow"])
        #expect(DashboardLayout.hiddenKinds(in: DashboardLayout.resolve(saved: saved)).count == DashboardWidgetKind.allCases.count - 2)
    }

    @Test("PATCH sends the full widget list under dashboard, keeping sizes and config")
    func encodesPatch() throws {
        let widgets = [
            DashboardWidgetConfig(widgetId: "balance-trend", colSpan: 2, rowSpan: 1, config: ["spikesEnabled": .bool(true)]),
            DashboardWidgetConfig(kind: .creditUtilization),
        ]
        let endpoint = Endpoints.saveDashboardWidgets(widgets)
        #expect(endpoint.method == .patch)
        #expect(endpoint.path == "/user/settings")

        let json = try body(endpoint)
        #expect(json.keys.sorted() == ["dashboard"])
        let dashboard = try #require(json["dashboard"] as? [String: Any])
        let list = try #require(dashboard["widgets"] as? [[String: Any]])
        #expect(list.count == 2)
        #expect(list[0]["widgetId"] as? String == "balance-trend")
        #expect(list[0]["colSpan"] as? Int == 2)
        #expect((list[0]["config"] as? [String: Any])?["spikesEnabled"] as? Bool == true)
        #expect(list[1]["widgetId"] as? String == "credit-utilization")
        #expect(list[1]["colSpan"] as? Int == 1)
        #expect(list[1]["config"] == nil)
    }

    @Test("Merging config keeps other keys and overrides the given ones")
    func mergesConfig() {
        let widget = DashboardWidgetConfig(
            widgetId: "category-spending-tracker",
            colSpan: 1,
            config: ["selectedCategoryIds": .array([.string("a")]), "includePlanned": .bool(false)]
        )
        let merged = widget.mergingConfig(["includePlanned": .bool(true)])
        #expect(merged.selectedCategoryIds == ["a"])
        #expect(merged.includePlanned)
    }

    @Test("Decodes the planned summary and aggregates it over the scoped accounts")
    func plannedSummary() throws {
        let json = """
        {"status":"success","response":[
          {"accountId":"a1","currencyCode":"EUR","plannedDelta":-50,"refPlannedDelta":-55.5,"count":2,"latestTime":"2026-11-02T10:00:00.000Z"},
          {"accountId":"a2","currencyCode":"USD","plannedDelta":100,"refPlannedDelta":100,"count":1,"latestTime":"2026-12-01T00:00:00Z"},
          {"accountId":"archived","currencyCode":"USD","plannedDelta":999,"refPlannedDelta":999,"count":9,"latestTime":"2027-01-01T00:00:00Z"}
        ]}
        """
        let entries = try decode(Endpoints.dashboardPlannedSummary(), json)
        #expect(entries.count == 3)
        #expect(entries[0].refPlannedDelta == Decimal(string: "-55.5"))

        let aggregate = DashboardPlannedAggregate(entries: entries, accountIDs: ["a1", "a2"])
        #expect(aggregate.refPlannedDelta == Decimal(string: "44.5"))
        #expect(aggregate.count == 3)
        #expect(aggregate.latestTime == entries[1].latestTime)

        let accounts = [
            Account(id: "a1", name: "Main", currencyCode: "EUR"),
            Account(id: "archived", name: "Old", currencyCode: "USD", status: .archived),
            Account(id: "car", name: "Car", currencyCode: "USD", accountCategory: .vehicle),
        ]
        #expect(DashboardPlannedAggregate.projectedAccounts(accounts).map(\.id) == ["a1"])
    }

    @Test("Credit used respects whether the balance includes the limit")
    func creditMath() {
        #expect(DashboardCreditMath.creditUsed(balance: 700, creditLimit: 1000, balanceIncludesCreditLimit: true) == 300)
        #expect(DashboardCreditMath.creditUsed(balance: -250, creditLimit: 1000, balanceIncludesCreditLimit: false) == 250)
        #expect(DashboardCreditMath.creditUsed(balance: 1200, creditLimit: 1000, balanceIncludesCreditLimit: true) == 0)
        #expect(DashboardCreditMath.utilization(used: 333, limit: 1000) == 33)
        #expect(DashboardCreditMath.utilization(used: 1500, limit: 1000) == 100)
        #expect(DashboardCreditMath.utilization(used: 10, limit: 0) == 0)
    }

    @Test("Credit lines keep active counted accounts with a limit, highest utilization first")
    func creditLines() {
        let accounts = [
            Account(id: "manual", name: "Manual", currencyCode: "USD", currentBalance: -400, creditLimit: 1000, type: .system),
            Account(id: "bank", name: "Bank", currencyCode: "USD", currentBalance: 100, creditLimit: 1000, type: .monobank),
            Account(id: "nolimit", name: "Debit", currencyCode: "USD", currentBalance: 50),
            Account(id: "excluded", name: "Hidden", currencyCode: "USD", creditLimit: 500, excludeFromStats: true),
        ]
        let lines = DashboardCreditLine.lines(accounts: accounts, includeCreditLimitInStats: false)
        #expect(lines.map(\.id) == ["bank", "manual"])
        #expect(lines[0].utilization == 90)
        #expect(lines[1].used == 400)

        let withLimit = DashboardCreditLine.lines(accounts: accounts, includeCreditLimitInStats: true)
        #expect(withLimit.first { $0.id == "manual" }?.used == 1400)
    }
}

@Suite("Insights dashboard net worth")
struct InsightsDashboardNetWorthTests {
    private func point(_ year: Int, _ month: Int, _ day: Int, total: Decimal, ventures: Decimal = 0, loans: Decimal = 0) -> BalancePoint {
        BalancePoint(
            date: CalendarDate(year: year, month: month, day: day),
            totalBalance: total,
            accountsBalance: total - ventures - loans,
            venturesBalance: ventures,
            loansBalance: loans
        )
    }

    @Test("Include toggles read from config, defaulting to included")
    func includes() {
        #expect(DashboardNetWorthIncludes(config: nil) == .all)
        let config: [String: DashboardConfigValue] = ["includeLoans": .bool(false), "includeVentures": .string("x")]
        let includes = DashboardNetWorthIncludes(config: config)
        #expect(includes == DashboardNetWorthIncludes(ventures: true, vehicles: true, loans: false))

        let sample = point(2026, 1, 1, total: 900, ventures: 100, loans: -200)
        #expect(DashboardNetWorthIncludes.all.compose(sample) == 900)
        #expect(includes.compose(sample) == 1100)
    }

    @Test("Summarises the month: start, end, previous month delta, and six trend bars")
    func summary() {
        let series = [
            point(2026, 8, 31, total: 1000),
            point(2026, 9, 15, total: 1200),
            point(2026, 9, 30, total: 1300),
            point(2026, 10, 5, total: 1250),
        ]
        let october = MonthPeriod(year: 2026, month: 10)
        let summary = DashboardNetWorthSummary(series: series, period: october, includes: .all)

        #expect(summary.startNetWorth == 1300)
        #expect(summary.endNetWorth == 1250)
        #expect(summary.currentDelta == -50)
        #expect(summary.previousDelta == 300)
        #expect(summary.bars.count == 6)
        #expect(summary.bars.last?.period == october)
        #expect(summary.bars.last?.isCurrent == true)
        #expect(summary.bars[4].delta == 300)
        #expect(summary.bars[0].delta == nil)

        let growth = summary.growthPercent ?? 0
        #expect(abs(growth - (-50.0 / 1300.0 * 100)) < 0.0001)
    }

    @Test("Without points before the month there is no previous delta")
    func noHistory() {
        let series = [point(2026, 10, 3, total: 500), point(2026, 10, 9, total: 650)]
        let summary = DashboardNetWorthSummary(series: series, period: MonthPeriod(year: 2026, month: 10), includes: .all)
        #expect(summary.previousDelta == nil)
        #expect(summary.startNetWorth == 500)
        #expect(summary.currentDelta == 150)
    }

    @Test("Fetch range starts the day before the earliest trend month")
    func fetchRange() {
        let range = DashboardNetWorthSummary.fetchRange(for: MonthPeriod(year: 2026, month: 3))
        #expect(range.from == CalendarDate(year: 2025, month: 9, day: 30))
        #expect(range.to == CalendarDate(year: 2026, month: 3, day: 31))
    }
}
