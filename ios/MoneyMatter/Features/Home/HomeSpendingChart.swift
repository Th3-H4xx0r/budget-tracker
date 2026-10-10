import Charts
import MoneyMatterKit
import SwiftUI

/// What a scrubbed point of the spending chart puts in the hero: its amount and a line
/// naming it.
struct HomeChartSelection: Equatable {
    let amount: Decimal
    let label: String
}

/// "Spending over time". A month draws its running total Stocks style (a 2 pt monotone
/// accent line over a 12 % fill, hidden axes) over the month before as a dotted secondary
/// line, with the monthly budget as a dashed rule. Longer periods draw one slim accent bar
/// per month with a dashed average. Scrubbing either one feeds the hero, with a selection
/// haptic per step.
struct SpendingChartCard: View {
    let period: HomePeriod
    let daily: LoadState<DailySpending>
    let buckets: LoadState<[SpendingBucket]>
    let budget: Decimal?
    @Binding var selectedDay: Int?
    @Binding var selectedBucketID: String?
    let currencyCode: String
    let retry: () async -> Void

    @State private var rawDay: Int?

    private static let chartHeight: CGFloat = 180
    private static let labelRowHeight: CGFloat = 20
    private static let ruleDash: [CGFloat] = [4, 4]

    private var isMonth: Bool {
        if case .month = period { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.cardGroupSpacing) {
            header
            if isMonth {
                dailyContent
            } else {
                bucketContent
            }
        }
        .dsCardSurface(padding: EdgeInsets(
            top: DS.cardPadding,
            leading: DS.cardPadding,
            bottom: DS.cardPadding,
            trailing: DS.cardPadding
        ))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text("Spending over time")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.s)
            if isMonth {
                HStack(spacing: DS.Space.m) {
                    legendItem(color: DS.Palette.accent, label: legendLabels.current)
                    legendItem(color: Color.secondary.opacity(0.5), label: legendLabels.previous)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(verbatim: label)
        }
    }

    /// "This month" and "Last month" for the current month; month names for an earlier one.
    private var legendLabels: (current: String, previous: String) {
        Self.legendLabels(for: period)
    }

    static func legendLabels(for period: HomePeriod, today: CalendarDate = CalendarDate(date: .now)) -> (current: String, previous: String) {
        guard case let .month(year, month) = period else { return ("", "") }
        if year == today.year, month == today.month {
            return (String(localized: "This month"), String(localized: "Last month"))
        }
        let first = CalendarDate(year: year, month: month, day: 1)
        let previous = first.shifted(months: -1)
        return (
            first.startDate().formatted(.dateTime.month(.wide)),
            previous.startDate().formatted(.dateTime.month(.wide))
        )
    }

    // MARK: Month: running total

    @ViewBuilder
    private var dailyContent: some View {
        switch daily {
        case .failed(let error):
            ErrorRow(ErrorMessage.message(for: error), retry: retry)
        case .loaded(let data) where data.current.allSatisfy({ $0.amount == 0 }) && data.previous.allSatisfy({ $0.amount == 0 }):
            emptyState
        case .loaded(let data):
            dailyChart(data)
        case .idle, .loading:
            dailyChart(.placeholder)
                .redactedWhileLoading(true)
        }
    }

