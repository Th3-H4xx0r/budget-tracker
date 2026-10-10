import Foundation
import MoneyMatterKit
import WidgetKit

nonisolated struct MonthlyBudgetEntry: TimelineEntry {
    let date: Date
    /// `nil` before the app has signed in and produced a snapshot for this month.
    let snapshot: MonthlySpendingSnapshot?
}

/// Loads this month's spending with the token and server the app shares through the
/// Keychain access group and App Group, falling back to the last saved snapshot when
/// offline or signed out.
nonisolated struct MonthlyBudgetProvider: TimelineProvider {
    static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> MonthlyBudgetEntry {
        MonthlyBudgetEntry(date: .now, snapshot: .sampleOver)
    }

    func getSnapshot(in context: Context, completion: @escaping (MonthlyBudgetEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        completion(MonthlyBudgetEntry(date: .now, snapshot: Self.cachedSnapshot(now: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthlyBudgetEntry>) -> Void) {
        let reply = CompletionBox(completion)
        Task {
            let now = Date.now
            let snapshot = await Self.loadSnapshot(now: now)
            reply.call(Self.timeline(for: snapshot, now: now))
        }
    }

    /// One entry per hour for the next few hours keeps the "updated … ago" footer honest if
    /// the system delays the next reload; the reload itself is requested after 30 minutes.
    static func timeline(for snapshot: MonthlySpendingSnapshot?, now: Date) -> Timeline<MonthlyBudgetEntry> {
        let entries = (0...6).map { hour in
            MonthlyBudgetEntry(date: now.addingTimeInterval(TimeInterval(hour) * 3600), snapshot: snapshot)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(refreshInterval)))
    }

    static func loadSnapshot(now: Date) async -> MonthlySpendingSnapshot? {
        let store = BudgetSnapshotStore()
        if let server = SharedContainer.server() {
            let tokenReader = SharedKeychainTokenReader(server: server)
            if tokenReader.accessToken() != nil {
                let client = APIClient(server: server, tokenProvider: tokenReader)
                if let fresh = try? await MonthlySpendingLoader(client: client).load(now: now) {
                    store.saveSnapshot(fresh)
                    return fresh
                }
            }
        }
        return cachedSnapshot(now: now)
    }

    /// The saved snapshot, but only for the current month: last month's total would read as
    /// this month's.
    static func cachedSnapshot(now: Date) -> MonthlySpendingSnapshot? {
        guard let cached = BudgetSnapshotStore().loadSnapshot(),
              cached.month == BudgetMonth(containing: now)
        else { return nil }
        return cached
    }
}

/// WidgetKit's completion handlers aren't annotated `@Sendable` but may be called from any
/// thread; this carries one into the loading task.
nonisolated private struct CompletionBox<Value>: @unchecked Sendable {
    let call: (Value) -> Void

    init(_ call: @escaping (Value) -> Void) {
        self.call = call
    }
}

// MARK: - Samples

nonisolated extension MonthlySpendingSnapshot {
    private static func sample(spent: Decimal, budget: Decimal?, days: Int) -> MonthlySpendingSnapshot {
        let now = Date.now
        let weights: [Decimal] = [3, 1, 0, 2, 5, 1, 1, 4, 2, 0, 3, 2, 1, 6, 2]
        let used = Array(weights.prefix(days))
        let total = used.reduce(0, +)
        var running: Decimal = 0
        let cumulative = used.map { weight -> Decimal in
            running += spent * weight / total
            return running
        }
        return MonthlySpendingSnapshot(
            month: BudgetMonth(containing: now),
            spent: spent,
            budget: budget,
            dailyCumulative: cumulative,
            currencyCode: "USD",
            updatedAt: now.addingTimeInterval(-13 * 3600)
        )
    }

    static let sampleOver = sample(spent: 1388, budget: 400, days: 9)
    static let sampleUnder = sample(spent: 988, budget: 1400, days: 15)
    static let sampleNoBudget = sample(spent: 642, budget: nil, days: 9)
}
