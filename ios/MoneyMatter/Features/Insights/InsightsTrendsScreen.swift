import Charts
import MoneyMatterKit
import SwiftUI

/// The trends comparison report: a metric (expenses, income, or savings) over a period,
/// compared month by month and cumulatively with the equally long period before it, plus a
/// category breakdown with changes.
struct InsightsTrendsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(ReferenceDataStore.self) private var referenceData

    @AppStorage("insights.trends.metric") private var metricRaw = TrendsMetric.expenses.rawValue
    @State private var period = InsightsTrendsScreen.defaultPeriod()
    @State private var filters = TrendsFilterSelection()
    @State private var isShowingFilters = false
    @State private var cumulative: LoadState<CumulativeReport> = .idle
    @State private var monthly: LoadState<CashFlowReport> = .idle
    @State private var categories: LoadState<CategoryComparison> = .idle
    @State private var generation = 0

    init() {}

    struct CategoryComparison: Equatable {
        var current: [CategorySpending]
        var previous: [CategorySpending]
    }

    private struct LoadKey: Hashable {
        let period: InsightsCashFlowPeriod
        let metric: TrendsMetric
        let filters: TrendsFilterSelection
    }

    private var metric: TrendsMetric { TrendsMetric(rawValue: metricRaw) ?? .expenses }
    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }
    private var digits: Int? { session.baseCurrency?.currency?.digits }

    /// The last twelve months up to today, as on the web.
    static func defaultPeriod(now: Date = .now) -> InsightsCashFlowPeriod {
        let start = Calendar.current.date(byAdding: .month, value: -12, to: now) ?? now
        return InsightsCashFlowPeriod(from: CalendarDate(date: start), to: CalendarDate(date: now))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls
                summaryCard
                monthlyCard
                cumulativeCard
                if metric != .savings {
                    breakdownCard
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingFilters = true
                } label: {
                    Image(systemName: filters.activeCount > 0
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                }
                .badge(filters.activeCount)
                .accessibilityLabel(Text("Filters"))
                .accessibilityValue(Text("\(filters.activeCount) active"))
            }
        }
        .sheet(isPresented: $isShowingFilters) {
            InsightsTrendsFiltersSheet(filters: $filters)
        }
        .refreshable { await loadAll() }
        .task(id: LoadKey(period: period, metric: metric, filters: filters)) { await loadAll() }
        .task { await referenceData.loadIfNeeded() }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            InsightsCashFlowPeriodMenu(period: $period)
            Picker("Metric", selection: $metricRaw) {
                Text("Expenses").tag(TrendsMetric.expenses.rawValue)
                Text("Income").tag(TrendsMetric.income.rawValue)
                Text("Savings").tag(TrendsMetric.savings.rawValue)
            }
            .pickerStyle(.segmented)
        }
    }

    private var metricTitle: LocalizedStringKey {
        switch metric {
        case .income: "Income"
        case .savings: "Savings"
        case .expenses, .unknown: "Expenses"
        }
    }

    private var metricColor: Color {
        switch metric {
        case .income: .green
        case .savings: .blue
        case .expenses, .unknown: .red
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryCard: some View {
        switch cumulative {
        case .failed(let error):
            InlineRetryView(ErrorMessage.message(for: error)) { await loadCumulative() }
                .cardStyle()
        default:
            let report = cumulative.value
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metricTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(MoneyFormat.string(report?.currentPeriod.total ?? 0, currencyCode: currencyCode, digits: digits))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(metric == .expenses ? Color.primary : metricColor)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Comparison Period")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(MoneyFormat.string(report?.previousPeriod.total ?? 0, currencyCode: currencyCode, digits: digits))
                            .font(.title3)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    InsightsCashFlowChangeBadge(
                        change: Int(InsightsCashFlowMath.double(report?.percentChange ?? 0).rounded()),
                        increaseIsGood: metric.increaseIsGood
                    )
                    Text("vs previous period")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .cardStyle()
            .redactedWhileLoading(report == nil)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Monthly comparison

    private struct MonthlyBar: Identifiable {
        let id: String
        let date: Date
        let series: String
        let colorHex: String?
        let value: Double
    }

    private func metricValue(_ period: CashFlowPeriod) -> Decimal {
        switch metric {
        case .income: period.income
        case .savings: period.netFlow
        case .expenses, .unknown: period.expenses
        }
    }

    private func categoryValue(_ category: CashFlowCategoryAmount) -> Decimal {
        metric == .income ? category.incomeAmount : category.expenseAmount
    }

    /// Categories with a non-zero amount for the metric in any month, in first-seen order.
    private func chartCategories(_ report: CashFlowReport) -> [CashFlowCategoryAmount] {
        guard metric != .savings else { return [] }
        return report.categoryTotals.filter { total in
            report.periods.contains { period in
                period.categories.contains { $0.categoryId == total.categoryId && categoryValue($0) != 0 }
            }
        }
    }

    @ViewBuilder
    private var monthlyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly Comparison")
                .font(.headline)
            switch monthly {
            case .idle, .loading:
                RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill))
                    .frame(height: 220)
                    .redactedWhileLoading(true)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await loadMonthly() }
            case .loaded(let report):
                if report.periods.allSatisfy({ metricValue($0) == 0 }) {
                    emptyChart
                } else {
                    monthlyChart(report)
                }
            }
        }
        .cardStyle()
    }

    private func monthlyChart(_ report: CashFlowReport) -> some View {
        let stackCategories = chartCategories(report)
        let isStacked = stackCategories.count > 1
        let bars: [MonthlyBar] = report.periods.flatMap { period -> [MonthlyBar] in
            let date = period.periodStart.startDate()
            if isStacked {
                return period.categories
                    .filter { category in stackCategories.contains { $0.categoryId == category.categoryId } }
                    .map {
                        MonthlyBar(
                            id: "\(period.id)-\($0.categoryId)",
                            date: date,
                            series: $0.name,
                            colorHex: $0.color,
                            value: InsightsCashFlowMath.double(categoryValue($0))
                        )
                    }
            }
            return [MonthlyBar(id: "\(period.id)", date: date, series: "", colorHex: nil, value: InsightsCashFlowMath.double(metricValue(period)))]
        }
        let values = report.periods.map { InsightsCashFlowMath.double(metricValue($0)) }
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)

        return VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(bars) { bar in
                    if isStacked {
                        BarMark(x: .value("Month", bar.date, unit: .month), y: .value("Amount", bar.value))
                            .foregroundStyle(by: .value("Category", bar.series))
                    } else {
                        BarMark(x: .value("Month", bar.date, unit: .month), y: .value("Amount", bar.value))
                            .foregroundStyle(bar.value < 0 ? Color.red.opacity(0.8) : metricColor.opacity(0.85))
                    }
                }
                if values.count > 1 {
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .chartForegroundStyleScale(
                domain: stackCategories.map(\.name),
                range: stackCategories.map { Color(hex: $0.color) ?? .gray }
            )
            .chartLegend(.hidden)
            .chartYAxis { compactAxis }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: max(1, report.periods.count / 6))) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(height: 220)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Monthly comparison chart"))
            .accessibilityValue(Text(monthlySummary(values: values, average: average)))

            legend(stackCategories: isStacked ? stackCategories : [], hasAverage: values.count > 1)
        }
    }

    private func monthlySummary(values: [Double], average: Double) -> String {
        let averageText = MoneyFormat.string(Decimal(average), currencyCode: currencyCode, digits: digits)
        return String(localized: "\(values.count) months, average \(averageText)")
    }

    @ViewBuilder
    private func legend(stackCategories: [CashFlowCategoryAmount], hasAverage: Bool) -> some View {
        let hidden = hiddenCategories
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if stackCategories.isEmpty {
                    legendChip(color: metricColor, title: Text(metricTitle))
                }
                ForEach(stackCategories) { category in
                    Button {
                        filters = filters.hidingCategory(category.categoryId)
                    } label: {
                        legendChip(color: Color(hex: category.color) ?? .gray, title: Text(category.name))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Hides this category from the report"))
                }
                ForEach(hidden) { category in
                    Button {
                        filters = filters.showingCategory(category.id)
                    } label: {
                        Label {
                            Text(category.name).strikethrough()
                        } icon: {
                            Image(systemName: "eye.slash")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Show \(category.name)"))
                }
                if hasAverage {
                    legendChip(color: .orange, title: Text("Average"))
                }
            }
        }
    }

    private func legendChip(color: Color, title: Text) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            title
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemFill), in: .capsule)
    }

    private var hiddenCategories: [MoneyMatterKit.Category] {
        guard metric != .savings, filters.categories.mode == .exclude else { return [] }
        return filters.categories.ids.compactMap { referenceData.category(id: $0) }
    }

    private var emptyChart: some View {
        ContentUnavailableView {
            Label("No Data", systemImage: "chart.bar")
        } description: {
            Text("There are no transactions for this metric in the selected period.")
        } actions: {
            if filters.activeCount > 0 {
                Button("Clear Filters") { filters = TrendsFilterSelection() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var compactAxis: some AxisContent {
        AxisMarks { value in
            AxisGridLine()
            AxisValueLabel {
                if let amount = value.as(Double.self) {
                    Text(MoneyFormat.compactString(Decimal(amount), currencyCode: currencyCode))
                }
            }
        }
    }

    // MARK: Cumulative

    private struct CumulativePoint: Identifiable {
        let id: String
        let month: Int
        let series: String
        let value: Double
    }

    @ViewBuilder
    private var cumulativeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cumulative")
                .font(.headline)
            switch cumulative {
            case .idle, .loading:
                RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill))
                    .frame(height: 220)
                    .redactedWhileLoading(true)
            case .failed:
                Text("Couldn't load the cumulative chart.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .loaded(let report):
                if report.hasData {
                    cumulativeChart(report)
                } else {
                    emptyChart
                }
            }
        }
        .cardStyle()
    }

    private func cumulativeChart(_ report: CumulativeReport) -> some View {
        let currentName = String(localized: "This Period")
        let previousName = String(localized: "Previous Period")
        let points = report.currentPeriod.data.map {
            CumulativePoint(id: "c\($0.month)", month: $0.month, series: currentName, value: InsightsCashFlowMath.double($0.value))
        } + report.previousPeriod.data.map {
            CumulativePoint(id: "p\($0.month)", month: $0.month, series: previousName, value: InsightsCashFlowMath.double($0.value))
        }
        let labels = Dictionary(
            (report.currentPeriod.data + report.previousPeriod.data).map { ($0.month, $0.monthLabel) },
            uniquingKeysWith: { first, _ in first }
        )
        let months = labels.keys.sorted()

        return VStack(alignment: .leading, spacing: 8) {
            Chart(points) { point in
                LineMark(x: .value("Month", point.month), y: .value("Total", point.value))
                    .foregroundStyle(by: .value("Period", point.series))
                    .lineStyle(point.series == previousName ? StrokeStyle(lineWidth: 2, dash: [5, 4]) : StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale([currentName: metricColor, previousName: Color.secondary])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartYAxis { compactAxis }
            .chartXAxis {
                AxisMarks(values: months.enumerated().filter { $0.offset % max(1, months.count / 6) == 0 }.map(\.element)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let month = value.as(Int.self) {
                            Text(verbatim: labels[month] ?? "")
                        }
                    }
                }
            }
            .frame(height: 220)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Cumulative chart"))
            .accessibilityValue(Text(cumulativeSummary(report)))
        }
    }

    private func cumulativeSummary(_ report: CumulativeReport) -> String {
        let current = MoneyFormat.string(report.currentPeriod.total, currencyCode: currencyCode, digits: digits)
        let previous = MoneyFormat.string(report.previousPeriod.total, currencyCode: currencyCode, digits: digits)
        return String(localized: "This period \(current), previous period \(previous)")
    }

    // MARK: Category breakdown

    @ViewBuilder
    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            (metric == .income ? Text("Income by Category") : Text("Spending by Category"))
                .font(.headline)
            switch categories {
            case .idle, .loading:
                ForEach(0..<4, id: \.self) { _ in
                    InsightsTrendsBreakdownRow(
                        name: "Category", colorHex: nil, amount: 100, share: 0.25, change: 10,
                        increaseIsGood: metric.increaseIsGood, currencyCode: currencyCode, digits: digits
                    )
                }
                .redactedWhileLoading(true)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await loadCategories() }
            case .loaded(let comparison):
                InsightsTrendsBreakdownList(
                    comparison: comparison,
                    increaseIsGood: metric.increaseIsGood,
                    currencyCode: currencyCode,
                    digits: digits,
                    hide: { filters = filters.hidingCategory($0) }
                )
            }
        }
        .cardStyle()
    }

    // MARK: Loading

    private func loadAll() async {
        generation += 1
        async let cumulativeLoad: Void = loadCumulative()
        async let monthlyLoad: Void = loadMonthly()
        async let categoriesLoad: Void = loadCategories()
        _ = await (cumulativeLoad, monthlyLoad, categoriesLoad)
    }

    private func loadCumulative() async {
        guard let client = services.client else { return }
        let token = generation
        if cumulative.value == nil { cumulative = .loading }
        let endpoint = Endpoints.cumulativeData(from: period.from, to: period.to, metric: metric, filters: filters.reportFilters)
        do {
            let value = try await client.send(endpoint)
            guard token == generation else { return }
            cumulative = .loaded(value)
        } catch {
            guard token == generation, cumulative.value == nil || !(error is CancellationError) else { return }
            cumulative = .failed(APIError(error))
        }
    }

    private func loadMonthly() async {
        guard let client = services.client else { return }
        let token = generation
        if monthly.value == nil { monthly = .loading }
        // Whole months, so a partial first or last month still shows its full bar.
        let from = MonthPeriod(containing: period.from.startDate()).firstDay
        let to = MonthPeriod(containing: period.to.startDate()).lastDay()
        let endpoint = Endpoints.cashFlow(from: from, to: to, granularity: .monthly, filters: filters.reportFilters)
        do {
            let value = try await client.send(endpoint)
            guard token == generation else { return }
            monthly = .loaded(value)
        } catch {
            guard token == generation, monthly.value == nil || !(error is CancellationError) else { return }
            monthly = .failed(APIError(error))
        }
    }

    private func loadCategories() async {
        guard let client = services.client, let type = metric.categoryType else { return }
        let token = generation
        if categories.value == nil { categories = .loading }
        let range = period
        let previousRange = previousMonthsRange(range)
        let reportFilters = filters.reportFilters
        do {
            async let current = client.send(
                Endpoints.filteredSpendingsByCategories(from: range.from, to: range.to, type: type, filters: reportFilters)
            )
            async let previous = client.send(
                Endpoints.filteredSpendingsByCategories(
                    from: previousRange.from, to: previousRange.to, type: type, filters: reportFilters
                )
            )
            let value = try await CategoryComparison(current: current, previous: previous)
            guard token == generation else { return }
            categories = .loaded(value)
        } catch {
            guard token == generation, categories.value == nil || !(error is CancellationError) else { return }
            categories = .failed(APIError(error))
        }
    }

    /// The same number of calendar months right before the period, as the cumulative chart uses.
    private func previousMonthsRange(_ range: InsightsCashFlowPeriod) -> InsightsCashFlowPeriod {
        let months = (range.to.year - range.from.year) * 12 + (range.to.month - range.from.month) + 1
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .month, value: -months, to: range.from.startDate()) ?? range.from.startDate()
        let to = calendar.date(byAdding: .month, value: -months, to: range.to.startDate()) ?? range.to.startDate()
        return InsightsCashFlowPeriod(from: CalendarDate(date: from), to: CalendarDate(date: to))
    }
}

