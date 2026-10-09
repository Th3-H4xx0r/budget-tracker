import Foundation
import MoneyMatterKit
import Observation

/// One month on the cash flow widget's trend.
struct HomeCashFlowMonth: Identifiable, Equatable {
    let period: MonthPeriod
    let totals: CashFlowTotals

    var id: MonthPeriod { period }
}

/// The cash flow widget's numbers: the selected month, the one before, and the six-month trend.
struct HomeCashFlowSnapshot: Equatable {
    let current: CashFlowTotals
    let previous: CashFlowTotals?
    /// Oldest first, ending with the selected month.
    let months: [HomeCashFlowMonth]

    /// Sums the monthly buckets that start inside each month, with the endpoint's own
    /// savings-rate math (`round(netFlow / income * 100)`).
    init(report: CashFlowReport, period: MonthPeriod, monthCount: Int) {
        func totals(for month: MonthPeriod) -> CashFlowTotals? {
            let buckets = report.periods.filter { $0.periodStart >= month.firstDay && $0.periodStart <= month.lastDay() }
            guard !buckets.isEmpty else { return nil }
            let income = buckets.reduce(Decimal.zero) { $0 + $1.income }
            let expenses = buckets.reduce(Decimal.zero) { $0 + $1.expenses }
            let net = income - expenses
            var rate = Decimal.zero
            if income > 0 {
                var raw = net / income * 100
                NSDecimalRound(&rate, &raw, 0, .plain)
            }
            return CashFlowTotals(income: income, expenses: expenses, netFlow: net, savingsRate: rate)
        }

        var periods: [MonthPeriod] = [period]
        for _ in 1..<max(monthCount, 1) { periods.insert(periods[0].previous, at: 0) }
        current = totals(for: period) ?? .zero
        previous = totals(for: period.previous)
        months = periods.map { HomeCashFlowMonth(period: $0, totals: totals(for: $0) ?? .zero) }
    }
}

/// The planned overview widget's data: per-account summary plus the nearest pending plans.
struct HomePlannedOverview: Equatable {
    let entries: [DashboardPlannedSummaryEntry]
    /// Ascending by time, so plans whose match window has run out lead.
    let plans: [Transaction]
}

/// Home's widget layout (persisted to `dashboard.widgets` in user settings) and the data of the
/// widgets that `HomeViewModel` doesn't cover. Each widget loads and fails on its own.
@Observable
final class HomeDashboardModel {
    static let trendMonthCount = 6
    static let nearestPlansLimit = 4
    private static let cacheKey = "home.dashboardLayout"

    private(set) var settings: LoadState<DashboardUserSettings> = .idle
    private(set) var cashFlow: LoadState<HomeCashFlowSnapshot> = .idle
    private(set) var netWorth: LoadState<[BalancePoint]> = .idle
    private(set) var tracker: LoadState<[CategorySpendingByType]> = .idle
    private(set) var planned: LoadState<HomePlannedOverview> = .idle
    /// The layout last loaded from the server, shown while settings load again.
    private var cachedLayout: [DashboardWidgetConfig]?

    @ObservationIgnored private let client: APIClient?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var generations: [AnyKeyPath: Int] = [:]

