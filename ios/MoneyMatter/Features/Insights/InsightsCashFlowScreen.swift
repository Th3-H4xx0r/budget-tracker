import Charts
import MoneyMatterKit
import SwiftUI

// MARK: - Shared period controls (also used by the trends report)

/// A day range for the cash flow and trends reports.
struct InsightsCashFlowPeriod: Hashable {
    var from: CalendarDate
    var to: CalendarDate

    /// The web's period presets.
    enum Preset: CaseIterable, Identifiable {
        case last3Months, last6Months, last12Months, thisYear, previousYear, allTime

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .last3Months: "Last 3 Months"
            case .last6Months: "Last 6 Months"
            case .last12Months: "Last 12 Months"
            case .thisYear: "This Year"
            case .previousYear: "Previous Year"
            case .allTime: "All Time"
            }
        }
    }

    static func preset(_ preset: Preset, earliest: CalendarDate? = nil, now: Date = .now) -> InsightsCashFlowPeriod {
        let today = CalendarDate(date: now)
        let thisMonth = MonthPeriod(containing: now)
        switch preset {
        case .last3Months: return .init(from: monthStart(monthsBack: 2, now: now), to: thisMonth.lastDay())
        case .last6Months: return .init(from: monthStart(monthsBack: 5, now: now), to: thisMonth.lastDay())
        case .last12Months: return .init(from: monthStart(monthsBack: 11, now: now), to: thisMonth.lastDay())
        case .thisYear: return .init(from: CalendarDate(year: today.year, month: 1, day: 1), to: today)
        case .previousYear:
            return .init(
                from: CalendarDate(year: today.year - 1, month: 1, day: 1),
                to: CalendarDate(year: today.year - 1, month: 12, day: 31)
            )
        case .allTime: return .init(from: earliest ?? CalendarDate(year: 2000, month: 1, day: 1), to: today)
        }
    }

    /// The current month, for the money flow section.
    static func thisMonth(now: Date = .now) -> InsightsCashFlowPeriod {
        let month = MonthPeriod(containing: now)
        return .init(from: month.firstDay, to: month.lastDay())
    }

    static func monthStart(monthsBack: Int, now: Date = .now) -> CalendarDate {
        let shifted = Calendar.current.date(byAdding: .month, value: -monthsBack, to: now) ?? now
        return MonthPeriod(containing: shifted).firstDay
    }

    /// The equally long range right before this one.
    var previous: InsightsCashFlowPeriod {
        let days = max(1, dayCount)
        return .init(from: from.adding(days: -days), to: from.adding(days: -1))
    }

    var dayCount: Int {
        let calendar = Calendar.current
        let start = from.startDate(in: calendar)
        let end = to.startDate(in: calendar)
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    var label: String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        return "\(from.startDate().formatted(style)) – \(to.startDate().formatted(style))"
    }
}

/// A menu of period presets plus a custom range sheet.
struct InsightsCashFlowPeriodMenu: View {
    @Binding var period: InsightsCashFlowPeriod
    var earliest: CalendarDate?
    @State private var isEditingCustom = false

    var body: some View {
        Menu {
            ForEach(InsightsCashFlowPeriod.Preset.allCases) { preset in
                Button(preset.title) {
                    period = .preset(preset, earliest: earliest)
                }
            }
            Divider()
            Button("Custom Range…", systemImage: "calendar") {
                isEditingCustom = true
            }
        } label: {
            Label(period.label, systemImage: "calendar")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(Text("Period: \(period.label)"))
        .sheet(isPresented: $isEditingCustom) {
            InsightsCashFlowCustomRangeSheet(period: $period)
                .presentationDetents([.medium])
        }
    }
}

private struct InsightsCashFlowCustomRangeSheet: View {
    @Binding var period: InsightsCashFlowPeriod
    @Environment(\.dismiss) private var dismiss
    @State private var from = Date.now
    @State private var to = Date.now

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        period = InsightsCashFlowPeriod(from: CalendarDate(date: from), to: CalendarDate(date: to))
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            from = period.from.startDate()
            to = period.to.startDate()
        }
    }
}

