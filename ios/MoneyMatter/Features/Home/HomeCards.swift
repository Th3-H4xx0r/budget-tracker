import Charts
import MoneyMatterKit
import SwiftUI

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

// MARK: - Period selector

struct HomePeriodSelector: View {
    let period: MonthPeriod
    let canGoNext: Bool
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack {
            Button(action: previous) {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous Month")
            Spacer()
            Text(period.firstDay.startDate().formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .contentTransition(.numericText())
            Spacer()
            Button(action: next) {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(!canGoNext)
            .accessibilityLabel("Next Month")
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Review card

struct HomeReviewCard: View {
    let state: LoadState<ReviewSummary>
    let retry: () async -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        switch state {
        case .failed:
            InlineRetryView(String(localized: "Couldn't load review status"), retry: retry)
                .cardStyle(padding: 12)
        case .loaded(let summary) where summary.unreviewedCount > 0:
            card(summary)
        case .idle, .loading, .loaded:
            EmptyView()
        }
    }

    private func card(_ summary: ReviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                router.openReviewPage(.unreviewed)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("^[\(summary.unreviewedCount) transaction](inflect: true) to review")
                            .font(.headline)
                        Text("Check recent bank transactions for anything you don't recognize")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            HStack {
                if summary.fraudCount > 0 {
                    Button {
                        router.openReviewPage(.fraud)
                    } label: {
                        Text("\(summary.fraudCount) marked as fraud")
                            .font(.subheadline.weight(.medium))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)
                }
                Spacer()
                Button {
                    router.presentReviewStack(expectedTotal: summary.unreviewedCount)
                } label: {
                    Text("Review")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
        .glassCardStyle()
    }
}

// MARK: - Balance trend

struct BalanceTrendCard: View {
    let state: LoadState<BalanceTrend>
    let currencyCode: String
    let digits: Int?
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Balance")
            switch state {
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error), retry: retry)
            case .loaded(let trend):
                content(trend)
            case .idle, .loading:
                content(BalanceTrend.placeholder)
                    .redactedWhileLoading(true)
            }
        }
        .cardStyle()
    }

    private func content(_ trend: BalanceTrend) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                AmountText(trend.currentTotal ?? 0, currencyCode: currencyCode, digits: digits)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let change = trend.change {
                    HStack(spacing: 4) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .accessibilityHidden(true)
                        AmountText(change, currencyCode: currencyCode, digits: digits, showsPlusSign: true)
                        Text("vs. last month")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .foregroundStyle(change >= 0 ? Color.green : Color.red)
                }
            }

            if trend.points.count > 1 {
                chart(trend.points)
            } else {
                Text("Not enough data for a trend yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    private func chart(_ points: [BalancePoint]) -> some View {
        let values = points.map(\.totalBalance.doubleValue)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let padding = max((high - low) * 0.1, 1)
        let floor = low - padding

        return Chart(points) { point in
            AreaMark(
                x: .value("Date", point.date.startDate(), unit: .day),
                yStart: .value("Floor", floor),
                yEnd: .value("Balance", point.totalBalance.doubleValue)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Date", point.date.startDate(), unit: .day),
                y: .value("Balance", point.totalBalance.doubleValue)
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
        .chartYScale(domain: floor...(high + padding))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(verbatim: MoneyFormat.compactString(Decimal(amount), currencyCode: currencyCode))
                    }
                }
            }
        }
        .frame(height: 160)
        .accessibilityChartDescriptor(BalanceChartDescriptor(points: points, currencyCode: currencyCode))
    }
}

extension BalanceTrend {
    static let placeholder: BalanceTrend = {
        let today = CalendarDate(date: .now)
        let points = (0..<10).map { index in
            BalancePoint(date: today.adding(days: index - 10), totalBalance: Decimal(1000 + index * 40))
        }
        return BalanceTrend(points: points, previousTotal: 1000)
    }()
}

