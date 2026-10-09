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
            HomeScreen(model: HomeViewModel(services: services))
                .navigationTitle("Home")
                .toolbar {
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
                    }
                }
        }
    }
}

private struct HomeScreen: View {
    @State private var model: HomeViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ReferenceDataStore.self) private var referenceData

    init(model: HomeViewModel) {
        _model = State(initialValue: model)
    }

    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }
    private var digits: Int? { session.baseCurrency?.currency?.digits }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HomeReviewCard(state: model.reviewSummary) {
                    await model.loadReviewSummary()
                }

                HomePeriodSelector(
                    period: model.period,
                    canGoNext: model.canGoToNextPeriod,
                    previous: { Task { await model.showPreviousPeriod() } },
                    next: { Task { await model.showNextPeriod() } }
                )

                BalanceTrendCard(state: model.balance, currencyCode: currencyCode, digits: digits) {
                    await model.loadBalance()
                }

                SpendingCard(state: model.spending, currencyCode: currencyCode, digits: digits) {
                    await model.loadSpending()
                }

                LatestTransactionsCard(state: model.latest) {
                    await model.loadLatest()
                }

                UpcomingPaymentsCard(state: model.upcoming) {
                    await model.loadUpcoming()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.default, value: model.reviewSummary.value)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            async let cards: Void = model.refresh()
            async let reference: Void = referenceData.refresh()
            _ = await (cards, reference)
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
                await model.loadLatest()
            }
        }
    }
}
