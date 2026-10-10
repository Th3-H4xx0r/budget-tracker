import MoneyMatterKit
import SwiftUI

/// Root of the Home tab: spending for the selected period as a hero over a line or bar
/// chart, the review row, spending by category, the period's transactions, and upcoming
/// payments.
struct HomeTab: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.homePath) {
            HomeScreen(model: HomeViewModel(services: services))
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
    /// The scrubbed day of the Month view's line chart, shown in the hero.
    @State private var selectedDay: Int?
    /// The scrubbed bar of the longer periods' chart, shown in the hero.
    @State private var selectedBucketID: String?
    @State private var isAddingTransaction = false
    /// Whether the spending figure is on screen; the bar's compact title shows once it isn't.
    @State private var heroVisible = true
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(AppServices.self) private var services
    @Environment(MonthlyBudgetModel.self) private var budget
    @Environment(\.scenePhase) private var scenePhase
    @State private var unread = NotificationsUnreadCounter.shared

    /// Space between Home's sections.
    private static let sectionSpacing: CGFloat = 20

    init(model: HomeViewModel) {
        _model = State(initialValue: model)
    }

    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }
    private var digits: Int? { session.baseCurrency?.currency?.digits }

    private var isCurrentMonth: Bool {
        model.period == .currentMonth()
    }

    /// The budget snapshot covers only the current month, so the budget line, the banner
    /// and the chart's budget rule follow it there.
    private var budgetSnapshot: MonthlySpendingSnapshot? {
        guard isCurrentMonth, let snapshot = budget.snapshot, snapshot.hasBudget else { return nil }
        return snapshot
    }

    private var isOverBudgetBannerShown: Bool {
        budgetSnapshot?.isOverBudget ?? false
    }

    /// The tab bar accessory carries the `+` while there is anything to review; otherwise
    /// it sits in the toolbar.
    private var showsAddButton: Bool {
        (model.reviewSummary.value?.unreviewedCount ?? 0) == 0
    }

    private var chartSelection: HomeChartSelection? {
        if case .month = model.period {
            guard let selectedDay, let data = model.daily.value,
                  let point = data.current.first(where: { $0.day == selectedDay }) else { return nil }
            let day = point.date.formatted(.dateTime.month(.abbreviated).day())
            guard let earlier = data.previous.first(where: { $0.day == selectedDay }) else {
                return HomeChartSelection(amount: point.amount, label: day)
            }
            let previousLabel = SpendingChartCard.legendLabels(for: model.period).previous
            let earlierAmount = MoneyFormat.string(earlier.amount, currencyCode: currencyCode, digits: digits)
            return HomeChartSelection(
                amount: point.amount,
                label: "\(day) \u{00B7} \(previousLabel) \(earlierAmount)"
            )
        }
        guard let selectedBucketID, let bucket = model.buckets.value?.first(where: { $0.id == selectedBucketID }) else {
            return nil
        }
        return HomeChartSelection(amount: bucket.amount, label: bucket.label)
    }

    var body: some View {
        let today = CalendarDate(date: .now)
        ScrollView {
            VStack(spacing: Self.sectionSpacing) {
                if let snapshot = budgetSnapshot, isOverBudgetBannerShown {
                    OverBudgetBanner(snapshot: snapshot) {
                        router.presentMonthlyBudgetSettings()
                    }
                }

                HomePeriodPicker(period: model.period, today: today) { period in
                    selectedDay = nil
                    selectedBucketID = nil
                    Task { await model.setPeriod(period) }
                }

                VStack(alignment: .leading, spacing: DS.Space.m) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("Spending")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        SpendingHero(
                            state: model.totals,
                            selection: chartSelection,
                            comparisonLabel: model.period.comparisonLabel,
                            currencyCode: currencyCode,
                            digits: digits,
                            retry: { await model.loadTotals() }
                        )
                        .onScrollVisibilityChange(threshold: 0.1) { visible in
                            heroVisible = visible
                        }
                    }
                    if isCurrentMonth {
                        // The banner already states the overrun, so the line keeps only its bar.
                        HomeBudgetLine(model: budget, showsDetail: !isOverBudgetBannerShown) {
                            router.presentMonthlyBudgetSettings()
                        }
                    }
                }

                SpendingChartCard(
                    period: model.period,
                    daily: model.daily,
                    buckets: model.buckets,
                    budget: budgetSnapshot?.budget,
                    selectedDay: $selectedDay,
                    selectedBucketID: $selectedBucketID,
                    currencyCode: currencyCode,
                    retry: { await model.loadChart() }
                )

                HomeReviewCard(state: model.reviewSummary) {
                    await model.loadReviewSummary()
                }

                CategorySpendingCard(state: model.spending, currencyCode: currencyCode, digits: digits) {
                    await model.loadSpending()
                }

                PeriodTransactionsCard(state: model.periodTransactions) {
                    await model.loadTransactions()
                }

                UpcomingPaymentsCard(state: model.upcoming) {
                    await model.loadUpcoming()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.default, value: model.reviewSummary.value)
        }
        .background(DS.Surface.canvas)
        .heroScreenTitle("Spending", isHeroVisible: heroVisible)
        .toolbar { toolbarItems }
        .refreshable {
            async let cards: Void = model.refresh()
            async let reference: Void = referenceData.refresh()
            async let monthlyBudget: Void = budget.refresh(client: services.client)
            _ = await (cards, reference, monthlyBudget)
        }
        .task {
            await model.loadIfNeeded()
        }
        .task(id: scenePhase) {
            // Keeps the shared unread count fresh while Home is on screen.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await unread.refresh(client: services.client)
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .sheet(isPresented: $isAddingTransaction) {
            TransactionEditorSheet(mode: .create(accountId: nil))
        }
        .onChange(of: router.reviewStack == nil) { _, isClosed in
            if isClosed { Task { await model.loadReviewSummary() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewStatusesDidChange)) { _ in
            Task {
                await model.loadReviewSummary()
                await model.loadTransactions()
            }
        }
    }

    /// Add (while the review queue is empty) and notifications share one glass group;
    /// profile sits apart.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if showsAddButton {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add transaction", systemImage: "plus") {
                    isAddingTransaction = true
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Notifications", systemImage: "bell") {
                router.homePath.append(.notifications)
            }
            .badge(unreadBadge)
            .accessibilityValue(unread.count > 0 ? Text("\(unread.count) unread") : Text(verbatim: ""))
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                router.presentSettings()
            } label: {
                Text(verbatim: session.user?.initials ?? "?")
                    .font(.footnote.weight(.semibold))
            }
            .accessibilityLabel(Text("Profile and Settings"))
        }
    }

    private var unreadBadge: Text? {
        switch unread.count {
        case ...0: nil
        case 100...: Text(verbatim: "99+")
        default: Text(verbatim: "\(unread.count)")
        }
    }
}
