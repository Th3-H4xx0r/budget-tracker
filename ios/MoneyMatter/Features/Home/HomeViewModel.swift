import Foundation
import MoneyMatterKit
import Observation

/// Spending in the selected period and in the matching earlier one, as positive amounts.
struct SpendingTotals: Equatable {
    let current: Decimal
    let previous: Decimal

    /// Positive when more was spent than in the earlier period.
    var change: Decimal { current - previous }
}

/// One bar of the spending chart: a week or a month of expenses.
struct SpendingBucket: Identifiable, Equatable {
    let start: CalendarDate
    let amount: Decimal

    var id: String { start.description }
}

struct SpendingBreakdown: Equatable {
    /// Largest first.
    let categories: [CategorySpending]

    var total: Decimal { categories.reduce(Decimal.zero) { $0 + $1.amount } }

    var topCategories: [CategorySpending] { Array(categories.prefix(5)) }

    /// Everything past the top five, for the donut's "Other" slice.
    var otherAmount: Decimal {
        categories.dropFirst(5).reduce(Decimal.zero) { $0 + $1.amount }
    }
}

/// Home's cards. The spending cards follow the selected period; each card loads and fails on
/// its own, so one slow or broken endpoint never blanks the whole screen.
@Observable
final class HomeViewModel {
    static let transactionLimit = 20

    private(set) var period: HomePeriod = .currentMonth()
    private(set) var reviewSummary: LoadState<ReviewSummary> = .idle
    private(set) var totals: LoadState<SpendingTotals> = .idle
    private(set) var buckets: LoadState<[SpendingBucket]> = .idle
    private(set) var spending: LoadState<SpendingBreakdown> = .idle
    private(set) var periodTransactions: LoadState<[Transaction]> = .idle
    private(set) var upcoming: LoadState<[SubscriptionListItem]> = .idle

    @ObservationIgnored private let stats: any StatsServicing
    @ObservationIgnored private let transactions: any TransactionsServicing
    @ObservationIgnored private let subscriptions: any SubscriptionsServicing
    @ObservationIgnored private let review: any ReviewServicing
    @ObservationIgnored private let client: APIClient?
    /// Bumped per card on every load; only the latest load may write the card, so a slow
    /// older response (period A, then B, then A again, or overlapping refreshes) can't win.
    @ObservationIgnored private var generations: [AnyKeyPath: Int] = [:]

    init(
        stats: any StatsServicing,
        transactions: any TransactionsServicing,
        subscriptions: any SubscriptionsServicing,
        review: any ReviewServicing,
        client: APIClient?
    ) {
        self.stats = stats
        self.transactions = transactions
        self.subscriptions = subscriptions
        self.review = review
        self.client = client
    }

    convenience init(services: AppServices) {
        self.init(
            stats: services.stats,
            transactions: services.transactions,
            subscriptions: services.subscriptions,
            review: services.review,
            client: services.client
        )
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard case .idle = reviewSummary else { return }
        await refresh()
    }

    /// Reloads every card in parallel. Loaded cards keep their content while refreshing.
    func refresh() async {
        async let summaryLoad: Void = loadReviewSummary()
        async let periodLoad: Void = loadPeriodCards()
        async let upcomingLoad: Void = loadUpcoming()
        _ = await (summaryLoad, periodLoad, upcomingLoad)
    }

    /// Switches every period-bound card to `newPeriod`, showing placeholders until it loads.
    func setPeriod(_ newPeriod: HomePeriod) async {
        guard newPeriod != period else { return }
        period = newPeriod
        totals = .loading
        buckets = .loading
        spending = .loading
        periodTransactions = .loading
        await loadPeriodCards()
    }

    func loadPeriodCards() async {
        async let totalsLoad: Void = loadTotals()
        async let bucketsLoad: Void = loadBuckets()
        async let spendingLoad: Void = loadSpending()
        async let transactionsLoad: Void = loadTransactions()
        _ = await (totalsLoad, bucketsLoad, spendingLoad, transactionsLoad)
    }

    func loadReviewSummary() async {
        await load(into: \.reviewSummary) { [review] in
            try await review.reviewSummary()
        }
    }

    /// The period's spending and the earlier period's, for the hero and its change line.
    func loadTotals() async {
        let today = CalendarDate(date: .now)
        let range = period.range(today: today)
        let previous = period.previousRange(today: today)
        await load(into: \.totals) { [stats] in
            async let current = stats.expensesTotal(from: range.from, to: range.to)
            async let earlier = stats.expensesTotal(from: previous.from, to: previous.to)
            return try await SpendingTotals(current: abs(current), previous: abs(earlier))
        }
    }

    func loadBuckets() async {
        let range = period.range(today: CalendarDate(date: .now))
        let granularity = period.granularity
        await load(into: \.buckets) { [client] in
            guard let client else { throw APIError(URLError(.notConnectedToInternet)) }
            let report = try await client.send(Endpoints.cashFlow(from: range.from, to: range.to, granularity: granularity))
            return report.periods.map { SpendingBucket(start: $0.periodStart, amount: abs($0.expenses)) }
        }
    }

    func loadSpending() async {
        let range = period.range(today: CalendarDate(date: .now))
        await load(into: \.spending) { [stats] in
            try await SpendingBreakdown(categories: stats.spendingByCategory(from: range.from, to: range.to))
        }
    }

    /// The latest rows in the period, up to now.
    func loadTransactions() async {
        let range = period.range(today: CalendarDate(date: .now))
        var query = TransactionListQuery(limit: Self.transactionLimit)
        query.from = range.from.startDate()
        query.to = min(range.to.adding(days: 1).startDate().addingTimeInterval(-1), .now)
        query.includeTags = true
        query.excludeBalanceAdjustments = true
        await load(into: \.periodTransactions) { [transactions] in
            try await transactions.transactions(query)
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