// MARK: - Breakdown

private struct InsightsTrendsBreakdownList: View {
    let comparison: InsightsTrendsScreen.CategoryComparison
    let increaseIsGood: Bool
    let currencyCode: String
    let digits: Int?
    let hide: (String) -> Void
    @State private var showsAll = false

    private struct Row: Identifiable {
        let id: String
        let name: String
        let color: String
        let amount: Decimal
        let share: Double
        let change: Int?
    }

    private var rows: [Row] {
        let positive = comparison.current.filter { $0.amount > 0 }
        let total = positive.reduce(Decimal.zero) { $0 + $1.amount }
        let previousByID = Dictionary(comparison.previous.map { ($0.id, $0.amount) }, uniquingKeysWith: { first, _ in first })
        return positive.map { category in
            let previous = previousByID[category.id]
            let change: Int?
            if let previous, previous > 0 {
                change = Int(InsightsCashFlowMath.double((category.amount - previous) / previous * 100).rounded())
            } else {
                change = 100
            }
            return Row(
                id: category.id,
                name: category.name,
                color: category.color,
                amount: category.amount,
                share: total > 0 ? InsightsCashFlowMath.double(category.amount / total) : 0,
                change: change
            )
        }
    }

    var body: some View {
        let all = rows
        if all.isEmpty {
            ContentUnavailableView(
                "No Categories",
                systemImage: "square.grid.2x2",
                description: Text("No category had activity in this period.")
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(showsAll ? all : Array(all.prefix(10))) { row in
                    InsightsTrendsBreakdownRow(
                        name: row.name,
                        colorHex: row.color,
                        amount: row.amount,
                        share: row.share,
                        change: row.change,
                        increaseIsGood: increaseIsGood,
                        currencyCode: currencyCode,
                        digits: digits
                    )
                    .contextMenu {
                        Button("Hide from Report", systemImage: "eye.slash") { hide(row.id) }
                    }
                }
                if all.count > 10 {
                    Button(showsAll ? "Show Less" : "Show All (\(all.count))") {
                        withAnimation { showsAll.toggle() }
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

private struct InsightsTrendsBreakdownRow: View {
    let name: String
    let colorHex: String?
    let amount: Decimal
    let share: Double
    let change: Int?
    let increaseIsGood: Bool
    let currencyCode: String
    let digits: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: colorHex) ?? .gray).frame(width: 10, height: 10)
                Text(name).font(.subheadline).lineLimit(1)
                Spacer(minLength: 8)
                InsightsCashFlowChangeBadge(change: change, increaseIsGood: increaseIsGood)
                Text(MoneyFormat.string(amount, currencyCode: currencyCode, digits: digits))
                    .font(.subheadline)
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule().fill(Color(hex: colorHex) ?? .gray)
                            .frame(width: max(2, proxy.size.width * share))
                    }
                }
                .frame(height: 4)
                Text(verbatim: "\(Int((share * 100).rounded()))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Filters

private struct InsightsTrendsFiltersSheet: View {
    @Binding var filters: TrendsFilterSelection
    @Environment(\.dismiss) private var dismiss
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var draft = TrendsFilterSelection()

    var body: some View {
        NavigationStack {
            Form {
                groupSection(
                    title: "Categories",
                    group: $draft.categories,
                    options: referenceData.categories.map { .init(id: $0.id, name: $0.name, colorHex: $0.color) }
                )
                groupSection(
                    title: "Payees",
                    group: $draft.payees,
                    options: referenceData.payees.map { .init(id: $0.id, name: $0.name, colorHex: $0.logoColor) }
                )
                groupSection(
                    title: "Tags",
                    group: $draft.tags,
                    options: referenceData.tags.map { .init(id: $0.id, name: $0.name, colorHex: $0.color) }
                )
                Section("Accounts") {
                    NavigationLink {
                        InsightsTrendsMultiSelectList(
                            title: "Accounts",
                            options: referenceData.accounts.map { .init(id: $0.id, name: $0.name, colorHex: nil) },
                            selection: $draft.accountIds
                        )
                    } label: {
                        LabeledContent("Accounts", value: selectionSummary(draft.accountIds))
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filters = draft
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset All", role: .destructive) {
                        draft = TrendsFilterSelection()
                    }
                    .disabled(draft.activeCount == 0)
                }
            }
        }
        .onAppear { draft = filters }
    }

    private func groupSection(
        title: LocalizedStringKey,
        group: Binding<TrendsFilterGroup>,
        options: [InsightsTrendsMultiSelectList.Option]
    ) -> some View {
        Section(title) {
            Picker("Mode", selection: group.mode) {
                Text("Include").tag(TrendsFilterGroup.Mode.include)
                Text("Exclude").tag(TrendsFilterGroup.Mode.exclude)
            }
            .pickerStyle(.segmented)
            NavigationLink {
                InsightsTrendsMultiSelectList(title: title, options: options, selection: group.ids)
            } label: {
                LabeledContent(title, value: selectionSummary(group.wrappedValue.ids))
            }
        }
    }

    private func selectionSummary(_ ids: [String]) -> String {
        ids.isEmpty ? String(localized: "All") : String(localized: "\(ids.count) selected")
    }
}

private struct InsightsTrendsMultiSelectList: View {
    struct Option: Identifiable {
        let id: String
        let name: String
        let colorHex: String?
    }

    let title: LocalizedStringKey
    let options: [Option]
    @Binding var selection: [String]
    @State private var query = ""

    private var filtered: [Option] {
        let sorted = options.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            ForEach(filtered) { option in
                Button {
                    if let index = selection.firstIndex(of: option.id) {
                        selection.remove(at: index)
                    } else {
                        selection.append(option.id)
                    }
                } label: {
                    HStack {
                        if let hex = option.colorHex, let color = Color(hex: hex) {
                            Circle().fill(color).frame(width: 10, height: 10)
                        }
                        Text(option.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(option.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .accessibilityAddTraits(selection.contains(option.id) ? .isSelected : [])
            }
        }
        .searchable(text: $query)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { selection = [] }
                    .disabled(selection.isEmpty)
            }
        }
    }
}
