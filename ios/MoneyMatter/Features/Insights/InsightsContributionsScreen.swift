import Charts
import MoneyMatterKit
import SwiftUI

/// Investment contributions: the external cash moved into portfolios per period, stacked by
/// portfolio, with the window total, its share of savings, and the per-period average.
struct InsightsContributionsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    @State private var period = InsightsNetWorthPeriod.default
    @State private var state: LoadState<InvestmentContributionsReport> = .idle
    @State private var portfolios: LoadState<[InsightsPortfolioOption]> = .idle
    @AppStorage("insights.contributions.granularity") private var granularity = InvestmentReportGranularity.monthly
    /// Comma-joined portfolio ids; empty means every portfolio.
    @AppStorage("insights.contributions.portfolioIds") private var storedPortfolioIds = ""

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

    private var showsNoPortfolios: Bool {
        if case .loaded(let list) = portfolios { return list.isEmpty }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if showsNoPortfolios {
                    ContentUnavailableView {
                        Label("No Portfolios Yet", systemImage: "briefcase")
                    } description: {
                        Text("Create a portfolio and start investing to track your contributions here.")
                    } actions: {
                        Button("Add a Portfolio") {
                            router.show(.accounts, popToRoot: true)
                            router.accountsPath.append(.investments)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 40)
                } else {
                    content
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Contributions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !showsNoPortfolios {
                ToolbarItem(placement: .topBarTrailing) {
                    InsightsNetWorthPeriodMenu(period: $period)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    optionsMenu
                }
            }
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

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    InsightsNetWorthStatCard(title: "Total Contributed", value: "$00,000")
                    InsightsNetWorthStatCard(title: "Share of Savings", value: "00%")
                }
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(height: 240)
                    .cardStyle()
            }
            .redactedWhileLoading(true)
        case .failed:
            InlineRetryView(String(localized: "Couldn't load contributions")) { await load() }
                .cardStyle()
        case .loaded(let report):
            if report.hasActivity {
                loaded(report)
            } else {
                ContentUnavailableView {
                    Label("No Contributions in This Range", systemImage: "chart.bar")
                } description: {
                    Text("Move money into a portfolio during this period to see it here.")
                } actions: {
                    Button("Show Last 5 Years") { period = .preset(.last5Years) }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 40)
            }
        }
    }

    @ViewBuilder
    private func loaded(_ report: InvestmentContributionsReport) -> some View {
        let total = InsightsNetWorthStatCard(
            title: "Total Contributed",
            value: MoneyFormat.string(report.totalContributed, currencyCode: currencyCode, digits: digits)
        )
        let share = InsightsNetWorthStatCard(
            title: "Share of Savings",
            value: report.shareOfSavingsPercent.map { "\($0)%" } ?? "—"
        )
        let average = InsightsNetWorthStatCard(
            title: "Average per Period",
            value: MoneyFormat.string(report.averagePerBucket, currencyCode: currencyCode, digits: digits)
        )

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { total; share; average }
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) { total; share }
                average
            }
        }

        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Contributions")
            InsightsContributionsChart(
                report: report,
                yearly: granularity == .yearly,
                currencyCode: currencyCode
            )
        }
        .cardStyle()

        VStack(alignment: .leading, spacing: 0) {
            CardHeader("By Period")
                .padding(.bottom, 8)
            ForEach(Array(report.buckets.enumerated().reversed()), id: \.element.id) { index, bucket in
                let previous = index > 0 ? report.buckets[index - 1].total : nil
                InsightsContributionsPeriodRow(
                    bucket: bucket,
                    previousTotal: previous,
                    yearly: granularity == .yearly,
                    currencyCode: currencyCode,
                    digits: digits
                )
                if index > 0 { Divider() }
            }
        }
        .cardStyle()
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
                    Text("Filters which portfolios count toward contributions.")
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
                            toggle(portfolio.id)
                        } label: {
                            if selectedPortfolioIds.contains(portfolio.id) {
                                Label(portfolio.name, systemImage: "checkmark")
                            } else {
                                Text(portfolio.name)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Options", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuActionDismissBehavior(.disabled)
    }

    private func toggle(_ id: String) {
        var ids = selectedPortfolioIds
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        storedPortfolioIds = ids.joined(separator: ",")
    }

    // MARK: Loading

    private func loadPortfolios() async {
        guard let client = services.client else { return }
        do {
            let list = try await client.send(Endpoints.insightsPortfolios())
            portfolios = .loaded(list)
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
        let endpoint = Endpoints.investmentContributions(
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

/// Bars stacked by portfolio, with a dashed average line from three periods up.
private struct InsightsContributionsChart: View {
    let report: InvestmentContributionsReport
    let yearly: Bool
    let currencyCode: String

    private struct Segment: Identifiable {
        let id: String
        let period: String
        let name: String
        let color: Color
        let amount: Double
    }

    private var legend: [(id: String, name: String, color: Color)] {
        report.portfolios.enumerated().map { index, portfolio in
            (
                id: portfolio.portfolioId,
                name: portfolio.name,
                color: InsightsNetWorthStyle.portfolioPalette[index % InsightsNetWorthStyle.portfolioPalette.count]
            )
        }
    }

    private var segments: [Segment] {
        let legend = legend
        return report.buckets.flatMap { bucket in
            let label = InsightsNetWorthStyle.bucketLabel(bucket.periodStart, yearly: yearly)
            return legend.map { entry in
                Segment(
                    id: "\(label)-\(entry.id)",
                    period: label,
                    name: entry.name,
                    color: entry.color,
                    amount: InsightsNetWorthStyle.double(bucket.amount(forPortfolio: entry.id))
                )
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                Chart {
                    ForEach(segments) { segment in
                        BarMark(
                            x: .value("Period", segment.period),
                            y: .value("Amount", segment.amount)
                        )
                        .foregroundStyle(segment.color)
                    }
                    if let average = report.chartAverage {
                        RuleMark(y: .value("Average", InsightsNetWorthStyle.double(average)))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Average")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
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
                .frame(width: max(300, CGFloat(report.buckets.count) * 36), height: 240)
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Contributions chart"))
            .accessibilityValue(Text(summary))

            InsightsNetWorthFlowLayout(spacing: 12) {
                ForEach(legend, id: \.id) { entry in
                    InsightsNetWorthLegendItem(title: Text(verbatim: entry.name), color: entry.color)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private var summary: String {
        let total = MoneyFormat.string(report.totalContributed, currencyCode: currencyCode)
        return String(localized: "\(total) contributed over \(report.buckets.count) periods.")
    }
}

/// One period's total with its change versus the period before.
private struct InsightsContributionsPeriodRow: View {
    let bucket: InvestmentContributionBucket
    let previousTotal: Decimal?
    let yearly: Bool
    let currencyCode: String
    let digits: Int?

    /// Shown only when both periods contributed, where a percentage means something.
    private var changePercent: Int? {
        guard let previousTotal, previousTotal > 0, bucket.total > 0 else { return nil }
        let ratio = InsightsNetWorthStyle.double((bucket.total - previousTotal) / previousTotal)
        return Int((ratio * 100).rounded())
    }

    var body: some View {
        HStack {
            Text(InsightsNetWorthStyle.bucketLabel(bucket.periodStart, yearly: yearly))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(MoneyFormat.string(bucket.total, currencyCode: currencyCode, digits: digits))
                    .monospacedDigit()
                    .foregroundStyle(bucket.total < 0 ? .red : .primary)
                if let changePercent {
                    Text("\(changePercent > 0 ? "+" : "")\(changePercent)% vs previous")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(changePercent >= 0 ? .green : .red)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
