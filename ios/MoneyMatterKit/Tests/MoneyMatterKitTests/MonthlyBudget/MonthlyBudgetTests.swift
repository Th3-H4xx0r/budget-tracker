import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Monthly budget")
struct MonthlyBudgetTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private let october = BudgetMonth(year: 2026, month: 10)

    private func snapshot(spent: Decimal, budget: Decimal?) -> MonthlySpendingSnapshot {
        MonthlySpendingSnapshot(
            month: october,
            spent: spent,
            budget: budget,
            dailyCumulative: [spent],
            currencyCode: "USD",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func expense(_ amount: Decimal, day: Int, month: Int = 10, hour: Int = 12) -> Transaction {
        let time = utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        return Transaction(
            id: UUID().uuidString,
            amount: amount,
            time: time,
            transactionType: .expense,
            accountId: "a",
            currencyCode: "USD"
        )
    }

    // MARK: Calculations

    @Test("Under budget: remaining is the difference and overBy is zero")
    func underBudget() {
        let value = snapshot(spent: 988, budget: 1400)
        #expect(value.remaining == 412)
        #expect(value.overBy == 0)
        #expect(value.fraction.map { abs($0 - 988.0 / 1400.0) < 0.0001 } == true)
        #expect(!value.isOverBudget)
    }

    @Test("Over budget: overBy is the excess and remaining is clamped to zero")
    func overBudget() {
        let value = snapshot(spent: 1388, budget: 400)
        #expect(value.overBy == 988)
        #expect(value.remaining == 0)
        #expect(value.isOverBudget)
    }

    @Test("Without a positive budget the derived values are nil")
    func noBudget() {
        for budget in [nil, Decimal(0), Decimal(-5)] {
            let value = snapshot(spent: 100, budget: budget)
            #expect(!value.hasBudget)
            #expect(value.remaining == nil)
            #expect(value.overBy == nil)
            #expect(value.fraction == nil)
            #expect(value.threshold == .none)
        }
    }

    // MARK: Thresholds

    @Test("Threshold boundaries: warning at 80 %, over only above 100 %",
          arguments: [
              (Decimal(0), BudgetThreshold.none),
              (Decimal(string: "79.99")!, .none),
              (Decimal(80), .warning),
              (Decimal(100), .warning),
              (Decimal(string: "100.01")!, .over),
              (Decimal(500), .over),
          ])
    func thresholds(spent: Decimal, expected: BudgetThreshold) {
        #expect(BudgetThreshold.of(spent: spent, budget: 100) == expected)
    }

    @Test("Thresholds order none < warning < over")
    func thresholdOrder() {
        #expect(BudgetThreshold.none < .warning)
        #expect(BudgetThreshold.warning < .over)
    }

    // MARK: Daily cumulative

    @Test("Sums refAmount per day into a running total through the given day")
    func cumulative() {
        let rows = [
            expense(10, day: 1),
            expense(5, day: 1, hour: 23),
            expense(20, day: 3),
            expense(99, day: 9), // after throughDay
            expense(50, day: 2, month: 9), // other month
        ]
        let result = MonthlySpendingSnapshot.dailyCumulative(of: rows, month: october, throughDay: 4, calendar: utc)
        #expect(result == [15, 15, 35, 35])
    }

    @Test("No days elapsed yields an empty series")
    func cumulativeEmpty() {
        #expect(MonthlySpendingSnapshot.dailyCumulative(of: [], month: october, throughDay: 0, calendar: utc).isEmpty)
        #expect(MonthlySpendingSnapshot.dailyCumulative(of: [], month: october, throughDay: 3, calendar: utc) == [0, 0, 0])
    }

    @Test("Month key and day count")
    func month() {
        #expect(october.key == "2026-10")
        #expect(BudgetMonth(year: 2028, month: 2).dayCount(calendar: utc) == 29)
        #expect(BudgetMonth(containing: utc.date(from: DateComponents(year: 2026, month: 10, day: 31))!, calendar: utc) == october)
    }

    // MARK: Settings decoding

    @Test("Settings slice decodes numbers, strings, null and missing keys")
    func settingsDecoding() throws {
        func decode(_ json: String) throws -> MonthlyBudgetSettings {
            try JSONCoding.makeDecoder().decode(MonthlyBudgetUserSettings.self, from: Data(json.utf8)).monthlySpendingBudget
        }
        #expect(try decode(#"{"monthlySpendingBudget":{"amount":1400.5,"alertsEnabled":false}}"#)
            == MonthlyBudgetSettings(amount: Decimal(string: "1400.5"), alertsEnabled: false))
        #expect(try decode(#"{"monthlySpendingBudget":{"amount":"250.00","alertsEnabled":true}}"#).amount == 250)
        #expect(try decode(#"{"monthlySpendingBudget":{"amount":null}}"#) == .notSet)
        #expect(try decode(#"{"otherKey":1}"#) == .notSet)
        #expect(try decode(#"{"monthlySpendingBudget":"garbage"}"#) == .notSet)
    }

    @Test("Patch body always sends amount, as null when cleared")
    func settingsEncoding() throws {
        let body = MonthlyBudgetSettingsPatch(monthlySpendingBudget: .notSet)
        let json = String(decoding: try JSONCoding.makeEncoder().encode(body), as: UTF8.self)
        #expect(json == #"{"monthlySpendingBudget":{"alertsEnabled":true,"amount":null}}"#)
    }

    @Test("Expense query matches the contract")
    func expenseQuery() {
        let from = Date(timeIntervalSince1970: 1_790_812_800) // 2026-10-01T00:00:00Z
        let items = MonthlySpendingLoader.expenseQuery(from: from, to: from.addingTimeInterval(3600), offset: 0).queryItems
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(dict["from"] == "2026-10-01T00:00:00.000Z")
        #expect(dict["transactionType"] == "expense")
        #expect(dict["isPlanned"] == "false")
        #expect(dict["excludeTransfer"] == "true")
        #expect(dict["excludeBalanceAdjustments"] == "true")
        #expect(dict["limit"] == "500")
        #expect(dict["offset"] == nil)
    }

    // MARK: Store

    @Test("Store round-trips the snapshot and tracks notified thresholds per month")
    func store() throws {
        let suite = "MonthlyBudgetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BudgetSnapshotStore(defaults: defaults)

        let warning = snapshot(spent: 90, budget: 100)
        store.saveSnapshot(warning)
        #expect(store.loadSnapshot() == warning)

        #expect(store.pendingAlert(for: warning) == .warning)
        store.markNotified(.warning, in: october)
        #expect(store.pendingAlert(for: warning) == nil)
        #expect(defaults.stringArray(forKey: "notified-2026-10") == ["warning"])

        let over = snapshot(spent: 120, budget: 100)
        #expect(store.pendingAlert(for: over) == .over)
        store.markNotified(.over, in: october)
        #expect(store.pendingAlert(for: over) == nil)
        #expect(store.pendingAlert(for: warning) == nil)

        #expect(store.notifiedThresholds(in: BudgetMonth(year: 2026, month: 11)).isEmpty)
        store.resetNotified(in: october)
        #expect(store.pendingAlert(for: over) == .over)

        store.clearSnapshot()
        #expect(store.loadSnapshot() == nil)
    }

    @Test("Marking over also marks warning")
    func overImpliesWarning() throws {
        let suite = "MonthlyBudgetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BudgetSnapshotStore(defaults: defaults)
        store.markNotified(.over, in: october)
        #expect(store.notifiedThresholds(in: october) == [.warning, .over])
    }

    // MARK: Freshness

    @Test("Freshness buckets", arguments: [
        (TimeInterval(20), BudgetFreshness.justNow),
        (TimeInterval(5 * 60), .minutes(5)),
        (TimeInterval(3 * 3600), .hours(3)),
        (TimeInterval(13 * 3600), .overHalfADay),
        (TimeInterval(30 * 3600), .overADay),
        (TimeInterval(80 * 3600), .days(3)),
    ])
    func freshness(age: TimeInterval, expected: BudgetFreshness) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(BudgetFreshness(since: now.addingTimeInterval(-age), now: now) == expected)
    }
}
