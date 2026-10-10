import Foundation

/// The last `MonthlySpendingSnapshot` and the budget alerts already sent, kept in the App
/// Group defaults so the app, its background refresh and the widget see the same values.
public struct BudgetSnapshotStore: @unchecked Sendable {
    /// `UserDefaults` is thread-safe; it is the only stored state.
    private let defaults: UserDefaults

    static let snapshotKey = "monthlySpendingSnapshot"

    public init(defaults: UserDefaults = SharedContainer.defaults) {
        self.defaults = defaults
    }

    // MARK: Snapshot

    public func loadSnapshot() -> MonthlySpendingSnapshot? {
        guard let data = defaults.data(forKey: Self.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(MonthlySpendingSnapshot.self, from: data)
    }

    public func saveSnapshot(_ snapshot: MonthlySpendingSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.snapshotKey)
    }

    /// Call on sign-out so the widget stops showing the previous account's spending.
    public func clearSnapshot() {
        defaults.removeObject(forKey: Self.snapshotKey)
    }

    // MARK: Alert bookkeeping

    static func notifiedKey(for month: BudgetMonth) -> String {
        "notified-\(month.key)"
    }

    /// Thresholds already notified in `month`.
    public func notifiedThresholds(in month: BudgetMonth) -> Set<BudgetThreshold> {
        let raw = defaults.stringArray(forKey: Self.notifiedKey(for: month)) ?? []
        return Set(raw.compactMap(BudgetThreshold.init(rawValue:)))
    }

    /// Records that `threshold` was notified for `month`. Reaching `.over` also marks
    /// `.warning`, so a later dip below 100 % doesn't send the softer alert.
    public func markNotified(_ threshold: BudgetThreshold, in month: BudgetMonth) {
        guard threshold != .none else { return }
        var notified = notifiedThresholds(in: month)
        notified.insert(threshold)
        if threshold == .over { notified.insert(.warning) }
        defaults.set(notified.map(\.rawValue).sorted(), forKey: Self.notifiedKey(for: month))
    }

    /// Forgets the alerts sent in `month`, e.g. after the budget amount changes.
    public func resetNotified(in month: BudgetMonth) {
        defaults.removeObject(forKey: Self.notifiedKey(for: month))
    }

    /// The threshold to notify for `snapshot`, if it reached one not yet notified this month.
    /// Returns the highest reached: going straight past 100 % yields `.over` only.
    public func pendingAlert(for snapshot: MonthlySpendingSnapshot) -> BudgetThreshold? {
        let reached = snapshot.threshold
        guard reached != .none else { return nil }
        return notifiedThresholds(in: snapshot.month).contains(reached) ? nil : reached
    }
}
