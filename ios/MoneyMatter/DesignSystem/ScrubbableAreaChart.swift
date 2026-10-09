import Charts
import SwiftUI

/// One dated amount, for callers without their own point type.
nonisolated struct ChartSample: Hashable, Sendable, Identifiable {
    let date: Date
    let value: Decimal

    var id: Date { date }

    init(date: Date, value: Decimal) {
        self.date = date
        self.value = value
    }
}

/// The app's one value-over-time chart, Stocks style, on Swift Charts.
///
/// - A 2 pt monotone line over a flat 12 % area fill (never a gradient), hidden axes.
/// - One gridline: the dotted baseline at the first value, or at `baseline`.
/// - Up to four `.caption2` date labels under the plot.
/// - Drag to scrub: a hairline and a 9 pt dot on the line, with a selection haptic each
///   time the snapped point changes. `selection` carries the scrubbed point (nil when the
///   finger lifts), so the hero above can show it.
/// - A pulsing dot on the latest value while not scrubbing (still under Reduce Motion).
/// - It draws in from the leading edge over 0.9 s on appearance and whenever `drawInKey`
///   changes (skipped under Reduce Motion).
/// - Green when the series ends at or above where it started, red when below. Pass
///   `color: DS.Palette.accent` for a neutral series.
///
/// Generic over any point type, read through key paths:
///
///     @State private var scrubbed: BalancePoint?
///
///     HeroValueHeader(format(scrubbed?.balance ?? latest), numericValue: …,
///                     valueAnimation: scrubbed == nil ? .snappy : nil)
///     ScrubbableAreaChart(history, date: \.date, value: \.balance,
///                         selection: $scrubbed, drawInKey: range)
struct ScrubbableAreaChart<Point>: View {
    private let points: [Point]
    private let dateKey: KeyPath<Point, Date>
    private let valueKey: KeyPath<Point, Decimal>
    @Binding private var selection: Point?
    private let color: Color?
    private let height: CGFloat
    private let baseline: Decimal?
    private let showsBaseline: Bool
    private let pulsingEndDot: Bool
    private let animate: Bool
    private let drawInKey: AnyHashable

    @State private var selectedDate: Date?
    @State private var scrubIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var labelRowHeight: CGFloat { 20 }

    /// - Parameters:
    ///   - color: nil picks green or red by the period's direction.
    ///   - baseline: where the dotted line sits; nil puts it at the first value.
    ///   - drawInKey: what names the series (its range, its account). A new key draws the
    ///     chart in again; a reload under the same key leaves it still.
    init(
        _ points: [Point],
        date: KeyPath<Point, Date>,
        value: KeyPath<Point, Decimal>,
        selection: Binding<Point?> = .constant(nil),
        color: Color? = nil,
        height: CGFloat = 200,
        baseline: Decimal? = nil,
        showsBaseline: Bool = true,
        pulsingEndDot: Bool = true,
        animate: Bool = true,
        drawInKey: AnyHashable = AnyHashable(0)
    ) {
        self.points = points
        self.dateKey = date
        self.valueKey = value
        self._selection = selection
        self.color = color
        self.height = height
        self.baseline = baseline
        self.showsBaseline = showsBaseline
        self.pulsingEndDot = pulsingEndDot
        self.animate = animate
        self.drawInKey = drawInKey
    }

    var body: some View {
        if points.isEmpty {
            Color.clear.frame(height: height)
        } else {
            chart(
                dates: points.map { $0[keyPath: dateKey] },
                values: points.map { $0[keyPath: valueKey].doubleValue }
            )
        }
    }

    // MARK: Chart

    private func chart(dates: [Date], values: [Double]) -> some View {
        let n = values.count
        let base = baseline?.doubleValue ?? values[0]
        let lineColor = color ?? (values[n - 1] >= base ? DS.Palette.up : DS.Palette.down)
        let bounds = ScrubbableChartMath.paddedBounds(values + [base])
        let domain = ScrubbableChartMath.dateDomain(first: dates[0], last: dates[n - 1])
        let span = dates[n - 1].timeIntervalSince(dates[0])
        let labels = ScrubbableChartMath.labelIndices(count: n, slots: 4)
            .map { ScrubbableChartMath.label(for: dates[$0], span: span) }
        let scrubbed = scrubIndex.flatMap { $0 < n ? $0 : nil }
        let plotHeight = min(max(height - Self.labelRowHeight, 40), height)

        return VStack(spacing: 0) {
            Chart {
                if showsBaseline {
                    RuleMark(y: .value("Baseline", base))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: DS.baselineDash))
                }

                ForEach(0..<n, id: \.self) { i in
                    AreaMark(
                        x: .value("Date", dates[i]),
                        yStart: .value("Floor", bounds.lowerBound),
                        yEnd: .value("Value", values[i])
                    )
                    .foregroundStyle(lineColor.opacity(DS.chartAreaOpacity))
                    .interpolationMethod(.monotone)

                    LineMark(x: .value("Date", dates[i]), y: .value("Value", values[i]))
                        .foregroundStyle(lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }

                if let scrubbed {
                    RuleMark(x: .value("Date", dates[scrubbed]))
                        .foregroundStyle(lineColor.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                    PointMark(x: .value("Date", dates[scrubbed]), y: .value("Value", values[scrubbed]))
                        .symbol { ScrubDot(color: lineColor) }
                } else if pulsingEndDot {
                    PointMark(x: .value("Date", dates[n - 1]), y: .value("Value", values[n - 1]))
                        .symbol { LiveEndDot(color: lineColor, pulsing: !reduceMotion) }
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: bounds)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedDate)
            .frame(height: plotHeight)
            .chartDrawIn(trigger: drawInKey, enabled: animate, interacting: selectedDate != nil)

            ChartDateLabels(labels: labels)
                .frame(height: Self.labelRowHeight, alignment: .bottom)
        }
        .frame(height: height)
        .onChange(of: selectedDate) { _, newValue in
            snap(newValue, dates: dates)
        }
        .sensoryFeedback(.selection, trigger: scrubIndex) { _, new in new != nil }
    }

