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
    /// The scrubbed day of the Month view's line chart, shown in the hero.
    @State private var selectedDay: Int?
    /// The scrubbed bar of the longer periods' chart, shown in the hero.
    @State private var selectedBucketID: String?
    @State private var isAddingTransaction = false
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

    /// The tab bar accessory carries the `+` while there is anything to review; otherwise
    /// it sits in the header.
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
                header

                if let snapshot = budgetSnapshot, snapshot.isOverBudget {
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
                    SpendingHero(
                        state: model.totals,
                        selection: chartSelection,
                        comparisonLabel: model.period.comparisonLabel,
                        currencyCode: currencyCode,
                        digits: digits,
                        retry: { await model.loadTotals() }
                    )
                    if isCurrentMonth {
                        HomeBudgetLine(model: budget) {
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
        .refreshable {
            async let cards: Void = model.refresh()
            async let reference: Void = referenceData.refresh()
            async let monthlyBudget: Void = budget.refresh(client: services.client)
            _ = await (cards, reference, monthlyBudget)
        }
        .task {
            await model.loadIfNeeded()
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

    /// "Spending" as a large title, with compact glass buttons on its baseline: add (while
    /// the review queue is empty), notifications, and profile.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text("Spending")
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.s)
            if showsAddButton {
                HomeHeaderButton(systemImage: "plus", accessibilityLabel: String(localized: "Add transaction")) {
                    isAddingTransaction = true
                }
                .transition(.scale.combined(with: .opacity))
            }
            HomeHeaderButton(
                systemImage: "bell",
                badge: unread.count,
                accessibilityLabel: String(localized: "Notifications")
            ) {
                router.homePath.append(.notifications)
            }
            HomeHeaderButton(accessibilityLabel: String(localized: "Profile and Settings")) {
                router.presentSettings()
            } label: {
                Text(verbatim: session.user?.initials ?? "?")
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(.top, DS.Space.s)
        .animation(.snappy, value: showsAddButton)
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

/// A 36 pt Liquid Glass circle for Home's header, sitting on the title's baseline, with an
/// optional unread badge on its corner. The hit area stays 44 pt.
private struct HomeHeaderButton<Label: View>: View {
    let accessibilityLabel: String
    var badge: Int
    let action: () -> Void
    private let label: Label

    private static var size: CGFloat { 36 }

    init(badge: Int = 0, accessibilityLabel: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.badge = badge
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: Self.size, height: Self.size)
                .glassEffect(.regular.interactive(), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if badge > 0 {
                Text(verbatim: badge > 99 ? "99+" : "\(badge)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.onAccent)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(DS.Palette.accent, in: .capsule)
                    .offset(x: 0, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, -(44 - Self.size) / 2)
        // The circle's centre sits about half a cap height above the title's baseline.
        .alignmentGuide(.firstTextBaseline) { dimensions in
            dimensions[VerticalAlignment.center] + 12
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(badge > 0 ? Text("\(badge) unread") : Text(verbatim: ""))
    }
}

extension HomeHeaderButton where Label == Image {
    init(systemImage: String, badge: Int = 0, accessibilityLabel: String, action: @escaping () -> Void) {
        self.init(badge: badge, accessibilityLabel: accessibilityLabel, action: action) {
            Image(systemName: systemImage)
        }
    }
}
