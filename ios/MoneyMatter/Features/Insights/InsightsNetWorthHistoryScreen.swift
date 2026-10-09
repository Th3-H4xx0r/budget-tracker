import Charts
import MoneyMatterKit
import SwiftUI

/// Net worth history: assets stacked by kind, liabilities below the baseline, and the
/// net worth line, per week, month, quarter, or year. Kind filters reshape the loaded
/// series without refetching.
struct InsightsNetWorthHistoryScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session

    @State private var period = InsightsNetWorthPeriod.default
    @State private var state: LoadState<NetWorthHistoryReport> = .idle
    /// `auto`, or a sticky granularity the user picked.
    @AppStorage("insights.netWorthHistory.granularity") private var granularityOverride = "auto"
    /// Comma-joined raw values; empty means every kind.
    @AppStorage("insights.netWorthHistory.assetKinds") private var storedAssetKinds = ""
    @AppStorage("insights.netWorthHistory.liabilityKinds") private var storedLiabilityKinds = ""

    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }
    private var digits: Int? { session.baseCurrency?.currency?.digits }

    private var disabledGranularities: Set<NetWorthHistoryGranularity> {
        NetWorthHistoryGranularity.disabled(from: period.from, to: period.to)
    }

    private var granularity: NetWorthHistoryGranularity {
        if let chosen = NetWorthHistoryGranularity(rawValue: granularityOverride), !disabledGranularities.contains(chosen) {
            return chosen
        }
        return .automatic(from: period.from, to: period.to)
    }

    private struct RequestKey: Equatable {
        let from: CalendarDate
        let to: CalendarDate
        let granularity: NetWorthHistoryGranularity
    }

    private var requestKey: RequestKey {
        RequestKey(from: period.from, to: period.to, granularity: granularity)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                content
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Net Worth")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InsightsNetWorthPeriodMenu(period: $period)
            }
            ToolbarItem(placement: .topBarTrailing) {
                optionsMenu
            }
        }
        .refreshable { await load() }
        .task(id: requestKey) { await load() }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            placeholder
        case .failed:
            InlineRetryView(String(localized: "Couldn't load net worth history")) { await load() }
                .cardStyle()
        case .loaded(let report):
            if report.hasData {
                loaded(report)
            } else {
                ContentUnavailableView {
                    Label("No History for This Period", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Try a longer period, or add accounts and transactions so there are balances to snapshot.")
                } actions: {
                    Button("Show Last 5 Years") { period = .preset(.last5Years) }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 40)
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                InsightsNetWorthStatCard(title: "Current Net Worth", value: "$000,000")
                InsightsNetWorthStatCard(title: "Period Change", value: "+$00,000")
            }
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
                .frame(height: 260)
                .cardStyle()
        }
        .redactedWhileLoading(true)
    }

    @ViewBuilder
    private func loaded(_ report: NetWorthHistoryReport) -> some View {
        let assetKinds = NetWorthHistoryMath.resolveSelection(
            stored: decodeKinds(storedAssetKinds, as: NetWorthAssetKind.self),
            available: report.assetKindsWithActivity
        )
        let liabilityKinds = NetWorthHistoryMath.resolveSelection(
            stored: decodeKinds(storedLiabilityKinds, as: NetWorthLiabilityKind.self),
            available: report.liabilityKindsWithActivity
        )
        let points = report.displayPoints(assetKinds: assetKinds, liabilityKinds: liabilityKinds)
        let change = NetWorthHistoryMath.periodChange(points)
        let annualized = NetWorthHistoryMath.annualizedGrowthPercent(points)
        let averageOwed = NetWorthHistoryMath.averageOwed(points)

        if let degraded = report.degraded {
            InsightsNetWorthDegradedNotice(degraded: degraded)
        }

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                currentCard(points)
                changeCard(change: change, annualized: annualized)
            }
            VStack(spacing: 12) {
                currentCard(points)
                changeCard(change: change, annualized: annualized)
            }
        }

        liabilitiesLine(averageOwed)

        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Assets, Liabilities and Net Worth")
            InsightsNetWorthHistoryChart(
                points: points,
                assetKinds: assetKinds,
                granularity: granularity,
                currencyCode: currencyCode
            )
            legend(assetKinds: assetKinds, showsLiabilities: !liabilityKinds.isEmpty)
        }
        .cardStyle()
    }

    private func currentCard(_ points: [NetWorthDisplayPoint]) -> some View {
        InsightsNetWorthStatCard(
            title: "Current Net Worth",
            value: MoneyFormat.string(points.last?.netWorth ?? 0, currencyCode: currencyCode, digits: digits)
        )
    }

    private func changeCard(change: (amount: Decimal, percent: Double?), annualized: Double?) -> some View {
        InsightsNetWorthStatCard(
            title: "Period Change",
            value: MoneyFormat.string(change.amount, currencyCode: currencyCode, digits: digits, sign: .always),
            valueColor: change.amount >= 0 ? .green : .red
        ) {
            VStack(alignment: .leading, spacing: 2) {
                if let percent = change.percent {
                    Text(InsightsNetWorthStyle.percent(percent))
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(change.amount >= 0 ? .green : .red)
                }
                if let annualized {
                    Text("≈ \(InsightsNetWorthStyle.percent(annualized)) / yr")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func liabilitiesLine(_ averageOwed: Decimal) -> some View {
        Group {
            if averageOwed > 0 {
                Text("You had an average of \(Text(MoneyFormat.string(averageOwed, currencyCode: currencyCode, digits: digits)).foregroundStyle(.red).monospacedDigit()) in liabilities during this period.")
            } else {
                Label("You had no liabilities during this period.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func legend(assetKinds: [NetWorthAssetKind], showsLiabilities: Bool) -> some View {
        InsightsNetWorthFlowLayout(spacing: 12) {
            ForEach(assetKinds) { kind in
                legendItem(InsightsNetWorthStyle.title(for: kind), color: InsightsNetWorthStyle.color(for: kind))
            }
            if showsLiabilities {
                legendItem("Liabilities", color: InsightsNetWorthStyle.liabilities)
            }
            legendItem("Net Worth", color: .primary)
        }
        .accessibilityHidden(true)
    }

    private func legendItem(_ title: LocalizedStringKey, color: Color) -> some View {
        InsightsNetWorthLegendItem(title: Text(title), color: color)
    }

    // MARK: Options

    private var optionsMenu: some View {
        Menu {
            Picker("Granularity", selection: Binding(
                get: { granularity },
                set: { granularityOverride = $0.rawValue }
            )) {
                ForEach(NetWorthHistoryGranularity.allCases) { option in
                    Text(Self.title(for: option)).tag(option)
                }
            }
            .pickerStyle(.menu)

            if let report = state.value {
                let assets = report.assetKindsWithActivity
                if !assets.isEmpty {
                    Section("Assets") {
                        kindToggles(available: assets, stored: $storedAssetKinds, title: InsightsNetWorthStyle.title(for:))
                    }
                }
                let liabilities = report.liabilityKindsWithActivity
                if !liabilities.isEmpty {
                    Section("Liabilities") {
                        kindToggles(available: liabilities, stored: $storedLiabilityKinds, title: InsightsNetWorthStyle.title(for:))
                    }
                }
            }
        } label: {
            Label("Options", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuActionDismissBehavior(.disabled)
    }

    private func kindToggles<Kind: RawRepresentable & Hashable & Identifiable>(
        available: [Kind],
        stored: Binding<String>,
        title: @escaping (Kind) -> LocalizedStringKey
    ) -> some View where Kind.RawValue == String {
        ForEach(available) { kind in
            let selected = NetWorthHistoryMath.resolveSelection(stored: decodeKinds(stored.wrappedValue, as: Kind.self), available: available)
            Toggle(isOn: Binding(
                get: { selected.contains(kind) },
                set: { isOn in
                    var next = selected
                    if isOn {
                        next.append(kind)
                    } else {
                        next.removeAll { $0 == kind }
                    }
                    // Keep at least one kind; every kind selected is stored as "all".
                    guard !next.isEmpty else { return }
                    stored.wrappedValue = next.count == available.count ? "" : next.map(\.rawValue).joined(separator: ",")
                }
            )) {
                Text(title(kind))
            }
        }
    }

    private func decodeKinds<Kind: RawRepresentable>(_ raw: String, as _: Kind.Type) -> [Kind] where Kind.RawValue == String {
        raw.split(separator: ",").compactMap { Kind(rawValue: String($0)) }
    }

    private static func title(for granularity: NetWorthHistoryGranularity) -> LocalizedStringKey {
        switch granularity {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        }
    }

    // MARK: Loading

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        let endpoint = Endpoints.netWorthHistory(from: period.from, to: period.to, granularity: granularity)
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

/// Assets stacked per kind above zero, liabilities below, and the net worth line.
private struct InsightsNetWorthHistoryChart: View {
    let points: [NetWorthDisplayPoint]
    let assetKinds: [NetWorthAssetKind]
    let granularity: NetWorthHistoryGranularity
    let currencyCode: String

    private var unit: Calendar.Component {
        switch granularity {
        case .weekly: .weekOfYear
        case .monthly: .month
        case .quarterly: .quarter
        case .yearly: .year
        }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                let date = point.date.startDate()
                ForEach(assetKinds) { kind in
                    BarMark(
                        x: .value("Date", date, unit: unit),
                        y: .value("Amount", InsightsNetWorthStyle.double(point.assetsByKind[kind] ?? 0))
                    )
                    .foregroundStyle(InsightsNetWorthStyle.color(for: kind).opacity(0.75))
                }
                if point.liabilitiesTotal != 0 {
                    BarMark(
                        x: .value("Date", date, unit: unit),
                        y: .value("Amount", InsightsNetWorthStyle.double(point.liabilitiesTotal))
                    )
                    .foregroundStyle(InsightsNetWorthStyle.liabilities.opacity(0.7))
                }
                LineMark(
                    x: .value("Date", date, unit: unit),
                    y: .value("Net Worth", InsightsNetWorthStyle.double(point.netWorth))
                )
                .foregroundStyle(Color.primary)
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
        .frame(height: 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Net worth chart"))
        .accessibilityValue(Text(summary))
    }

    private var summary: String {
        guard let first = points.first, let last = points.last else { return "" }
        let start = MoneyFormat.string(first.netWorth, currencyCode: currencyCode)
        let end = MoneyFormat.string(last.netWorth, currencyCode: currencyCode)
        return String(localized: "Net worth went from \(start) to \(end) over \(points.count) periods.")
    }
}
