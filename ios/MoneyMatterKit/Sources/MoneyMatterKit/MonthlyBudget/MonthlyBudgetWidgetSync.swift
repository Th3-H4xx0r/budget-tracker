import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Keeps the widget's shared snapshot current. The app calls `refresh(client:)` after
/// launch, after edits that change spending, after the budget changes, and from the
/// background refresh task.
public enum MonthlyBudgetWidgetSync {
    /// Loads a fresh snapshot, saves it to the App Group and reloads the widget timelines.
    /// Check `store.pendingAlert(for:)` on the result to decide whether to notify.
    @discardableResult
    public static func refresh(
        client: APIClient,
        store: BudgetSnapshotStore = BudgetSnapshotStore(),
        now: Date = .now
    ) async throws -> MonthlySpendingSnapshot {
        let snapshot = try await MonthlySpendingLoader(client: client).load(now: now)
        save(snapshot, store: store)
        return snapshot
    }

    /// Saves `snapshot` for the widget and reloads its timelines.
    public static func save(_ snapshot: MonthlySpendingSnapshot, store: BudgetSnapshotStore = BudgetSnapshotStore()) {
        store.saveSnapshot(snapshot)
        reloadWidgets()
    }

    /// Clears the shared snapshot (e.g. on sign-out) and reloads the widget timelines.
    public static func clear(store: BudgetSnapshotStore = BudgetSnapshotStore()) {
        store.clearSnapshot()
        reloadWidgets()
    }

    public static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
