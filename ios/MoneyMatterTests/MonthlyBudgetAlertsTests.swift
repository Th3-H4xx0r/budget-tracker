import Foundation
import MoneyMatterKit
import Testing
@testable import MoneyMatter

@Suite("MonthlyBudgetAlerts")
struct MonthlyBudgetAlertsTests {
    private static let locale = Locale(identifier: "en_US")
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 19 October 2026: 12 days left in the month.
    private static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))!

    private func snapshot(spent: Decimal, budget: Decimal?) -> MonthlySpendingSnapshot {
        MonthlySpendingSnapshot(
            month: BudgetMonth(year: 2026, month: 10),
            spent: spent,
            budget: budget,
            dailyCumulative: [],
            currencyCode: "USD",
            updatedAt: Self.now
        )
    }

    private func freshStore() -> BudgetSnapshotStore {
        BudgetSnapshotStore(defaults: UserDefaults(suiteName: "MonthlyBudgetAlertsTests-\(UUID().uuidString)")!)
    }

    @Test("Over budget names the spend, the overage, and the budget")
    func overMessage() {
        let message = MonthlyBudgetAlertMessage.make(
            for: .over,
            snapshot: snapshot(spent: 1388, budget: 400),
            now: Self.now,
            calendar: Self.calendar,
            locale: Self.locale
        )
        #expect(message?.title == "Over budget")
        #expect(message?.body == "You've spent $1,388 this month, $988 over your $400 budget.")
    }

    @Test("The warning names the share used, what's left, and the days to go")
    func warningMessage() {
        let message = MonthlyBudgetAlertMessage.make(
            for: .warning,
            snapshot: snapshot(spent: 320, budget: 400),
            now: Self.now,
            calendar: Self.calendar,
            locale: Self.locale
        )
        #expect(message?.body == "80% of your monthly budget used — $80 left with 12 days to go.")
    }

    @Test("No message without a budget")
    func noBudgetMessage() {
        #expect(MonthlyBudgetAlertMessage.make(for: .over, snapshot: snapshot(spent: 10, budget: nil)) == nil)
    }

    @Test("Cents show only when the amount has them")
    func moneyFormatting() {
        #expect(MonthlyBudgetFormat.money(1388, currencyCode: "USD", locale: Self.locale) == "$1,388")
        #expect(MonthlyBudgetFormat.money(Decimal(string: "12.5")!, currencyCode: "USD", locale: Self.locale) == "$12.50")
    }

    @Test("Alerts once per threshold, only when enabled with a budget")
    func decision() {
        let store = freshStore()
        let over = snapshot(spent: 1388, budget: 400)

        #expect(MonthlyBudgetAlerts.alertToSend(for: over, alertsEnabled: false, store: store) == nil)
        #expect(MonthlyBudgetAlerts.alertToSend(for: snapshot(spent: 1388, budget: nil), alertsEnabled: true, store: store) == nil)
        #expect(MonthlyBudgetAlerts.alertToSend(for: snapshot(spent: 100, budget: 400), alertsEnabled: true, store: store) == nil)
        #expect(MonthlyBudgetAlerts.alertToSend(for: snapshot(spent: 320, budget: 400), alertsEnabled: true, store: store) == .warning)
        #expect(MonthlyBudgetAlerts.alertToSend(for: over, alertsEnabled: true, store: store) == .over)

        store.markNotified(.over, in: over.month)
        #expect(MonthlyBudgetAlerts.alertToSend(for: over, alertsEnabled: true, store: store) == nil)
        #expect(MonthlyBudgetAlerts.alertToSend(for: snapshot(spent: 320, budget: 400), alertsEnabled: true, store: store) == nil)
    }

    @Test("Deep links parse home and the budget settings")
    func deepLinks() {
        #expect(AppDeepLink(url: SharedContainer.homeURL) == .home)
        #expect(AppDeepLink(url: SharedContainer.setBudgetURL) == .monthlyBudgetSettings)
        #expect(AppDeepLink(url: URL(string: "https://example.com/home")!) == nil)
    }
}