    init(client: APIClient?, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.cacheKey) {
            cachedLayout = try? JSONDecoder().decode([DashboardWidgetConfig].self, from: data)
        }
    }

    /// The widgets to show, in order. Before settings load, the last known layout keeps the
    /// placeholders accurate; with nothing saved, the default layout.
    var widgets: [DashboardWidgetConfig] {
        if let loaded = settings.value {
            return DashboardLayout.resolve(saved: loaded.widgets)
        }
        return DashboardLayout.resolve(saved: cachedLayout)
    }

    var includeCreditLimitInStats: Bool { settings.value?.includeCreditLimitInStats ?? false }

    func widget(_ kind: DashboardWidgetKind) -> DashboardWidgetConfig? {
        widgets.first { $0.kind == kind }
    }

    func isShown(_ kind: DashboardWidgetKind) -> Bool { widget(kind) != nil }

    // MARK: Loading

    func loadSettings() async {
        await load(into: \.settings) { [client] in
            guard let client else { throw APIError(URLError(.notConnectedToInternet)) }
            return try await client.send(Endpoints.dashboardSettings())
        }
        if let widgets = settings.value?.widgets { cache(widgets) }
    }

    /// Loads the data of every shown widget this model owns; hidden widgets are skipped.
    func loadWidgets(period: MonthPeriod) async {
        async let cashFlowLoad: Void = loadCashFlow(period: period)
        async let netWorthLoad: Void = loadNetWorth(period: period)
        async let trackerLoad: Void = loadTracker(period: period)
        async let plannedLoad: Void = loadPlanned()
        _ = await (cashFlowLoad, netWorthLoad, trackerLoad, plannedLoad)
    }

    func loadCashFlow(period: MonthPeriod) async {
        guard isShown(.cashFlow) else { return }
        let includePlanned = widget(.cashFlow)?.includePlanned ?? true
        var first = period
        for _ in 1..<Self.trendMonthCount { first = first.previous }
        let from = first.firstDay
        await load(into: \.cashFlow) { [client] in
            guard let client else { throw APIError(URLError(.notConnectedToInternet)) }
            let report = try await client.send(Endpoints.cashFlow(
                from: from,
                to: period.lastDay(),
                granularity: .monthly,
                excludePlanned: !includePlanned
            ))
            return HomeCashFlowSnapshot(report: report, period: period, monthCount: Self.trendMonthCount)
        }
    }

    func loadNetWorth(period: MonthPeriod) async {
        guard isShown(.netWorth) else { return }
        let range = DashboardNetWorthSummary.fetchRange(for: period)
        await load(into: \.netWorth) { [client] in
            guard let client else { throw APIError(URLError(.notConnectedToInternet)) }
            // One day past the end: the API reports the last requested day as 0.
            let points = try await client.send(Endpoints.combinedBalanceHistory(from: range.from, to: range.to.adding(days: 1)))
            return points.filter { $0.date <= range.to }
        }
    }

    func loadTracker(period: MonthPeriod) async {
        guard isShown(.categorySpendingTracker) else { return }
        let config = widget(.categorySpendingTracker)
        let ids = config?.selectedCategoryIds ?? []
        let includePlanned = config?.includePlanned ?? true
        guard !ids.isEmpty else {
            tracker = .loaded([])
            return
        }
        await load(into: \.tracker) { [client] in
            guard let client else { throw APIError(URLError(.notConnectedToInternet)) }
            return try await client.send(Endpoints.spendingsByCategoriesByType(
                from: period.firstDay,
                to: period.lastDay(),
                categoryIds: ids,
                excludePlanned: !includePlanned
            ))
        }
    }

    func loadPlanned() async {
        guard isShown(.plannedOverview) else { return }
        await load(into: \.planned) { [client] in
            guard let client else { throw APIError(URLError(.notConnectedToInternet)) }
            var query = TransactionListQuery(limit: 20, offset: 0)
            query.isPlanned = true
            query.sortBy = .time
            query.order = .ascending
            query.includeTags = true
            query.includeSplits = true
            async let entries = client.send(Endpoints.dashboardPlannedSummary())
            async let plans = client.send(Endpoints.transactions(query))
            return try await HomePlannedOverview(
                entries: entries,
                plans: Array(plans.sorted { $0.time < $1.time }.prefix(Self.nearestPlansLimit))
            )
        }
    }

    // MARK: Saving

    /// Saves the full widget list. Throws so the caller can show the error alert.
    func saveLayout(_ widgets: [DashboardWidgetConfig]) async throws {
        guard let client else { throw APIError(URLError(.notConnectedToInternet)) }
        let saved = try await client.send(Endpoints.saveDashboardWidgets(widgets))
        apply(saved, fallbackWidgets: widgets)
    }

    /// Merges `values` into one widget's config and saves the layout.
    func saveConfig(for kind: DashboardWidgetKind, values: [String: DashboardConfigValue]) async throws {
        let updated = widgets.map { $0.kind == kind ? $0.mergingConfig(values) : $0 }
        try await saveLayout(updated)
    }

    private func apply(_ saved: DashboardUserSettings, fallbackWidgets: [DashboardWidgetConfig]) {
        let widgets = saved.widgets ?? fallbackWidgets
        settings = .loaded(DashboardUserSettings(widgets: widgets, includeCreditLimitInStats: saved.includeCreditLimitInStats))
        cache(widgets)
    }

    private func cache(_ widgets: [DashboardWidgetConfig]) {
        cachedLayout = widgets
        if let data = try? JSONEncoder().encode(widgets) {
            defaults.set(data, forKey: Self.cacheKey)
        }
    }

    /// Runs `fetch` into one widget's state. A failed refresh of loaded content keeps it;
    /// results from a load that a newer one superseded are dropped.
    private func load<Value>(
        into keyPath: ReferenceWritableKeyPath<HomeDashboardModel, LoadState<Value>>,
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
            if self[keyPath: keyPath].value == nil {
                self[keyPath: keyPath] = .failed(APIError(error))
            }
        }
    }
}
