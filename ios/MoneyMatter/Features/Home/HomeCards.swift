import Charts
import MoneyMatterKit
import SwiftUI

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

// MARK: - Period picker

/// The period control under the header: Month, YTD, 1Y and Last year as segments, and a
/// chip below them naming the exact span, whose menu picks a specific month or earlier year.
struct HomePeriodPicker: View {
    static let monthCount = 24
    static let yearCount = 10

    let period: HomePeriod
    let today: CalendarDate
    let select: (HomePeriod) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Picker("Period", selection: Binding(
                get: { period.kind },
                set: { kind in
                    if let kind { select(.defaultPeriod(for: kind, today: today)) }
                }
            )) {
                ForEach(HomePeriod.Kind.allCases) { kind in
                    Text(verbatim: kind.label).tag(Optional(kind))
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            HStack(spacing: 0) {
                stepButton(delta: -1)
                Spacer(minLength: 0)
                periodMenu
                Spacer(minLength: 0)
                stepButton(delta: 1)
            }
            .sensoryFeedback(.selection, trigger: period)
        }
    }

    /// Previous / next arrow. Months step by one month and years by one year; YTD and 1Y have
    /// nothing to step through, so their arrows are hidden but keep their space to centre the title.
    private func stepButton(delta: Int) -> some View {
        let target = stepped(by: delta)
        let isStepping = period.kind == .month || period.kind == .lastYear || period.kind == nil
        return Button {
            if let target { select(target) }
        } label: {
            Image(systemName: delta < 0 ? "chevron.left" : "chevron.right")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(target == nil ? Color(uiColor: .quaternaryLabel) : Color(uiColor: .secondaryLabel))
        .disabled(target == nil)
        .opacity(isStepping ? 1 : 0)
        .accessibilityHidden(!isStepping)
        .accessibilityLabel(Text(delta < 0 ? "Previous" : "Next"))
    }

    /// The neighbouring period, or nil when stepping would reach the future or past the oldest year.
    private func stepped(by delta: Int) -> HomePeriod? {
        switch period {
        case let .month(year, month):
            var newMonth = month + delta
            var newYear = year
            if newMonth < 1 { newMonth = 12; newYear -= 1 } else if newMonth > 12 { newMonth = 1; newYear += 1 }
            if newYear > today.year || (newYear == today.year && newMonth > today.month) { return nil }
            return .month(year: newYear, month: newMonth)
        case .lastYear:
            return steppedYear(from: today.year - 1, by: delta)
        case let .year(year):
            return steppedYear(from: year, by: delta)
        case .ytd, .last12Months:
            return nil
        }
    }

    private func steppedYear(from year: Int, by delta: Int) -> HomePeriod? {
        let target = year + delta
        guard target < today.year, target >= today.year - Self.yearCount else { return nil }
        return .calendarYear(target, today: today)
    }

    /// The centred title; tapping it jumps straight to any recent month or earlier year.
    private var periodMenu: some View {
        Menu {
                Section("Month") {
                    ForEach(recentMonths, id: \.self) { month in
                        option(
                            .month(year: month.year, month: month.month),
                            title: month.firstDay.startDate().formatted(.dateTime.month(.wide).year())
                        )
                    }
                }
                Section("Year") {
                    ForEach(earlierYears, id: \.self) { year in
                        option(.calendarYear(year, today: today), title: String(year))
                    }
                }
            } label: {
                Text(verbatim: period.title(today: today))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Color(uiColor: .label))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .tint(Color(uiColor: .label))
            .accessibilityHint(Text("Choose a month or year"))
    }

    private func option(_ value: HomePeriod, title: String) -> some View {
        Button {
            select(value)
        } label: {
            if value == period {
                Label(title, systemImage: "checkmark")
            } else {
                Text(verbatim: title)
            }
        }
    }

    /// The current month first, then the ones before it.
    private var recentMonths: [MonthPeriod] {
        var month = MonthPeriod(year: today.year, month: today.month)
        var months: [MonthPeriod] = []
        for _ in 0..<Self.monthCount {
            months.append(month)
            month = month.previous
        }
        return months
    }

    /// Last year first, then the years before it.
    private var earlierYears: [Int] {
        (1...Self.yearCount).map { today.year - $0 }
    }
}

// MARK: - Review row

/// The compact review row: the unreviewed count on a shield tile, with the fraud badge when
/// any are marked. Tapping starts the review stack; the review page and the fraud list sit
/// in the context menu and the accessibility actions.
struct HomeReviewCard: View {
    let state: LoadState<ReviewSummary>
    let retry: () async -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        switch state {
        case .failed:
            ErrorRow(String(localized: "Couldn't load review status"), retry: retry)
        case .loaded(let summary) where summary.unreviewedCount > 0:
            row(summary)
        case .idle, .loading, .loaded:
            EmptyView()
        }
    }

