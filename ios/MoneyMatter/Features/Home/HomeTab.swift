import MoneyMatterKit
import SwiftUI

/// Root of the Home tab: the review card, balance trend, spending by category, latest
/// transactions, and upcoming payments, in one scrolling column.
struct HomeTab: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.homePath) {
            HomeScreen(model: HomeViewModel(services: services), dashboard: HomeDashboardModel(client: services.client))
                .navigationTitle("Home")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Notifications", systemImage: "bell") {
                            router.homePath.append(.notifications)
                        }
                        .notificationsUnreadBadge()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ProfileButton()
                    }
                }
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .transaction(let id):
                        TransactionDetailScreen(transactionID: id)
                    case .account(let id):
                        AccountDetailScreen(accountID: id)
                    case .reviewPage(let status):
                        ReviewPageScreen(initialStatus: status)
                    case .notifications:
                        NotificationsScreen()
                    }
                }
        }
    }
}

private struct HomeScreen: View {
    @State private var model: HomeViewModel
    @State private var dashboard: HomeDashboardModel
    @State private var isEditing = false
    @State private var alert: ErrorAlert?
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ReferenceDataStore.self) private var referenceData

    init(model: HomeViewModel, dashboard: HomeDashboardModel) {
        _model = State(initialValue: model)
        _dashboard = State(initialValue: dashboard)
    }

    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }
    private var digits: Int? { session.baseCurrency?.currency?.digits }
    private var widgets: [DashboardWidgetConfig] { dashboard.widgets }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HomeReviewCard(state: model.reviewSummary) {
                    await model.loadReviewSummary()
                }

                if widgets.contains(where: { $0.kind?.needsPeriod == true }) {
                    HomePeriodSelector(
                        period: model.period,
                        canGoNext: model.canGoToNextPeriod,
                        previous: { Task { await model.showPreviousPeriod() } },
                        next: { Task { await model.showNextPeriod() } }
                    )
                }

                if widgets.isEmpty {
                    ContentUnavailableView {
                        Label("No Widgets", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Choose what Home shows.")
                    } actions: {
                        Button("Edit Home") { isEditing = true }
                            .buttonStyle(.borderedProminent)
                    }
                }

                ForEach(widgets) { widget in
                    if let kind = widget.kind {
                        card(kind, config: widget)
                    }
                }

                Button("Edit Home", systemImage: "slider.horizontal.3") { isEditing = true }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.default, value: model.reviewSummary.value)
            .animation(.default, value: widgets.map(\.widgetId))
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Edit Home", systemImage: "slider.horizontal.3") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            HomeEditSheet(initialWidgets: widgets) { updated in
                try await dashboard.saveLayout(updated)
                await dashboard.loadWidgets(period: model.period)
            }
        }
        .errorAlert($alert)
        .refreshable {
            async let cards: Void = model.refresh()
            async let reference: Void = referenceData.refresh()
            async let layout: Void = refreshDashboard()
            _ = await (cards, reference, layout)
        }
        .task {
            async let cards: Void = model.loadIfNeeded()
            async let layout: Void = loadDashboardIfNeeded()
            _ = await (cards, layout)
        }
        .onChange(of: model.period) { _, period in
            Task { await dashboard.loadWidgets(period: period) }
        }
        .onChange(of: router.reviewStack == nil) { _, isClosed in
            if isClosed { Task { await model.loadReviewSummary() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewStatusesDidChange)) { _ in
            Task {
                await model.loadReviewSummary()
                await model.loadLatest()
            }
        }
    }

    private func loadDashboardIfNeeded() async {
        guard dashboard.settings.value == nil else { return }
        await refreshDashboard()
    }

    private func refreshDashboard() async {
        await dashboard.loadSettings()
        await dashboard.loadWidgets(period: model.period)
    }

    /// Saves one widget's config, then reloads its data.
    private func saveConfig(_ kind: DashboardWidgetKind, _ values: [String: DashboardConfigValue]) async {
        do {
            try await dashboard.saveConfig(for: kind, values: values)
            await dashboard.loadWidgets(period: model.period)
        } catch {
            alert = ErrorAlert(error)
        }
    }

    @ViewBuilder
    private func card(_ kind: DashboardWidgetKind, config: DashboardWidgetConfig) -> some View {
        switch kind {
        case .balanceTrend:
            BalanceTrendCard(state: model.balance, currencyCode: currencyCode, digits: digits) {
                await model.loadBalance()
            }
        case .spendingCategories:
            SpendingCard(state: model.spending, currencyCode: currencyCode, digits: digits) {
                await model.loadSpending()
            }
        case .latestRecords:
            LatestTransactionsCard(state: model.latest) {
                await model.loadLatest()
            }
        case .subscriptionsOverview:
            UpcomingPaymentsCard(state: model.upcoming) {
                await model.loadUpcoming()
            }
        case .cashFlow:
            HomeCashFlowCard(
                state: dashboard.cashFlow,
                currencyCode: currencyCode,
                digits: digits,
                includePlanned: config.includePlanned,
                setIncludePlanned: { value in Task { await saveConfig(.cashFlow, ["includePlanned": .bool(value)]) } },
                retry: { await dashboard.loadCashFlow(period: model.period) }
            )
        case .netWorth:
            HomeNetWorthCard(
                state: dashboard.netWorth,
                period: model.period,
                includes: DashboardNetWorthIncludes(config: config.config),
                currencyCode: currencyCode,
                digits: digits,
                setIncludes: { includes in Task { await saveConfig(.netWorth, includes.configValues) } },
                retry: { await dashboard.loadNetWorth(period: model.period) }
            )
        case .creditUtilization:
            HomeCreditUtilizationCard(
                accounts: referenceData.accounts,
                hasLoaded: referenceData.hasLoaded,
                includeCreditLimitInStats: dashboard.includeCreditLimitInStats,
                currencyCode: currencyCode,
                digits: digits
            )
        case .plannedOverview:
            HomePlannedOverviewCard(
                state: dashboard.planned,
                accounts: referenceData.accounts,
                includeCreditLimitInStats: dashboard.includeCreditLimitInStats,
                currencyCode: currencyCode,
                digits: digits,
                retry: { await dashboard.loadPlanned() }
            )
        case .categorySpendingTracker:
            HomeCategoryTrackerCard(
                state: dashboard.tracker,
                selectedIDs: config.selectedCategoryIds,
                currencyCode: currencyCode,
                digits: digits,
                includePlanned: config.includePlanned,
                setIncludePlanned: { value in
                    Task { await saveConfig(.categorySpendingTracker, ["includePlanned": .bool(value)]) }
                },
                saveSelection: { ids in
                    await saveConfig(.categorySpendingTracker, ["selectedCategoryIds": .array(ids.map { .string($0) })])
                },
                retry: { await dashboard.loadTracker(period: model.period) }
            )
        }
    }
}