/// A "▲ 12%" pill, green when the change is good news and red when it isn't.
struct InsightsCashFlowChangeBadge: View {
    let change: Int?
    var increaseIsGood = true
    /// "%" for relative changes, "pp" for percentage-point differences.
    var unit = "%"

    var body: some View {
        if let change {
            let symbol = change == 0 ? "minus" : (change > 0 ? "arrow.up" : "arrow.down")
            let isGood = change == 0 ? nil : (change > 0) == increaseIsGood
            Label {
                Text(verbatim: "\(abs(change))\(unit)")
                    .monospacedDigit()
            } icon: {
                Image(systemName: symbol)
            }
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isGood.map { $0 ? Color.green : Color.red } ?? .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: .capsule)
            .accessibilityLabel(Text(change > 0 ? "Up \(abs(change))\(unit)" : (change < 0 ? "Down \(abs(change))\(unit)" : "No change")))
        }
    }
}

/// Percent change between two totals, rounded, as on the web.
enum InsightsCashFlowMath {
    static func percentChange(current: Decimal?, previous: Decimal?) -> Int? {
        guard let current, let previous else { return nil }
        if previous == 0 { return current > 0 ? 100 : (current < 0 ? -100 : 0) }
        let ratio = NSDecimalNumber(decimal: (current - previous) / abs(previous) * 100).doubleValue
        return Int(ratio.rounded())
    }

    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

// MARK: - Screen

/// The cash flow report: income versus expenses per bucket, totals with a comparison to the
/// previous period, and where the money went.
struct InsightsCashFlowScreen: View {
    enum ChartKind: String, CaseIterable, Identifiable {
        case mirrored, stacked, grouped
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .mirrored: "Mirrored"
            case .stacked: "Stacked"
            case .grouped: "Grouped"
            }
        }