    private func row(_ summary: ReviewSummary) -> some View {
        Button {
            router.presentReviewStack(expectedTotal: summary.unreviewedCount)
        } label: {
            EntityRow(
                String(localized: "\(summary.unreviewedCount) transactions to review"),
                subtitle: String(localized: "Check recent bank transactions for anything you don't recognize"),
                systemImage: "checkmark.shield.fill"
            ) {
                HStack(spacing: DS.Space.s) {
                    if summary.fraudCount > 0 {
                        StatusBadge(label: String(localized: "\(summary.fraudCount) fraud"), color: DS.Palette.danger)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, DS.Space.m)
            .padding(.horizontal, DS.Space.l)
            .background(DS.Surface.panel, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Review", systemImage: "rectangle.stack") {
                router.presentReviewStack(expectedTotal: summary.unreviewedCount)
            }
            Button("See All", systemImage: "list.bullet") { router.openReviewPage(.unreviewed) }
            if summary.fraudCount > 0 {
                Button("\(summary.fraudCount) marked as fraud", systemImage: "exclamationmark.shield") {
                    router.openReviewPage(.fraud)
                }
            }
        }
        .accessibilityAction(named: Text("See All")) { router.openReviewPage(.unreviewed) }
        .accessibilityAction(named: Text("\(summary.fraudCount) marked as fraud")) { router.openReviewPage(.fraud) }
    }
}

// MARK: - Spending hero

/// The Home hero: the period's spending, and its change against the earlier period. Only
/// the arrow and the change are coloured: red for more spending, green for less; the
/// comparison stays secondary. A scrubbed chart point replaces the value with its amount
/// and the change line with its label.
struct SpendingHero: View {
    let state: LoadState<SpendingTotals>
    let selection: HomeChartSelection?
    let comparisonLabel: String
    let currencyCode: String
    let digits: Int?
    let retry: () async -> Void

    var body: some View {
        switch state {
        case .failed(let error):
            ErrorRow(ErrorMessage.message(for: error), retry: retry)
        case .loaded(let totals):
            content(totals)
        case .idle, .loading:
            content(SpendingTotals(current: 1_000, previous: 900))
                .redactedWhileLoading(true)
        }
    }

    private func content(_ totals: SpendingTotals) -> some View {
        let shown = selection?.amount ?? totals.current
        return HeroValueHeader(
            MoneyFormat.string(shown, currencyCode: currencyCode, digits: digits),
            numericValue: shown.doubleValue,
            valueAnimation: selection == nil ? .snappy : nil
        ) {
            if let selection {
                Text(verbatim: selection.label)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(1)
            } else {
                changeLine(totals)
            }
        }
    }

    private func changeLine(_ totals: SpendingTotals) -> some View {
        let delta = totals.change
        let color: Color = delta > 0 ? DS.Palette.danger : delta < 0 ? DS.Palette.success : Color(uiColor: .secondaryLabel)
        let symbol: String? = delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : nil
        let text = changeText(delta: delta, previous: totals.previous)
        return HStack(spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.xxs) {
                if let symbol {
                    Image(systemName: symbol)
                        .accessibilityHidden(true)
                }
                Text(verbatim: text)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            Text(verbatim: comparisonLabel)
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [
            delta > 0 ? String(localized: "Spending up") : delta < 0 ? String(localized: "Spending down") : "",
            text,
            comparisonLabel,
        ].filter { !$0.isEmpty }.joined(separator: " ")))
    }

    private func changeText(delta: Decimal, previous: Decimal) -> String {
        let amount = MoneyFormat.string(abs(delta), currencyCode: currencyCode, digits: digits)
        let sign = delta > 0 ? "+" : delta < 0 ? "\u{2212}" : ""
        guard previous != 0 else { return sign + amount }
        let percent = abs((delta / previous).doubleValue)
        return "\(sign)\(amount) (\(percent.formatted(.percent.precision(.fractionLength(0...1)))))"
    }
}

// MARK: - Spending by category

struct SpendingSlice: Identifiable {
    let id: String
    let name: String
    let amount: Decimal
    let color: Color
}

/// A slim violet donut of the period's top five categories plus "Other", the total in its
/// centre, and each one's share and amount listed below.
struct CategorySpendingCard: View {
    let state: LoadState<SpendingBreakdown>
    let currencyCode: String
    let digits: Int?
    let retry: () async -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DSCard(String(localized: "Spending by category")) {
            switch state {
            case .failed(let error):
                ErrorRow(ErrorMessage.message(for: error), retry: retry)
            case .loaded(let breakdown) where breakdown.categories.isEmpty:
                Text("No expenses in this period.")
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
    }

    private static let donutSize: CGFloat = 170

    private func content(_ breakdown: SpendingBreakdown) -> some View {
        let slices = slices(for: breakdown)
        let total = breakdown.total
        return VStack(spacing: DS.Space.l) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Amount", slice.amount.doubleValue),
                    innerRadius: .ratio(0.72),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let anchor = proxy.plotFrame {
                        let frame = geometry[anchor]
                        VStack(spacing: DS.Space.xxs) {
                            Text("Spent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            AmountText(total, currencyCode: currencyCode, digits: digits)
                                .font(.title3.bold())
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                        }
                        .frame(width: frame.width * 0.6)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(width: Self.donutSize, height: Self.donutSize)
            .frame(maxWidth: .infinity)
            .accessibilityChartDescriptor(SpendingChartDescriptor(slices: slices, currencyCode: currencyCode))

            Grid(alignment: .leading, horizontalSpacing: DS.Space.s, verticalSpacing: DS.Space.m) {
                ForEach(slices) { slice in
                    GridRow {
                        Circle()
                            .fill(slice.color)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(verbatim: slice.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: share(of: slice.amount, total: total))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .gridColumnAlignment(.trailing)
                        AmountText(slice.amount, currencyCode: currencyCode, digits: digits)
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .gridColumnAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func share(of amount: Decimal, total: Decimal) -> String {
        guard total != 0 else { return "" }
        return (amount / total).doubleValue.formatted(.percent.precision(.fractionLength(0)))
    }

    private func slices(for breakdown: SpendingBreakdown) -> [SpendingSlice] {
        let top = breakdown.topCategories
        let hasOther = breakdown.otherAmount > 0
        let count = top.count + (hasOther ? 1 : 0)
        var slices = top.enumerated().map { rank, category in
            SpendingSlice(
                id: category.id,
                name: category.name,
                amount: category.amount,
                color: DonutPalette.color(rank: rank, count: count, scheme: colorScheme)
            )
        }
        if hasOther {
            // The tail takes the palette's faintest violet, softened further so it reads as muted.
            let muted = DonutPalette.color(rank: count - 1, count: count, scheme: colorScheme).opacity(0.55)
            slices.append(SpendingSlice(id: "other", name: String(localized: "Other"), amount: breakdown.otherAmount, color: muted))
        }
        return slices
    }
}

extension SpendingBreakdown {
    static let placeholder = SpendingBreakdown(
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

// MARK: - Transactions

/// The period's latest transactions. "See all" opens the Transactions tab.
struct PeriodTransactionsCard: View {
    let state: LoadState<[Transaction]>
    let retry: () async -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            CardHeader(title: "Transactions") {
                Button("See all") {
                    router.show(.transactions)
                }
            }
            switch state {
            case .failed(let error):
                ErrorRow(ErrorMessage.message(for: error), retry: retry)
            case .loaded(let rows) where rows.isEmpty:
                Text("No transactions in this period.")
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
                TransactionRowsPlaceholder(count: 5)
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
                ErrorRow(ErrorMessage.message(for: error), retry: retry)
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
            CardHeader("Upcoming payments")
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