private struct BalanceChartDescriptor: AXChartDescriptorRepresentable {
    let points: [BalancePoint]
    let currencyCode: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = points.map { $0.date.startDate().timeIntervalSince1970 }
        let values = points.map(\.totalBalance.doubleValue)
        let currencyCode = currencyCode
        let xAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Date"),
            range: (dates.min() ?? 0)...(dates.max() ?? 1),
            gridlinePositions: []
        ) { value in
            Date(timeIntervalSince1970: value).formatted(date: .abbreviated, time: .omitted)
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Balance"),
            range: (values.min() ?? 0)...(values.max() ?? 1),
            gridlinePositions: []
        ) { value in
            MoneyFormat.string(Decimal(value), currencyCode: currencyCode)
        }
        let series = AXDataSeriesDescriptor(
            name: String(localized: "Total balance"),
            isContinuous: true,
            dataPoints: zip(dates, values).map { AXDataPoint(x: $0, y: $1) }
        )
        return AXChartDescriptor(
            title: String(localized: "Balance trend"),
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Spending by category

struct SpendingCard: View {
    let state: LoadState<SpendingBreakdown>
    let currencyCode: String
    let digits: Int?
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Spending by Category")
            switch state {
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error), retry: retry)
            case .loaded(let breakdown) where breakdown.categories.isEmpty:
                Text("No expenses this month.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            case .loaded(let breakdown):
                content(breakdown)
            case .idle, .loading:
                content(SpendingBreakdown.placeholder)
                    .redactedWhileLoading(true)
            }
        }
        .cardStyle()
    }

    private func content(_ breakdown: SpendingBreakdown) -> some View {
        let slices = slices(for: breakdown)
        return VStack(spacing: 16) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Amount", slice.amount.doubleValue),
                    innerRadius: .ratio(0.64),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let anchor = proxy.plotFrame {
                        let frame = geometry[anchor]
                        VStack(spacing: 2) {
                            Text("Spent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            AmountText(breakdown.total, currencyCode: currencyCode, digits: digits)
                                .font(.title3.weight(.semibold))
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                        }
                        .frame(width: frame.width * 0.55)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: 200)
            .accessibilityChartDescriptor(SpendingChartDescriptor(slices: slices, currencyCode: currencyCode))

            VStack(spacing: 10) {
                ForEach(breakdown.topCategories) { category in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: category.color) ?? .gray)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(category.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        AmountText(category.amount, currencyCode: currencyCode, digits: digits)
                            .font(.subheadline.weight(.medium))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func slices(for breakdown: SpendingBreakdown) -> [SpendingSlice] {
        var slices = breakdown.topCategories.map {
            SpendingSlice(id: $0.id, name: $0.name, amount: $0.amount, color: Color(hex: $0.color) ?? .gray)
        }
        if breakdown.otherAmount > 0 {
            slices.append(SpendingSlice(id: "other", name: String(localized: "Other"), amount: breakdown.otherAmount, color: Color(.systemGray4)))
        }
        return slices
    }
}

struct SpendingSlice: Identifiable {
    let id: String
    let name: String
    let amount: Decimal
    let color: Color
}

extension SpendingBreakdown {
    static let placeholder = SpendingBreakdown(
        total: 1000,
        categories: (0..<5).map { index in
            CategorySpending(id: "placeholder-\(index)", name: "Category name", color: "#8e8e93", amount: Decimal(500 - index * 80))
        }
    )
}

private struct SpendingChartDescriptor: AXChartDescriptorRepresentable {
    let slices: [SpendingSlice]
    let currencyCode: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = slices.map(\.amount.doubleValue)
        let currencyCode = currencyCode
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: String(localized: "Category"),
            categoryOrder: slices.map(\.name)
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Amount"),
            range: 0...(values.max() ?? 1),
            gridlinePositions: []
        ) { value in
            MoneyFormat.string(Decimal(value), currencyCode: currencyCode)
        }
        let series = AXDataSeriesDescriptor(
            name: String(localized: "Spending"),
            isContinuous: false,
            dataPoints: slices.map { AXDataPoint(x: $0.name, y: $0.amount.doubleValue) }
        )
        return AXChartDescriptor(
            title: String(localized: "Spending by category"),
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Latest transactions

struct LatestTransactionsCard: View {
    let state: LoadState<[Transaction]>
    let retry: () async -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Latest Transactions") {
                Button("See All") {
                    router.show(.transactions)
                }
                .font(.subheadline)
            }
            switch state {
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error), retry: retry)
            case .loaded(let rows) where rows.isEmpty:
                Text("No transactions yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            case .loaded(let rows):
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, transaction in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 48)
                    }
                    NavigationLink(value: HomeRoute.transaction(id: transaction.id)) {
                        ResolvedTransactionRow(transaction: transaction, showsDate: true)
                    }
                    .buttonStyle(.plain)
                }
            case .idle, .loading:
                TransactionRowsPlaceholder(count: HomeViewModel.latestCount)
            }
        }
        .cardStyle()
    }
}

// MARK: - Upcoming payments

struct UpcomingPaymentsCard: View {
    let state: LoadState<[SubscriptionListItem]>
    let retry: () async -> Void

    var body: some View {
        switch state {
        case .loaded(let items) where items.isEmpty:
            EmptyView()
        case .loaded(let items):
            container {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 48)
                    }
                    UpcomingPaymentRow(item: item)
                }
            }
        case .failed(let error):
            container {
                InlineRetryView(ErrorMessage.message(for: error), retry: retry)
            }
        case .idle, .loading:
            container {
                UpcomingPaymentRow(item: nil)
                    .redactedWhileLoading(true)
            }
        }
    }

    private func container(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader("Upcoming Payments")
            content()
        }
        .cardStyle()
    }
}

private struct UpcomingPaymentRow: View {
    /// `nil` renders the loading placeholder.
    let item: SubscriptionListItem?

    @Environment(ReferenceDataStore.self) private var referenceData

    var body: some View {
        HStack(spacing: 12) {
            InitialsBadge(item?.logoInitials ?? String(item?.name.prefix(2) ?? "Su"), colorHex: item?.logoColor ?? item?.category?.color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item?.name ?? "Subscription name")
                    .font(.body)
                    .lineLimit(1)
                dueText
                    .font(.subheadline)
            }
            Spacer(minLength: 8)
            if let item, let amount = item.expectedAmount, let code = item.expectedCurrencyCode {
                AmountText(
                    amount,
                    currencyCode: code,
                    digits: referenceData.digits(for: code),
                    style: item.transactionType == .income ? .income : .expense
                )
                .font(.body.weight(.medium))
            } else if item == nil {
                Text(verbatim: "$00.00")
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var dueText: some View {
        if let item, item.isOverdue {
            Text("Overdue")
                .foregroundStyle(.red)
        } else if let due = item?.currentPeriod?.dueDate ?? item?.nextDueDate {
            let today = CalendarDate(date: .now)
            Group {
                if due <= today {
                    Text("Due today")
                } else if due == today.adding(days: 1) {
                    Text("Due tomorrow")
                } else {
                    Text("Due \(due.startDate().formatted(.dateTime.weekday(.wide)))")
                }
            }
            .foregroundStyle(.secondary)
        } else {
            Text("Due soon")
                .foregroundStyle(.secondary)
        }
    }
}