        var symbol: String {
            switch self {
            case .mirrored: "chart.bar.xaxis"
            case .stacked: "square.stack"
            case .grouped: "chart.bar"
            }
        }
    }

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session

    @AppStorage("insights.cashFlow.granularity") private var granularityRaw = CashFlowGranularity.monthly.rawValue
    @AppStorage("insights.cashFlow.chartKind") private var chartKindRaw = ChartKind.mirrored.rawValue
    @AppStorage("insights.cashFlow.movingAverage") private var showsMovingAverage = true
    @State private var period = InsightsCashFlowPeriod.preset(.last12Months)
    @State private var earliest: CalendarDate?
    @State private var report: LoadState<CashFlowReport> = .idle
    @State private var previous: CashFlowReport?
    @State private var generation = 0

    init() {}

    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }
    private var digits: Int? { session.baseCurrency?.currency?.digits }
    private var granularity: CashFlowGranularity { CashFlowGranularity(rawValue: granularityRaw) ?? .monthly }
    private var chartKind: ChartKind { ChartKind(rawValue: chartKindRaw) ?? .mirrored }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls
                content
                InsightsCashFlowMoneyFlowSection(currencyCode: currencyCode, digits: digits, earliest: earliest)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Cash Flow")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: LoadKey(period: period, granularity: granularity)) { await load() }
        .task { await loadEarliest() }
    }

    private struct LoadKey: Hashable {
        let period: InsightsCashFlowPeriod
        let granularity: CashFlowGranularity
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            InsightsCashFlowPeriodMenu(period: $period, earliest: earliest)
            Picker("Granularity", selection: $granularityRaw) {
                Text("Monthly").tag(CashFlowGranularity.monthly.rawValue)
                Text("Biweekly").tag(CashFlowGranularity.biweekly.rawValue)
                Text("Weekly").tag(CashFlowGranularity.weekly.rawValue)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch report {
        case .idle, .loading:
            summaryGrid(totals: .zero, previous: nil)
                .redactedWhileLoading(true)
            chartCard(periods: InsightsCashFlowScreen.placeholderPeriods)
                .redactedWhileLoading(true)
        case .failed(let error):
            InlineRetryView(ErrorMessage.message(for: error)) { await load() }
                .cardStyle()
        case .loaded(let value):
            summaryGrid(totals: value.totals, previous: previous?.totals)
            if value.isEmpty {
                ContentUnavailableView {
                    Label("No Cash Flow", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("There are no income or expense transactions in this period.")
                } actions: {
                    Button("Show Last 12 Months") { period = .preset(.last12Months) }
                        .buttonStyle(.bordered)
                }
                .cardStyle()
            } else {
                chartCard(periods: value.periods)
            }
        }
    }

    // MARK: Summary

    private func summaryGrid(totals: CashFlowTotals, previous: CashFlowTotals?) -> some View {
        let comparison = Text("vs \(period.previous.label)")
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            InsightsCashFlowSummaryTile(
                title: "Income",
                value: Text(MoneyFormat.string(totals.income, currencyCode: currencyCode, digits: digits)),
                tint: .green,
                change: InsightsCashFlowMath.percentChange(current: totals.income, previous: previous?.income),
                increaseIsGood: true,
                comparison: comparison
            )
            InsightsCashFlowSummaryTile(
                title: "Expenses",
                value: Text(MoneyFormat.string(totals.expenses, currencyCode: currencyCode, digits: digits)),
                tint: .primary,
                change: InsightsCashFlowMath.percentChange(current: totals.expenses, previous: previous?.expenses),
                increaseIsGood: false,
                comparison: comparison
            )
            InsightsCashFlowSummaryTile(
                title: "Net Savings",
                value: Text(MoneyFormat.string(totals.netFlow, currencyCode: currencyCode, digits: digits)),
                tint: totals.netFlow >= 0 ? .green : .red,
                change: InsightsCashFlowMath.percentChange(current: totals.netFlow, previous: previous?.netFlow),
                increaseIsGood: true,
                comparison: comparison
            )
            InsightsCashFlowSummaryTile(
                title: "Savings Rate",
                value: Text(verbatim: "\(Int(InsightsCashFlowMath.double(totals.savingsRate).rounded()))%"),
                tint: .blue,
                change: previous.map {
                    Int(InsightsCashFlowMath.double(totals.savingsRate - $0.savingsRate).rounded())
                },
                increaseIsGood: true,
                unit: "pp",
                comparison: comparison
            )
        }
    }

    // MARK: Chart

    private func chartCard(periods: [CashFlowPeriod]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Income vs Expenses")
                    .font(.headline)
                Spacer()
                Menu {
                    Picker("Chart Type", selection: $chartKindRaw) {
                        ForEach(ChartKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind.rawValue)
                        }
                    }
                    Toggle("Moving Average", isOn: $showsMovingAverage)
                } label: {
                    Image(systemName: chartKind.symbol)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Text("Chart Options"))
            }
            InsightsCashFlowChart(
                periods: periods,
                kind: chartKind,
                granularity: granularity,
                showsMovingAverage: showsMovingAverage,
                currencyCode: currencyCode
            )
            .frame(height: 260)
            HStack(spacing: 16) {
                legendItem(color: .green, title: "Income")
                legendItem(color: .red, title: "Expenses")
                legendItem(color: .blue, title: "Net")
                if showsMovingAverage {
                    legendItem(color: .orange, title: "Average")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func legendItem(color: Color, title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
        }
    }

    // MARK: Loading

    private func load() async {
        guard let client = services.client else { return }
        generation += 1
        let current = generation
        if report.value == nil { report = .loading }
        let range = period
        let bucket = granularity
        do {
            async let currentReport = client.send(Endpoints.cashFlow(from: range.from, to: range.to, granularity: bucket))
            async let previousReport = client.send(
                Endpoints.cashFlow(from: range.previous.from, to: range.previous.to, granularity: bucket)
            )
            let value = try await currentReport
            let before = try? await previousReport
            guard current == generation else { return }
            report = .loaded(value)
            previous = before
        } catch {
            guard current == generation else { return }
            if report.value == nil || !(error is CancellationError) {
                report = .failed(APIError(error))
            }
        }
    }

    private func loadEarliest() async {
        guard earliest == nil, let client = services.client else { return }
        earliest = try? await client.send(Endpoints.cashFlowEarliestTransactionDate())
    }

    private static let placeholderPeriods: [CashFlowPeriod] = (1...6).map { month in
        CashFlowPeriod(
            periodStart: CalendarDate(year: 2026, month: month, day: 1),
            periodEnd: CalendarDate(year: 2026, month: month, day: 28),
            income: Decimal(1000 + month * 100),
            expenses: Decimal(800 + month * 50),
            netFlow: Decimal(200 + month * 50)
        )
    }
}

