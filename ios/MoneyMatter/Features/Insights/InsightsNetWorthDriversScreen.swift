import Charts
import MoneyMatterKit
import SwiftUI

/// Net worth drivers: how much of the window's growth was saved versus returned by the
/// market, per period and cumulatively, plus the growth-crossover target.
struct InsightsNetWorthDriversScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    @State private var period = InsightsNetWorthPeriod.default
    @State private var state: LoadState<NetWorthDriversReport> = .idle
    @State private var portfolios: LoadState<[InsightsPortfolioOption]> = .idle
    @State private var isInfoPresented = false
    @AppStorage("insights.netWorthDrivers.granularity") private var granularity = InvestmentReportGranularity.monthly
    /// Comma-joined portfolio ids; empty means every portfolio.
    @AppStorage("insights.netWorthDrivers.portfolioIds") private var storedPortfolioIds = ""

    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }
    private var digits: Int? { session.baseCurrency?.currency?.digits }

    private var selectedPortfolioIds: [String] {
        storedPortfolioIds.split(separator: ",").map(String.init)
    }

    private var enabledPortfolios: [InsightsPortfolioOption] {
        (portfolios.value ?? []).filter(\.isEnabled)
    }

    private struct RequestKey: Equatable {
        let from: CalendarDate
        let to: CalendarDate
        let granularity: InvestmentReportGranularity
        let portfolioIds: [String]
    }

    private var requestKey: RequestKey {
        RequestKey(from: period.from, to: period.to, granularity: granularity, portfolioIds: selectedPortfolioIds)
    }

    /// Only once the list loaded fine and is empty: a failed fetch must not claim the user
    /// has no portfolios.
    private var showsNoPortfolios: Bool {
        if case .loaded(let list) = portfolios { return list.isEmpty }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if showsNoPortfolios {
                    noPortfolios
                } else {
                    content
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Net Worth Drivers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !showsNoPortfolios {
                ToolbarItem(placement: .topBarTrailing) {
                    InsightsNetWorthPeriodMenu(period: $period)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    optionsMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("How This Is Calculated", systemImage: "info.circle") {
                        isInfoPresented = true
                    }
                }
            }
        }
        .sheet(isPresented: $isInfoPresented) {
            InsightsNetWorthDriversInfoSheet()
        }
        .refreshable {
            async let list: Void = loadPortfolios()
            async let report: Void = load()
            _ = await (list, report)
        }
        .task { await loadPortfolios() }
        .task(id: requestKey) { await load() }
    }

    // MARK: Content

    private var noPortfolios: some View {
        ContentUnavailableView {
            Label("No Investments Yet", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("This report splits your net worth change into what you saved and what your investments grew. Add a portfolio to start tracking growth.")
        } actions: {
            Button("Add a Portfolio") {
                router.show(.accounts, popToRoot: true)
                router.accountsPath.append(.investments)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            VStack(spacing: 16) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(verbatim: "Saved vs. grown")
                            .font(.headline)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                            .frame(height: 220)
                    }
                    .cardStyle()
                }
            }
            .redactedWhileLoading(true)
        case .failed:
            InlineRetryView(String(localized: "Couldn't load the report")) { await load() }
                .cardStyle()
        case .loaded(let report):
            if let degraded = report.degraded {
                InsightsNetWorthDegradedNotice(degraded: degraded)
            }
            if report.hasData {
                loaded(report)
            } else {
                ContentUnavailableView {
                    Label("Nothing to Show for This Period", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("Once you have income, expenses, or investments in this range, they'll appear here.")
                } actions: {
                    Button("Show Last 5 Years") { period = .preset(.last5Years) }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 40)
            }
        }
    }

    @ViewBuilder
    private func loaded(_ report: NetWorthDriversReport) -> some View {
        let series = report.cumulativeSeries

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                CardHeader("Saved vs. Grown")
                Text("Cumulative totals over the selected period.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let last = series.last {
                HStack(spacing: 16) {
                    totalLabel("Saved", amount: last.savedCumulative, color: InsightsNetWorthStyle.saved)
                    totalLabel("Grown", amount: last.grownCumulative, color: InsightsNetWorthStyle.grown)
                    totalLabel("Total Gained", amount: last.savedCumulative + last.grownCumulative, color: .primary)
                }
            }
            InsightsNetWorthDriversCumulativeChart(
                points: series,
                yearly: granularity == .yearly,
                currencyCode: currencyCode
            )
            if let line = allocationLine(report) {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                CardHeader("Per-Period Breakdown")
                Text("How much you saved and how much the market returned in each period.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            InsightsNetWorthDriversBreakdownChart(
                report: report,
                yearly: granularity == .yearly,
                currencyCode: currencyCode
            )
        }
        .cardStyle()

        if report.hasPortfolioActivity {
            let seeds = report.targetSeeds
            InsightsNetWorthTargetPanel(
                currentPortfolioValue: seeds.currentPortfolioValue,
                averageMonthlySavings: seeds.averageMonthlySavings,
                currencyCode: currencyCode,
                digits: digits
            )
        } else {
            Text("Investment growth appears once you add a portfolio with priced holdings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func totalLabel(_ title: LocalizedStringKey, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MoneyFormat.string(amount, currencyCode: currencyCode, digits: digits))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    /// Hidden under a portfolio filter: holdings are scoped but cash isn't, so the ratio
    /// would mix two scopes.
    private func allocationLine(_ report: NetWorthDriversReport) -> String? {
        guard selectedPortfolioIds.isEmpty else { return nil }
        let context = report.allocationContext()
        guard let current = context.currentSharePercent else { return nil }
        let share = Int(current.rounded())
        if let reference = context.referenceSharePercent, let date = context.referencePeriodEnd {
            let month = date.startDate().formatted(.dateTime.month(.abbreviated).year())
            return String(localized: "\(share)% of your net worth sits in investments (was \(Int(reference.rounded()))% in \(month))")
        }
        return String(localized: "\(share)% of your net worth sits in investments")
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Granularity", selection: $granularity) {
                Text("Monthly").tag(InvestmentReportGranularity.monthly)
                Text("Quarterly").tag(InvestmentReportGranularity.quarterly)
                Text("Yearly").tag(InvestmentReportGranularity.yearly)
            }
            .pickerStyle(.menu)
            if enabledPortfolios.count > 1 {
                Section("Portfolios") {
                    portfolioToggles
                }
            }
        } label: {
            Label("Options", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuActionDismissBehavior(.disabled)
    }

    @ViewBuilder
    private var portfolioToggles: some View {
        Text("Filters investment holdings and growth only. Saved amounts and account cash are not affected.")
        Button {
            storedPortfolioIds = ""
        } label: {
            if selectedPortfolioIds.isEmpty {
                Label("All Portfolios", systemImage: "checkmark")
            } else {
                Text("All Portfolios")
            }
        }
        ForEach(enabledPortfolios) { portfolio in
            Button {
                var ids = selectedPortfolioIds
                if let index = ids.firstIndex(of: portfolio.id) {
                    ids.remove(at: index)
                } else {
                    ids.append(portfolio.id)
                }
                storedPortfolioIds = ids.joined(separator: ",")
            } label: {
                if selectedPortfolioIds.contains(portfolio.id) {
                    Label(portfolio.name, systemImage: "checkmark")
                } else {
                    Text(portfolio.name)
                }
            }
        }
    }

    // MARK: Loading

    private func loadPortfolios() async {
        guard let client = services.client else { return }
        do {
            let list = try await client.send(Endpoints.insightsPortfolios())
            portfolios = .loaded(list)
            // Drop ids of portfolios that no longer exist so the filter can't go stale.
            let known = Set(list.map(\.id))
            let kept = selectedPortfolioIds.filter(known.contains)
            if kept.count != selectedPortfolioIds.count { storedPortfolioIds = kept.joined(separator: ",") }
        } catch {
            guard !Task.isCancelled else { return }
            if portfolios.value == nil { portfolios = .failed(APIError(error)) }
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        let endpoint = Endpoints.netWorthDrivers(
            from: period.from,
            to: period.to,
            granularity: granularity,
            portfolioIds: selectedPortfolioIds
        )
        do {
            let report = try await client.send(endpoint)
            guard !Task.isCancelled else { return }
            state = .loaded(report)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(APIError(error))
        }
    }
}

// MARK: - Charts

private struct InsightsNetWorthDriversCumulativeChart: View {
    let points: [NetWorthDriversCumulativePoint]
    let yearly: Bool
    let currencyCode: String

    var body: some View {
        Chart {
            ForEach(points) { point in
                let date = point.periodEnd.startDate()
                AreaMark(
                    x: .value("Period", date),
                    y: .value("Amount", InsightsNetWorthStyle.double(point.savedCumulative))
                )
                .foregroundStyle(InsightsNetWorthStyle.saved.opacity(0.15))
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Period", date),
                    y: .value("Amount", InsightsNetWorthStyle.double(point.savedCumulative)),
                    series: .value("Series", "Saved")
                )
                .foregroundStyle(InsightsNetWorthStyle.saved)
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Period", date),
                    y: .value("Amount", InsightsNetWorthStyle.double(point.grownCumulative)),
                    series: .value("Series", "Grown")
                )
                .foregroundStyle(InsightsNetWorthStyle.grown)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.4))
        }
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
        .chartLegend(.hidden)
        .frame(height: 220)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 12) {
                InsightsNetWorthLegendItem(title: Text("Saved"), color: InsightsNetWorthStyle.saved)
                InsightsNetWorthLegendItem(title: Text("Grown"), color: InsightsNetWorthStyle.grown)
            }
            .padding(.leading, 4)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Saved versus grown chart"))
        .accessibilityValue(Text(summary))
    }

    private var summary: String {
        guard let last = points.last else { return "" }
        let saved = MoneyFormat.string(last.savedCumulative, currencyCode: currencyCode)
        let grown = MoneyFormat.string(last.grownCumulative, currencyCode: currencyCode)
        return String(localized: "Saved \(saved) and grown \(grown) over the period.")
    }
}

