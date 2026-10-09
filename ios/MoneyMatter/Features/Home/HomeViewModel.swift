import Foundation
import MoneyMatterKit
import Observation

/// The balance trend for one month, plus the closing balance of the month before it.
struct BalanceTrend: Equatable {
    let points: [BalancePoint]
    /// The last balance before the period started, when the server had one.
    let previousTotal: Decimal?

    var currentTotal: Decimal? { points.last?.totalBalance }

    /// The change versus the previous period's close, else versus the period's first day.
    var change: Decimal? {
        guard let currentTotal, let baseline = previousTotal ?? points.first?.totalBalance else { return nil }
        return currentTotal - baseline
    }
}

/// The hero chart's range on Home.
enum HomeBalanceRange: String, CaseIterable, Identifiable, Hashable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "All"

    var id: Self { self }

    /// The segmented picker's label.
    var label: String {
        switch self {
        case .all: String(localized: "All")
        default: rawValue
        }
    }

    /// The first day of the range ending `today`. "All" reaches back ten years; leading
    /// empty days are trimmed after loading.
    func firstDay(today: CalendarDate) -> CalendarDate {
        let days = switch self {
        case .oneMonth: 30
        case .threeMonths: 91
        case .sixMonths: 182
        case .oneYear: 365
        case .all: 3_650
        }
        return today.adding(days: -days)
    }
}

struct SpendingBreakdown: Equatable {
    let total: Decimal
    /// Largest first.
    let categories: [CategorySpending]

    var topCategories: [CategorySpending] { Array(categories.prefix(5)) }

    /// Everything past the top five, for the donut's "Other" slice.
    var otherAmount: Decimal {
        categories.dropFirst(5).reduce(Decimal.zero) { $0 + $1.amount }
    }
}

/// Home's cards. Each card loads and fails on its own, so one slow or broken endpoint never
/// blanks the whole screen.
@Observable
final class HomeViewModel {
    static let latestCount = 5

    private(set) var period = MonthPeriod(containing: .now)
    private(set) var balanceRange: HomeBalanceRange = .oneMonth
    /// When the balance hero last loaded, for its "Updated" line.
    private(set) var balanceUpdatedAt: Date?
    private(set) var reviewSummary: LoadState<ReviewSummary> = .idle
    private(set) var balance: LoadState<BalanceTrend> = .idle
    private(set) var spending: LoadState<SpendingBreakdown> = .idle
    private(set) var latest: LoadState<[Transaction]> = .idle
    private(set) var upcoming: LoadState<[SubscriptionListItem]> = .idle

    @ObservationIgnored private let stats: any StatsServicing
    @ObservationIgnored private let transactions: any TransactionsServicing
    @ObservationIgnored private let subscriptions: any SubscriptionsServicing
    @ObservationIgnored private let review: any ReviewServicing
    /// Bumped per card on every load; only the latest load may write the card, so a slow
    /// older response (period A, then B, then A again, or overlapping refreshes) can't win.
    @ObservationIgnored private var generations: [AnyKeyPath: Int] = [:]

    init(
        stats: any StatsServicing,
        transactions: any TransactionsServicing,
        subscriptions: any SubscriptionsServicing,
        review: any ReviewServicing
    ) {
        self.stats = stats
        self.transactions = transactions
        self.subscriptions = subscriptions
        self.review = review
    }

    convenience init(services: AppServices) {
        self.init(
            stats: services.stats,
            transactions: services.transactions,
            subscriptions: services.subscriptions,
            review: services.review
        )
    }

    var canGoToNextPeriod: Bool { period < MonthPeriod(containing: .now) }

    // MARK: Loading

    func loadIfNeeded() async {
        guard case .idle = reviewSummary else { return }
        await refresh()
    }

    /// Reloads every card in parallel. Loaded cards keep their content while refreshing.
    func refresh() async {
        async let summaryLoad: Void = loadReviewSummary()
        async let balanceLoad: Void = loadBalance()
        async let spendingLoad: Void = loadSpending()
        async let latestLoad: Void = loadLatest()
        async let upcomingLoad: Void = loadUpcoming()
        _ = await (summaryLoad, balanceLoad, spendingLoad, latestLoad, upcomingLoad)
    }

    func showPreviousPeriod() async {
        await setPeriod(period.previous)
    }

    func showNextPeriod() async {
        guard canGoToNextPeriod else { return }
        await setPeriod(period.next)
    }