private struct InsightsCashFlowSummaryTile: View {
    let title: LocalizedStringKey
    let value: Text
    let tint: Color
    let change: Int?
    var increaseIsGood = true
    var unit = "%"
    let comparison: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            value
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            InsightsCashFlowChangeBadge(change: change, increaseIsGood: increaseIsGood, unit: unit)
            comparison
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chart

private struct InsightsCashFlowChart: View {
    let periods: [CashFlowPeriod]
    let kind: InsightsCashFlowScreen.ChartKind
    let granularity: CashFlowGranularity
    let showsMovingAverage: Bool
    let currencyCode: String

    private struct Bar: Identifiable {
        let id: String
        let date: Date
        let series: String
        let value: Double
    }

    private var bars: [Bar] {
        periods.flatMap { period -> [Bar] in
            let date = period.periodStart.startDate()
            let income = InsightsCashFlowMath.double(period.income)
            let expenses = InsightsCashFlowMath.double(period.expenses)
            return [
                Bar(id: "\(period.id)-i", date: date, series: String(localized: "Income"), value: income),
                Bar(
                    id: "\(period.id)-e",
                    date: date,
                    series: String(localized: "Expenses"),
                    value: kind == .mirrored ? -expenses : expenses
                ),
            ]
        }
    }

    /// A trailing three-bucket average of net flow.
    private var movingAverage: [(date: Date, value: Double)] {
        periods.indices.map { index in
            let window = periods[max(0, index - 2)...index]
            let sum = window.reduce(0.0) { $0 + InsightsCashFlowMath.double($1.netFlow) }
            return (periods[index].periodStart.startDate(), sum / Double(window.count))
        }
    }

    private var unit: Calendar.Component {
        granularity == .monthly ? .month : .weekOfYear
    }

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                if kind == .grouped {
                    BarMark(x: .value("Period", bar.date, unit: unit), y: .value("Amount", bar.value))
                        .foregroundStyle(by: .value("Series", bar.series))
                        .position(by: .value("Series", bar.series))
                } else {
                    BarMark(x: .value("Period", bar.date, unit: unit), y: .value("Amount", bar.value))
                        .foregroundStyle(by: .value("Series", bar.series))
                }
            }
            ForEach(periods) { period in
                LineMark(
                    x: .value("Period", period.periodStart.startDate(), unit: unit),
                    y: .value("Net", InsightsCashFlowMath.double(period.netFlow)),
                    series: .value("Line", "net")
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.monotone)
                .symbol(.circle)
            }
            if showsMovingAverage, periods.count > 2 {
                ForEach(movingAverage, id: \.date) { point in
                    LineMark(
                        x: .value("Period", point.date, unit: unit),
                        y: .value("Average", point.value),
                        series: .value("Line", "average")
                    )
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
        }
        .chartForegroundStyleScale([
            String(localized: "Income"): Color.green,
            String(localized: "Expenses"): Color.red,
        ])
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(MoneyFormat.compactString(Decimal(amount), currencyCode: currencyCode))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: granularity == .monthly ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Income and expenses chart"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        let income = periods.reduce(Decimal.zero) { $0 + $1.income }
        let expenses = periods.reduce(Decimal.zero) { $0 + $1.expenses }
        return String(
            localized: "\(periods.count) periods. Income \(MoneyFormat.string(income, currencyCode: currencyCode)), expenses \(MoneyFormat.string(expenses, currencyCode: currencyCode))."
        )
    }
}