private struct InsightsNetWorthDriversBreakdownChart: View {
    let report: NetWorthDriversReport
    let yearly: Bool
    let currencyCode: String

    private static let maxPortfolios = 8
    private static let othersID = "__others__"

    private struct Segment: Identifiable {
        let id: String
        let period: String
        let group: String
        let name: String
        let color: Color
        let amount: Double
    }

    private var legend: [(id: String, name: String, color: Color)] {
        var entries = report.portfolios.prefix(Self.maxPortfolios).enumerated().map { index, portfolio in
            (
                id: portfolio.portfolioId,
                name: portfolio.name,
                color: InsightsNetWorthStyle.portfolioPalette[index % InsightsNetWorthStyle.portfolioPalette.count]
            )
        }
        if report.portfolios.count > Self.maxPortfolios {
            entries.append((id: Self.othersID, name: String(localized: "Others"), color: InsightsNetWorthStyle.others))
        }
        return entries
    }

    private var segments: [Segment] {
        let legend = legend
        let namedIDs = Set(legend.map(\.id))
        let savedName = String(localized: "Saved")
        let grownName = String(localized: "Grown")
        return report.buckets.flatMap { bucket -> [Segment] in
            let label = InsightsNetWorthStyle.bucketLabel(bucket.periodStart, yearly: yearly)
            var rows = [Segment(
                id: "\(label)-saved",
                period: label,
                group: savedName,
                name: savedName,
                color: InsightsNetWorthStyle.saved,
                amount: InsightsNetWorthStyle.double(bucket.savings.net)
            )]
            if legend.isEmpty {
                rows.append(Segment(
                    id: "\(label)-grown",
                    period: label,
                    group: grownName,
                    name: grownName,
                    color: InsightsNetWorthStyle.grown,
                    amount: InsightsNetWorthStyle.double(bucket.investments.growth)
                ))
            } else {
                for entry in legend {
                    let growth: Decimal
                    if entry.id == Self.othersID {
                        growth = bucket.investments.byPortfolio
                            .filter { !namedIDs.contains($0.portfolioId) }
                            .reduce(Decimal.zero) { $0 + $1.growth }
                    } else {
                        growth = bucket.investments.byPortfolio.first { $0.portfolioId == entry.id }?.growth ?? 0
                    }
                    rows.append(Segment(
                        id: "\(label)-\(entry.id)",
                        period: label,
                        group: grownName,
                        name: entry.name,
                        color: entry.color,
                        amount: InsightsNetWorthStyle.double(growth)
                    ))
                }
            }
            return rows
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                Chart(segments) { segment in
                    BarMark(
                        x: .value("Period", segment.period),
                        y: .value("Amount", segment.amount)
                    )
                    .foregroundStyle(segment.color)
                    .position(by: .value("Group", segment.group))
                }
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
                .frame(width: max(300, CGFloat(report.buckets.count) * 44), height: 220)
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Per-period breakdown chart"))
            .accessibilityValue(Text("\(report.buckets.count) periods"))

            InsightsNetWorthFlowLayout(spacing: 12) {
                InsightsNetWorthLegendItem(title: Text("Saved"), color: InsightsNetWorthStyle.saved)
                if legend.isEmpty {
                    InsightsNetWorthLegendItem(title: Text("Grown"), color: InsightsNetWorthStyle.grown)
                }
                ForEach(legend, id: \.id) { entry in
                    InsightsNetWorthLegendItem(title: Text(verbatim: entry.name), color: entry.color)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Target panel

/// The growth-crossover target: the portfolio size at which market growth covers a chosen
/// share of each month's net worth gain, and how long it takes to get there.
private struct InsightsNetWorthTargetPanel: View {
    let currentPortfolioValue: Decimal
    let averageMonthlySavings: Decimal
    let currencyCode: String
    let digits: Int?

    @AppStorage("insights.netWorthDrivers.targetSharePercent") private var targetSharePercent = 80
    @AppStorage("insights.netWorthDrivers.returnIndicator") private var returnIndicator = "sp500"
    @AppStorage("insights.netWorthDrivers.returnRate") private var returnRate = 10.0
    /// Empty means "use the window's average".
    @AppStorage("insights.netWorthDrivers.savingsOverride") private var savingsOverride = ""

    private var averageSavings: Double { InsightsNetWorthStyle.double(averageMonthlySavings) }

    private var effectiveSavings: Double {
        Double(savingsOverride) ?? averageSavings
    }

    private var result: NetWorthFireTarget.Result {
        NetWorthFireTarget.compute(
            currentPortfolioValue: InsightsNetWorthStyle.double(currentPortfolioValue),
            monthlySavings: effectiveSavings,
            annualReturnPercent: returnRate,
            targetGrowthSharePercent: Double(targetSharePercent)
        )
    }

    private func money(_ value: Double) -> String {
        MoneyFormat.string(Decimal(value.rounded()), currencyCode: currencyCode, digits: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                CardHeader("Growth Crossover")
                Text("The portfolio size where market growth, not your saving, does most of the work.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            results

            Divider()

            Text("Assumptions")
                .font(.subheadline.weight(.semibold))

            Stepper(value: $targetSharePercent, in: 50...95, step: 5) {
                LabeledContent("Growth's Share of Monthly Gain") {
                    Text(InsightsNetWorthStyle.percent(Double(targetSharePercent), fractionDigits: 0))
                        .monospacedDigit()
                }
            }

            InsightsNetWorthAnnualReturnField(indicator: $returnIndicator, rate: $returnRate)

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Expected Monthly Saving") {
                    TextField(
                        "e.g. 1,000",
                        text: Binding(
                            get: { savingsOverride.isEmpty ? String(Int(averageSavings.rounded())) : savingsOverride },
                            set: { savingsOverride = $0.filter { $0.isNumber || $0 == "." || $0 == "-" } }
                        )
                    )
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 140)
                }
                if !savingsOverride.isEmpty {
                    Button("Use My Average (\(money(averageSavings)))") {
                        savingsOverride = ""
                    }
                    .font(.footnote)
                }
            }

            Text("A straight projection from today's values and your assumptions, not financial advice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var results: some View {
        switch result {
        case .unreachable:
            Text("Pick a positive expected return to see a target value.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .reached(let needed, let share):
            figure("Portfolio Value Needed", value: money(needed))
            Label("Target reached: your portfolio is already there.", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
            shareLine(share)
            HStack(spacing: 16) {
                figure("Gap", value: String(localized: "Target reached"))
                figure("Time to Target", value: String(localized: "Reached"))
            }
        case .projected(let needed, let gap, let years, let share):
            figure("Portfolio Value Needed", value: money(needed))
            let current = InsightsNetWorthStyle.double(currentPortfolioValue)
            let progress = needed > 0 ? min(max(current / needed, 0), 1) : 0
            ProgressView(value: progress)
                .tint(InsightsNetWorthStyle.grown)
            Text("You're \(Int((progress * 100).rounded()))% of the way: \(money(current)) of \(money(needed)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            shareLine(share)
            HStack(alignment: .top, spacing: 16) {
                figure("Gap", value: String(localized: "\(money(gap)) more needed"))
                VStack(alignment: .leading, spacing: 2) {
                    figure("Time to Target", value: String(localized: "~\(max((years * 10).rounded() / 10, 0.1).formatted(.number.precision(.fractionLength(0...1)))) yr"))
                    Text("If you keep saving and the return holds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func shareLine(_ share: Double) -> some View {
        Text("Today growth covers ~\(Int(share.rounded()))% of your monthly gain; you're aiming for \(targetSharePercent)%.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func figure(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Picks the expected annual return: one of the user's portfolios (its tracked return), a
/// market index average, or a custom rate.
private struct InsightsNetWorthAnnualReturnField: View {
    @Binding var indicator: String
    @Binding var rate: Double
    @Environment(AppServices.self) private var services
    @State private var portfolioReturns: [InsightsPortfolioReturn] = []

    private static let customID = "custom"
    private static let portfolioPrefix = "portfolio:"
    private static let marketIndicators: [(id: String, label: String, rate: Double)] = [
        ("sp500", "S&P 500", 10),
        ("nasdaq", "NASDAQ Composite", 12),
        ("djia", "Dow Jones", 7.5),
        ("world-stock", "Total World Stock", 8),
        ("us-treasury", "US Treasury Bonds", 5),
        ("corporate-bonds", "Corporate Bonds", 6),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Expected Annual Return", selection: Binding(
                get: { indicator },
                set: { select($0) }
            )) {
                ForEach(portfolioReturns) { item in
                    if let value = item.annualizedReturn {
                        Text("\(item.portfolioName) (\(value.formatted(.number.precision(.fractionLength(1))))%/yr)")
                            .tag(Self.portfolioPrefix + item.portfolioId)
                    }
                }
                ForEach(Self.marketIndicators, id: \.id) { item in
                    Text(verbatim: "\(item.label) (~\(item.rate.formatted())%/yr)").tag(item.id)
                }
                Text("Custom").tag(Self.customID)
            }
            .pickerStyle(.menu)

            if indicator == Self.customID {
                LabeledContent("Custom Rate") {
                    HStack(spacing: 4) {
                        TextField("Rate", value: $rate, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 80)
                        Text(verbatim: "%")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            guard let client = services.client else { return }
            portfolioReturns = (try? await client.send(Endpoints.insightsPortfolioReturns())) ?? []
            // A stored portfolio choice follows the portfolio's latest tracked return.
            if indicator.hasPrefix(Self.portfolioPrefix) {
                let id = String(indicator.dropFirst(Self.portfolioPrefix.count))
                if let value = portfolioReturns.first(where: { $0.portfolioId == id })?.annualizedReturn {
                    rate = value
                }
            }
        }
    }

    private func select(_ id: String) {
        indicator = id
        if let market = Self.marketIndicators.first(where: { $0.id == id }) {
            rate = market.rate
        } else if id.hasPrefix(Self.portfolioPrefix) {
            let portfolioID = String(id.dropFirst(Self.portfolioPrefix.count))
            if let value = portfolioReturns.first(where: { $0.portfolioId == portfolioID })?.annualizedReturn {
                rate = value
            }
        }
    }
}

// MARK: - Info sheet

private struct InsightsNetWorthDriversInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Saved") {
                    Text("Money you set aside: income minus spending. Moving money between your own accounts, or into an investment portfolio, doesn't count as saving.")
                }
                Section("Grown") {
                    Text("What the market did to your holdings: price changes, plus dividends, minus fees. Money you put in is never counted as growth.")
                }
                Section("Example") {
                    Text("You earn $10,000, invest it, and it grows to $12,000. That's $10,000 Saved and $2,000 Grown. The $10,000 is counted once, as Saved, and only the $2,000 counts as Grown.")
                }
                Section {
                    Text("Growth is counted as prices move each period, not only when you sell. Selling something that already rose doesn't add to Grown a second time.")
                }
            }
            .navigationTitle("How This Is Calculated")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
