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
                // No bar: net worth leads the screen, with the glass buttons beside it.
                .toolbar(.hidden, for: .navigationBar)
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
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var unread = NotificationsUnreadCounter.shared

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
                header

                BalanceTrendCard(
                    state: model.balance,
                    range: model.balanceRange,
                    updatedAt: model.balanceUpdatedAt,
                    currencyCode: currencyCode,
                    digits: digits,
                    setRange: { range in Task { await model.setBalanceRange(range) } },
                    retry: { await model.loadBalance() }
                )
                .padding(.bottom, DS.Space.s)

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
                            .dsProminentButton()
                    }
                }

                ForEach(widgets) { widget in
                    if let kind = widget.kind {
                        card(kind, config: widget)
                    }
                }

                InlineActionRow(String(localized: "Edit Home"), systemImage: "slider.horizontal.3") { isEditing = true }
                    .padding(.vertical, DS.Space.m)
                    .padding(.horizontal, DS.Space.l)
                    .background(DS.Surface.panel, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
                    .padding(.top, DS.Space.xs)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.default, value: model.reviewSummary.value)
            .animation(.default, value: widgets.map(\.widgetId))
        }
        .background(DS.Surface.canvas)
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

    /// "Net worth" with the notifications and profile glass buttons at the top right.
    private var header: some View {
        HStack(spacing: DS.Space.m) {
            Text("Net worth")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            GlassCircleButton(
                systemImage: "bell",
                badge: unread.count,
                accessibilityLabel: String(localized: "Notifications")
            ) {
                router.homePath.append(.notifications)
            }
            GlassCircleButton(accessibilityLabel: String(localized: "Profile and Settings")) {
                router.presentSettings()
            } label: {
                Text(verbatim: session.user?.initials ?? "?")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.top, DS.Space.xs)
        .task(id: scenePhase) {
            // Keeps the shared unread count fresh while Home is on screen.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await unread.refresh(client: services.client)
                try? await Task.sleep(for: .seconds(60))
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
            // The net worth hero at the top of Home draws the balance trend.
            EmptyView()
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