// MARK: - Money flow

/// Where the period's income came from and where it went: income sources, expenses, and
/// savings destinations (portfolios, venture deals, savings categories, cash).
private struct InsightsCashFlowMoneyFlowSection: View {
    let currencyCode: String
    let digits: Int?
    let earliest: CalendarDate?

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @AppStorage("insights.cashFlow.sourceLevel") private var sourceLevel = 2
    @AppStorage("insights.cashFlow.expenseLevel") private var expenseLevel = 1
    @AppStorage("insights.cashFlow.topN") private var topN = 8
    @State private var period = InsightsCashFlowPeriod.thisMonth()
    @State private var inputs: LoadState<Inputs> = .idle
    @State private var generation = 0

    struct Inputs {
        var spending: [CategorySpendingByType]
        var destinations: [CashFlowMoneyFlowDestination]
        var savingsCategoryIds: Set<String>
    }

    private var flow: CashFlowMoneyFlow? {
        inputs.value.map {
            CashFlowMoneyFlowBuilder.build(
                data: $0.spending,
                categories: referenceData.categories,
                destinations: $0.destinations,
                sourceLevel: sourceLevel,
                expenseLevel: expenseLevel,
                topN: topN,
                savingsCategoryIds: $0.savingsCategoryIds
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Money Flow")
                    .font(.headline)
                Spacer()
                settingsMenu
            }
            InsightsCashFlowPeriodMenu(period: $period, earliest: earliest)
            switch inputs {
            case .idle, .loading:
                columns(for: placeholderFlow)
                    .redactedWhileLoading(true)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await load() }
            case .loaded:
                if let flow, !flow.isEmpty {
                    columns(for: flow)
                } else {
                    ContentUnavailableView(
                        "No Money Flow",
                        systemImage: "arrow.left.arrow.right",
                        description: Text("Nothing came in or went out in this period.")
                    )
                }
            }
        }
        .cardStyle()
        .task(id: period) { await load() }
    }

    private var settingsMenu: some View {
        Menu {
            Picker("Income Detail", selection: $sourceLevel) {
                Text("Top-Level Categories").tag(1)
                Text("Subcategories").tag(2)
                Text("Deepest Level").tag(3)
            }
            Picker("Expense Detail", selection: $expenseLevel) {
                Text("Top-Level Categories").tag(1)
                Text("Subcategories").tag(2)
                Text("Deepest Level").tag(3)
            }
            Picker("Show Top", selection: $topN) {
                Text("5").tag(5)
                Text("8").tag(8)
                Text("12").tag(12)
                Text("All").tag(1000)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(Text("Money Flow Settings"))
    }

    @ViewBuilder
    private func columns(for flow: CashFlowMoneyFlow) -> some View {
        HStack(spacing: 8) {
            totalPill(title: "Income", amount: flow.income, tint: .green)
            totalPill(title: "Expenses", amount: flow.expenses, tint: .primary)
            totalPill(title: "Saved", amount: flow.savings, tint: .blue)
        }
        column(title: "Income Sources", nodes: flow.sources, tint: .green)
        column(title: "Spending", nodes: flow.expenseNodes, tint: .red)
        if !flow.savingsNodes.isEmpty {
            column(title: "Savings", nodes: flow.savingsNodes, tint: .blue)
        }
    }

    private func totalPill(title: LocalizedStringKey, amount: Decimal, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(MoneyFormat.string(amount, currencyCode: currencyCode, digits: digits))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func column(title: LocalizedStringKey, nodes: [CashFlowMoneyFlowNode], tint: Color) -> some View {
        if !nodes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(nodes) { node in
                    InsightsCashFlowFlowRow(node: node, fallback: tint, currencyCode: currencyCode, digits: digits)
                }
            }
            .padding(.top, 4)
        }
    }

    private var placeholderFlow: CashFlowMoneyFlow {
        CashFlowMoneyFlowBuilder.build(
            data: [
                CategorySpendingByType(id: "a", name: "Salary", color: "#34c759", income: 3000, expense: 0),
                CategorySpendingByType(id: "b", name: "Housing", color: "#ff3b30", income: 0, expense: 1200),
                CategorySpendingByType(id: "c", name: "Groceries", color: "#ff9500", income: 0, expense: 600),
            ],
            categories: []
        )
    }

    private func load() async {
        guard let client = services.client else { return }
        generation += 1
        let current = generation
        if inputs.value == nil { inputs = .loading }
        // The rollup needs the category tree, and the request scopes to the user's categories.
        await referenceData.loadIfNeeded()
        guard current == generation else { return }
        let range = period
        let categoryIds = referenceData.categories.map(\.id)
        do {
            async let spending = client.send(
                Endpoints.spendingsByCategoriesByType(from: range.from, to: range.to, categoryIds: categoryIds)
            )
            async let contributions = try? client.send(
                Endpoints.investmentContributions(from: range.from, to: range.to, granularity: .yearly)
            )
            async let ventures = try? client.send(Endpoints.ventureContributions(from: range.from, to: range.to))
            async let settings = try? client.send(Endpoints.cashFlowSavingsSettings())
            let rows = try await spending
            let destinations = Self.destinations(contributions: await contributions, ventures: await ventures)
            let savingsIDs = Set(await settings?.savingsCategoryIds ?? [])
            guard current == generation else { return }
            inputs = .loaded(Inputs(spending: rows, destinations: destinations, savingsCategoryIds: savingsIDs))
        } catch {
            guard current == generation else { return }
            if inputs.value == nil || !(error is CancellationError) {
                inputs = .failed(APIError(error))
            }
        }
    }

    /// Positive net contributions per portfolio, plus each venture deal.
    private static func destinations(
        contributions: InvestmentContributionsReport?,
        ventures: [InsightsVentureContribution]?
    ) -> [CashFlowMoneyFlowDestination] {
        var byPortfolio: [String: Decimal] = [:]
        for bucket in contributions?.buckets ?? [] {
            for slice in bucket.byPortfolio {
                byPortfolio[slice.portfolioId, default: 0] += slice.amount
            }
        }
        let portfolios = (contributions?.portfolios ?? []).map {
            CashFlowMoneyFlowDestination(id: $0.portfolioId, name: $0.name, value: byPortfolio[$0.portfolioId] ?? 0)
        }
        let deals = (ventures ?? []).map { CashFlowMoneyFlowDestination(id: $0.dealId, name: $0.name, value: $0.amount) }
        return (portfolios + deals).filter { $0.value > 0 }
    }
}