    /// Snaps a raw selection to the nearest point by time, reporting it only when the index
    /// changes.
    private func snap(_ date: Date?, dates: [Date]) {
        guard let date else {
            if scrubIndex != nil {
                scrubIndex = nil
                selection = nil
            }
            return
        }
        let index = ScrubbableChartMath.nearestIndex(in: dates, to: date)
        guard index != scrubIndex else { return }
        scrubIndex = index
        selection = points[index]
    }
}

extension ScrubbableAreaChart where Point == ChartSample {
    /// A chart of plain `ChartSample`s.
    init(
        _ samples: [ChartSample],
        selection: Binding<ChartSample?> = .constant(nil),
        color: Color? = nil,
        height: CGFloat = 200,
        baseline: Decimal? = nil,
        showsBaseline: Bool = true,
        pulsingEndDot: Bool = true,
        animate: Bool = true,
        drawInKey: AnyHashable = AnyHashable(0)
    ) {
        self.init(
            samples,
            date: \.date,
            value: \.value,
            selection: selection,
            color: color,
            height: height,
            baseline: baseline,
            showsBaseline: showsBaseline,
            pulsingEndDot: pulsingEndDot,
            animate: animate,
            drawInKey: drawInKey
        )
    }
}

/// The chart's pure geometry and labels.
nonisolated enum ScrubbableChartMath {
    /// Min/max widened by 6 % of the span on each side, so the line never touches the
    /// edges. Flat or empty input still gets a range with positive height.
    static func paddedBounds(_ values: [Double], padFraction: Double = 0.06) -> ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        if lo == hi {
            let pad = abs(lo) < 1 ? 1.0 : abs(lo) * 0.01
            return (lo - pad)...(hi + pad)
        }
        let pad = (hi - lo) * padFraction
        return (lo - pad)...(hi + pad)
    }

    /// The x domain; a single point gets a one-day span.
    static func dateDomain(first: Date, last: Date) -> ClosedRange<Date> {
        last > first ? first...last : first...first.addingTimeInterval(86_400)
    }

    /// The index of the date nearest `target` in an ascending series.
    static func nearestIndex(in dates: [Date], to target: Date) -> Int {
        guard dates.count > 1 else { return 0 }
        var lo = 0
        var hi = dates.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if dates[mid] < target { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return 0 }
        let prev = lo - 1
        return abs(dates[lo].timeIntervalSince(target)) < abs(dates[prev].timeIntervalSince(target)) ? lo : prev
    }

    /// Up to `slots` evenly spaced indices to label, always the first and last.
    static func labelIndices(count: Int, slots: Int) -> [Int] {
        if count <= 0 { return [] }
        if count == 1 { return [0] }
        let n = min(max(slots, 2), count)
        return (0..<n).map { s in Int((Double(s) / Double(n - 1) * Double(count - 1)).rounded()) }
    }

    /// A date label scaled to the visible span: a time within two days, "Mar 4" within
    /// four months, "Mar ’26" beyond.
    static func label(for date: Date, span: TimeInterval) -> String {
        let days = span / 86_400
        if days <= 2 { return date.formatted(date: .omitted, time: .shortened) }
        if days <= 120 { return date.formatted(.dateTime.month(.abbreviated).day()) }
        return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
    }
}

/// The scrub dot: solid, ringed in the background colour so it reads on the line.
private struct ScrubDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
    }
}

/// The latest-value dot with an expanding ring that fades; still under Reduce Motion.
private struct LiveEndDot: View {
    let color: Color
    let pulsing: Bool

    var body: some View {
        ZStack {
            if pulsing {
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                    .phaseAnimator([0.0, 1.0]) { ring, t in
                        ring.scaleEffect(1 + t * 2.5).opacity(1 - t)
                    } animation: { t in
                        t == 1 ? .easeOut(duration: 1.6) : .linear(duration: 0)
                    }
            }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
        }
        .frame(width: 32, height: 32)
    }
}

/// Evenly spaced x-axis labels under a plot, first leading and last trailing.
struct ChartDateLabels: View {
    let labels: [String]

    var body: some View {
        if !labels.isEmpty {
            HStack(spacing: 0) {
                ForEach(labels.indices, id: \.self) { i in
                    if i > 0 { Spacer(minLength: 4) }
                    Text(verbatim: labels[i])
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .accessibilityHidden(true)
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var scrubbed: ChartSample?
        let samples = (0..<60).map { i in
            ChartSample(
                date: Date(timeIntervalSince1970: 1_790_000_000 + Double(i) * 86_400),
                value: Decimal(5_800 + 60 * sin(Double(i) / 6) + Double(i) * 1.5)
            )
        }

        var body: some View {
            ScrollView {
                DSCard {
                    VStack(alignment: .leading, spacing: DS.cardGroupSpacing) {
                        let shown = scrubbed ?? samples.last!
                        HeroValueHeader(
                            shown.value.formatted(.currency(code: "USD")),
                            numericValue: shown.value.doubleValue,
                            valueAnimation: scrubbed == nil ? .snappy : nil,
                            change: "+$62.13 (+1.07%)",
                            direction: .up,
                            status: "Updated just now"
                        )
                        ScrubbableAreaChart(samples, selection: $scrubbed)
                    }
                }
                .padding()
            }
            .background(DS.Surface.canvas)
        }
    }
    return Demo()
}