    private func dailyChart(_ data: DailySpending) -> some View {
        let accent = DS.Palette.accent
        let budgetValue = budget.map(\.doubleValue).flatMap { $0 > 0 ? $0 : nil }
        let peak = (data.current.map(\.amount.doubleValue) + data.previous.map(\.amount.doubleValue) + [budgetValue ?? 0]).max() ?? 0
        let top = max(peak, 1) * 1.1
        let dayCount = max(data.dayCount, 2)
        let calendar = Calendar.autoupdatingCurrent
        let labels = ScrubbableChartMath.labelIndices(count: dayCount, slots: 4).map { index in
            (calendar.date(byAdding: .day, value: index, to: data.monthStart) ?? data.monthStart)
                .formatted(.dateTime.month(.abbreviated).day())
        }
        let selected = selectedDay.flatMap { day in data.current.first { $0.day == day } }

        return VStack(spacing: 0) {
            Chart {
                if let budgetValue {
                    RuleMark(y: .value("Budget", budgetValue))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: Self.ruleDash))
                        .annotation(position: .top, alignment: .leading, spacing: 2) {
                            Text("Budget")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }

                ForEach(data.previous) { point in
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Spent", point.amount.doubleValue),
                        series: .value("Month", "previous")
                    )
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 4]))
                    .interpolationMethod(.monotone)
                }

                ForEach(data.current) { point in
                    AreaMark(
                        x: .value("Day", point.day),
                        y: .value("Spent", point.amount.doubleValue)
                    )
                    .foregroundStyle(accent.opacity(DS.chartAreaOpacity))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Spent", point.amount.doubleValue),
                        series: .value("Month", "current")
                    )
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }

                if let selected {
                    RuleMark(x: .value("Day", selected.day))
                        .foregroundStyle(accent.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                    PointMark(x: .value("Day", selected.day), y: .value("Spent", selected.amount.doubleValue))
                        .symbol { HomeChartDot(color: accent, size: 9) }
                } else if let last = data.current.last {
                    PointMark(x: .value("Day", last.day), y: .value("Spent", last.amount.doubleValue))
                        .symbol { HomeChartDot(color: accent, size: 8) }
                }
            }
            .chartXScale(domain: 1...dayCount)
            .chartYScale(domain: 0...top)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartXSelection(value: $rawDay)
            .frame(height: Self.chartHeight - Self.labelRowHeight)
            .chartDrawIn(trigger: AnyHashable(period), interacting: rawDay != nil)

            ChartDateLabels(labels: labels)
                .frame(height: Self.labelRowHeight, alignment: .bottom)
        }
        .frame(height: Self.chartHeight)
        .onChange(of: rawDay) { _, raw in
            guard let raw, !data.current.isEmpty else {
                selectedDay = nil
                return
            }
            let snapped = min(max(raw, 1), data.current.count)
            if snapped != selectedDay { selectedDay = snapped }
        }
        .onChange(of: period) { _, _ in rawDay = nil }
        .sensoryFeedback(.selection, trigger: selectedDay) { _, new in new != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Spending over time"))
        .accessibilityValue(Text(verbatim: data.current.last.map {
            MoneyFormat.string($0.amount, currencyCode: currencyCode)
        } ?? ""))
    }

    // MARK: Longer periods: monthly bars

    @ViewBuilder
    private var bucketContent: some View {
        switch buckets {
        case .failed(let error):
            ErrorRow(ErrorMessage.message(for: error), retry: retry)
        case .loaded(let rows) where rows.allSatisfy({ $0.amount == 0 }):
            emptyState
        case .loaded(let rows):
            barChart(rows)
        case .idle, .loading:
            barChart(SpendingBucket.placeholder)
                .redactedWhileLoading(true)
        }
    }

    private func barChart(_ rows: [SpendingBucket]) -> some View {
        let accent = DS.Palette.accent
        let average = rows.isEmpty ? 0 : rows.reduce(0) { $0 + $1.amount.doubleValue } / Double(rows.count)
        let averageText = average.formatted(
            .currency(code: currencyCode).notation(.compactName).precision(.significantDigits(1...3))
        )

        return Chart {
            ForEach(rows) { bucket in
                BarMark(
                    x: .value("Month", bucket.id),
                    y: .value("Spent", bucket.amount.doubleValue),
                    width: .ratio(0.5)
                )
                .cornerRadius(4)
                .foregroundStyle(accent.opacity(selectedBucketID == nil || selectedBucketID == bucket.id ? 1 : 0.35))
                .accessibilityLabel(Text(verbatim: bucket.label))
                .accessibilityValue(Text(verbatim: MoneyFormat.string(bucket.amount, currencyCode: currencyCode)))
            }

            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: Self.ruleDash))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("Avg \(averageText)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXSelection(value: $selectedBucketID)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: rows.map(\.id)) { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let date = CalendarDate(string: id)?.startDate() {
                        Text(verbatim: date.formatted(.dateTime.month(.narrow)))
                    }
                }
                .font(.caption2)
            }
        }
        .frame(height: Self.chartHeight)
        .sensoryFeedback(.selection, trigger: selectedBucketID) { _, new in new != nil }
    }

    private var emptyState: some View {
        Text("No spending in this period.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}

/// The chart's point marker: solid, ringed in the background colour so it reads on the line.
private struct HomeChartDot: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2))
    }
}

extension SpendingBucket {
    /// "October 2026".
    var label: String {
        start.startDate().formatted(.dateTime.month(.wide).year())
    }

    static let placeholder: [SpendingBucket] = {
        let first = MonthPeriod(containing: .now).firstDay
        return (0..<6).map { index in
            SpendingBucket(start: first.shifted(months: index - 5), amount: Decimal(300 + (index % 3) * 120))
        }
    }()
}

extension DailySpending {
    /// A steady climb for the loading state.
    static let placeholder: DailySpending = {
        let calendar = Calendar.autoupdatingCurrent
        let start = BudgetMonth(containing: .now).startDate(calendar: calendar)
        func points(count: Int, perDay: Int) -> [DailySpendingPoint] {
            (1...count).map { day in
                DailySpendingPoint(
                    day: day,
                    date: calendar.date(byAdding: .day, value: day - 1, to: start) ?? start,
                    amount: Decimal(day * perDay)
                )
            }
        }
        return DailySpending(
            current: points(count: 14, perDay: 40),
            previous: points(count: 30, perDay: 36),
            dayCount: 30,
            monthStart: start
        )
    }()
}