private struct InsightsCashFlowFlowRow: View {
    let node: CashFlowMoneyFlowNode
    let fallback: Color
    let currencyCode: String
    let digits: Int?
    @State private var isExpanded = false

    private var title: String {
        switch node.kind {
        case .other: String(localized: "Other")
        case .keptAsCash: String(localized: "Kept as Cash")
        case .deficit: String(localized: "From Reserves")
        case .regular: node.name
        }
    }

    private var color: Color {
        if node.kind == .deficit { return .orange }
        return Color(hex: node.color) ?? fallback
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if !node.children.isEmpty { withAnimation { isExpanded.toggle() } }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(.subheadline).lineLimit(1)
                        if let parent = node.parentName {
                            Text(parent).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if !node.children.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(MoneyFormat.string(node.value, currencyCode: currencyCode, digits: digits))
                        .font(.subheadline)
                        .monospacedDigit()
                    Text(verbatim: "\(Int((node.share * 100).rounded()))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 36, alignment: .trailing)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(node.children.isEmpty)
            GeometryReader { proxy in
                Capsule()
                    .fill(color.opacity(0.8))
                    .frame(width: max(2, proxy.size.width * node.share))
            }
            .frame(height: 4)
            .accessibilityHidden(true)
            if isExpanded {
                ForEach(node.children) { child in
                    InsightsCashFlowFlowRow(node: child, fallback: fallback, currencyCode: currencyCode, digits: digits)
                        .padding(.leading, 18)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
