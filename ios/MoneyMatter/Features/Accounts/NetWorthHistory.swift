import Charts
import MoneyMatterKit
import Observation
import SwiftUI

/// The balance history over one range, plus the closing balance before it.
struct BalanceTrend: Equatable {
    let points: [BalancePoint]
    /// The last balance before the range started, when the server had one.
    let previousTotal: Decimal?

    var currentTotal: Decimal? { points.last?.totalBalance }

    /// What changes are measured from: the close before the range, else its first day.
    var baseline: Decimal? { previousTotal ?? points.first?.totalBalance }

    var change: Decimal? {
        guard let currentTotal, let baseline else { return nil }
        return currentTotal - baseline
    }
}

/// The net worth chart's range.
enum NetWorthRange: String, CaseIterable, Identifiable, Hashable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "All"

    var id: Self { self }

    /// The segmented picker's label.
    var label: String {
        switch self {
        case .all: String(localized: "All")
        default: rawValue
        }
    }

    /// The hero's change label.
    var summaryLabel: String {
        switch self {
        case .oneMonth: String(localized: "Past month")
        case .threeMonths: String(localized: "Past 3 months")
        case .sixMonths: String(localized: "Past 6 months")
        case .oneYear: String(localized: "Past year")
        case .all: String(localized: "All time")
        }
    }

    /// The first day of the range ending `today`. "All" reaches back ten years; leading
    /// empty days are trimmed after loading.
    func firstDay(today: CalendarDate) -> CalendarDate {
        let days = switch self {
        case .oneMonth: 30
        case .threeMonths: 91
        case .sixMonths: 182
        case .oneYear: 365
        case .all: 3_650
        }
        return today.adding(days: -days)
    }
}

/// One day of the net worth chart.
struct NetWorthChartPoint: Hashable {
    let date: Date
    let amount: Decimal
}

/// Loads `/stats/combined-balance-history` for the selected range. Only the latest load may
/// write the state, so a slow response for an earlier range can't replace a newer one.
@Observable
final class NetWorthHistoryModel {
    private(set) var range: NetWorthRange = .oneMonth
    private(set) var state: LoadState<BalanceTrend> = .idle
    @ObservationIgnored private var generation = 0

    func loadIfNeeded(stats: any StatsServicing) async {
        guard case .idle = state else { return }
        await load(stats: stats)
    }

    func setRange(_ newRange: NetWorthRange, stats: any StatsServicing) async {
        guard newRange != range else { return }
        range = newRange
        state = .loading
        await load(stats: stats)
    }

    /// Reloads the current range. A loaded chart keeps its content while refreshing.
    func load(stats: any StatsServicing) async {
        generation += 1
        let current = generation
        let range = range
        let today = CalendarDate(date: .now)
        let from = range.firstDay(today: today)
        if state.value == nil { state = .loading }
        do {
            // One extra day in front, for the closing balance before the range. One extra day at
            // the end too: the API reports the last requested day as 0, so that point is dropped.
            let points = try await stats.balanceHistory(from: from.adding(days: -1), to: today.adding(days: 1))
                .sorted { $0.date < $1.date }
            let previous = points.last { $0.date < from }
            var inRange = points.filter { $0.date >= from && $0.date <= today }
            if range == .all, let firstValue = inRange.firstIndex(where: { $0.totalBalance != 0 }) {
                inRange.removeFirst(firstValue)
            }
            guard generation == current else { return }
            state = .loaded(BalanceTrend(
                points: Self.downsampled(points: inRange, limit: 400),
                previousTotal: range == .all ? nil : previous?.totalBalance
            ))
        } catch {
            guard generation == current else { return }
            if state.value == nil { state = .failed(APIError(error)) }
        }
    }

    /// At most `limit` points, evenly strided, always keeping the latest.
    private static func downsampled(points: [BalancePoint], limit: Int) -> [BalancePoint] {
        guard points.count > limit, let last = points.last else { return points }
        let stride = Int((Double(points.count) / Double(limit)).rounded(.up))
        var result = Swift.stride(from: 0, to: points.count - 1, by: stride).map { points[$0] }
        result.append(last)
        return result
    }
}

/// The scrubbable net worth chart and its 1M to All range picker. Scrubbing writes
/// `scrubbed`, which the net worth hero above it shows.
struct NetWorthHistoryChart: View {
    let state: LoadState<BalanceTrend>
    let range: NetWorthRange
    @Binding var scrubbed: NetWorthChartPoint?
    let currencyCode: String
    let setRange: (NetWorthRange) -> Void
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            switch state {
            case .failed(let error):
                ErrorRow(ErrorMessage.message(for: error), retry: retry)
            case .loaded(let trend):
                chart(trend)
            case .idle, .loading:
                chart(BalanceTrend.placeholder)
                    .redactedWhileLoading(true)
            }
            Picker("Range", selection: Binding(get: { range }, set: setRange)) {
                ForEach(NetWorthRange.allCases) { option in
                    Text(verbatim: option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func chart(_ trend: BalanceTrend) -> some View {
        let points = trend.points.map { NetWorthChartPoint(date: $0.date.startDate(), amount: $0.totalBalance) }
        if points.count > 1 {
            ScrubbableAreaChart(
                points,
                date: \.date,
                value: \.amount,
                selection: $scrubbed,
                height: 200,
                baseline: trend.baseline,
                drawInKey: range
            )
            .accessibilityChartDescriptor(BalanceChartDescriptor(points: trend.points, currencyCode: currencyCode))
        } else {
            Text("Not enough data for a trend yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
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
            name: String(localized: "Net worth"),
            isContinuous: true,
            dataPoints: zip(dates, values).map { AXDataPoint(x: $0, y: $1) }
        )
        return AXChartDescriptor(
            title: String(localized: "Net worth history"),
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