    private func setPeriod(_ newPeriod: MonthPeriod) async {
        period = newPeriod
        spending = .loading
        await loadSpending()
    }

    func setBalanceRange(_ range: HomeBalanceRange) async {
        guard range != balanceRange else { return }
        balanceRange = range
        balance = .loading
        await loadBalance()
    }

    func loadReviewSummary() async {
        await load(into: \.reviewSummary) { [review] in
            try await review.reviewSummary()
        }
    }

    func loadBalance() async {
        let today = CalendarDate(date: .now)
        let range = balanceRange
        let from = range.firstDay(today: today)
        await load(into: \.balance) { [stats] in
            // One extra day in front, for the closing balance before the range. One extra day at
            // the end too: the API reports the last requested day as 0, so that point is dropped.
            let points = try await stats.balanceHistory(from: from.adding(days: -1), to: today.adding(days: 1))
                .sorted { $0.date < $1.date }
            let previous = points.last { $0.date < from }
            var inRange = points.filter { $0.date >= from && $0.date <= today }
            if range == .all, let firstValue = inRange.firstIndex(where: { $0.totalBalance != 0 }) {
                inRange.removeFirst(firstValue)
            }
            return BalanceTrend(
                points: Self.downsampled(inRange, limit: 400),
                previousTotal: range == .all ? nil : previous?.totalBalance
            )
        }
        if balance.value != nil { balanceUpdatedAt = .now }
    }

    /// At most `limit` points, evenly strided, always keeping the latest.
    private static func downsampled(_ points: [BalancePoint], limit: Int) -> [BalancePoint] {
        guard points.count > limit, let last = points.last else { return points }
        let stride = Int((Double(points.count) / Double(limit)).rounded(.up))
        var result = Swift.stride(from: 0, to: points.count - 1, by: stride).map { points[$0] }
        result.append(last)
        return result
    }

    func loadSpending() async {
        let range = dateRange(for: period)
        await load(into: \.spending) { [stats] in
            async let categories = stats.spendingByCategory(from: range.from, to: range.to)
            async let total = stats.expensesTotal(from: range.from, to: range.to)
            return try await SpendingBreakdown(total: total, categories: categories)
        }
    }

    func loadLatest() async {
        await load(into: \.latest) { [transactions] in
            let now = Date.now
            let rows = try await transactions.transactions(.latestRecords(now: now))
            return Array(rows.filter { $0.time <= now }.prefix(Self.latestCount))
        }
    }

    /// Overdue or due within three days, overdue first, then by due date.
    func loadUpcoming() async {
        await load(into: \.upcoming) { [subscriptions] in
            let today = CalendarDate(date: .now)
            return try await subscriptions.activeSubscriptions()
                .filter { $0.needsAttention(today: today) }
                .sorted { lhs, rhs in
                    if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue }
                    let lhsDue = lhs.currentPeriod?.dueDate ?? lhs.nextDueDate
                    let rhsDue = rhs.currentPeriod?.dueDate ?? rhs.nextDueDate
                    switch (lhsDue, rhsDue) {
                    case let (lhs?, rhs?): return lhs < rhs
                    case (.some, nil): return true
                    default: return lhs.name < rhs.name
                    }
                }
        }
    }

    // MARK: Private

    /// The period's days, capped at today for the current month.
    private func dateRange(for period: MonthPeriod) -> (from: CalendarDate, to: CalendarDate) {
        let today = CalendarDate(date: .now)
        return (period.firstDay, min(period.lastDay(), today))
    }

    /// Runs `fetch` into one card's state. A failed refresh of a loaded card keeps the
    /// content. Results from a load that a newer one superseded are dropped.
    private func load<Value>(
        into keyPath: ReferenceWritableKeyPath<HomeViewModel, LoadState<Value>>,
        fetch: () async throws -> Value
    ) async {
        let generation = (generations[keyPath] ?? 0) + 1
        generations[keyPath] = generation
        if self[keyPath: keyPath].value == nil {
            self[keyPath: keyPath] = .loading
        }
        do {
            let value = try await fetch()
            guard generations[keyPath] == generation else { return }
            self[keyPath: keyPath] = .loaded(value)
        } catch {
            guard generations[keyPath] == generation else { return }
            // A cancelled first load also lands here, so the card offers Retry instead of
            // staying a placeholder.
            if self[keyPath: keyPath].value == nil {
                self[keyPath: keyPath] = .failed(APIError(error))
            }
        }
    }
}
