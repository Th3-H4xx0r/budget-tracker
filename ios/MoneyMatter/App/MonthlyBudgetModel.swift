import Foundation
import MoneyMatterKit
import Observation

/// This month's spending against the monthly budget for Home and the budget settings
/// screen. Starts from the App Group snapshot so Home draws at once, then each `refresh`
/// reloads it, updates the widget, and posts any due alert. Created per signed-in session.
@Observable
final class MonthlyBudgetModel {
    private(set) var snapshot: MonthlySpendingSnapshot?
    /// True once a snapshot is known, cached or fresh, so Home doesn't offer "Set a monthly
    /// budget" before it knows whether one is set.
    private(set) var hasLoaded: Bool

    @ObservationIgnored private let store: BudgetSnapshotStore
    /// Only the latest refresh may write `snapshot`.
    @ObservationIgnored private var generation = 0

    init(store: BudgetSnapshotStore = BudgetSnapshotStore(), now: Date = .now) {
        self.store = store
        // Last month's total would read as this month's.
        let cached = store.loadSnapshot().flatMap { $0.month == BudgetMonth(containing: now) ? $0 : nil }
        snapshot = cached
        hasLoaded = cached != nil
    }

    func refresh(client: APIClient?) async {
        guard let client else { return }
        generation += 1
        let current = generation
        let fresh = await MonthlyBudgetAlerts.refreshAndCheck(client: client)
        guard current == generation, let fresh else { return }
        snapshot = fresh
        hasLoaded = true
    }

    /// After saving the budget settings: a new amount re-arms this month's alerts, then the
    /// snapshot, widget, and alerts are refreshed against it.
    func settingsDidChange(to settings: MonthlyBudgetSettings, from previous: MonthlyBudgetSettings?, client: APIClient?) async {
        MonthlyBudgetAlerts.alertsEnabled = settings.alertsEnabled
        if settings.effectiveAmount != previous?.effectiveAmount {
            store.resetNotified(in: BudgetMonth(containing: .now))
        }
        await refresh(client: client)
    }
}
