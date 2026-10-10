import MoneyMatterKit
import SwiftUI

/// Root of the Home tab: spending for the selected period as a hero and a bar chart, the
/// review row, spending by category, the period's transactions, and upcoming payments.
struct HomeTab: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.homePath) {
            HomeScreen(model: HomeViewModel(services: services))
                .navigationTitle("Home")
                // No bar: spending leads the screen, with the glass buttons beside it.
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
    /// The scrubbed bar of the spending chart, shown in the hero.
    @State private var selectedBucketID: String?
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(AppServices.self) private var services
    @Environment(MonthlyBudgetModel.self) private var budget
    @Environment(\.scenePhase) private var scenePhase
    @State private var unread = NotificationsUnreadCounter.shared

    init(model: HomeViewModel) {
        _model = State(initialValue: model)
    }

    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }
    private var digits: Int? { session.baseCurrency?.currency?.digits }

    private var selectedBucket: SpendingBucket? {
        guard let selectedBucketID else { return nil }
        return model.buckets.value?.first { $0.id == selectedBucketID }
    }

    var body: some View {
        let today = CalendarDate(date: .now)
        ScrollView {
            VStack(spacing: 16) {
                header

                HomeBudgetSection(model: budget) {
                    router.presentMonthlyBudgetSettings()
                }

                HomePeriodPicker(period: model.period, today: today) { period in
                    selectedBucketID = nil
                    Task { await model.setPeriod(period) }
                }

                SpendingHero(
                    state: model.totals,
                    selected: selectedBucket,
                    granularity: model.period.granularity,
                    comparisonLabel: model.period.comparisonLabel,
                    currencyCode: currencyCode,
                    digits: digits,
                    retry: { await model.loadTotals() }
                )

                SpendingChartCard(
                    state: model.buckets,
                    granularity: model.period.granularity,
                    selectedID: $selectedBucketID,
                    currencyCode: currencyCode,
                    retry: { await model.loadBuckets() }
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
        .refreshable {
            async let cards: Void = model.refresh()
            async let reference: Void = referenceData.refresh()
            async let monthlyBudget: Void = budget.refresh(client: services.client)
            _ = await (cards, reference, monthlyBudget)
        }
        .task {
            await model.loadIfNeeded()
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

    /// "Spending" with the notifications and profile glass buttons at the top right.
    private var header: some View {
        HStack(spacing: DS.Space.m) {
            Text("Spending")
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
}
