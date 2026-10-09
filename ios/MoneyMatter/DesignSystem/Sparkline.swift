import Charts
import SwiftUI

/// A tiny trend line for a row: 1.5 pt, monotone, with no fill, axes, grid or legend.
///
/// Green when the last value is at or above the first and red otherwise, unless you pass
/// `color`. An optional `baseline` draws the dotted reference line. It draws in from the
/// left over 0.65 s on first appearance (skipped under Reduce Motion, or with
/// `animated: false`). Decorative: the row's text carries the numbers for VoiceOver.
///
///     Sparkline(values: balances).frame(width: 60, height: 24)
struct Sparkline: View {
    let values: [Double]
    var height: CGFloat
    var color: Color?
    var baseline: Double?
    var animated: Bool

    init(values: [Double], height: CGFloat = 28, color: Color? = nil, baseline: Double? = nil, animated: Bool = true) {
        self.values = values
        self.height = height
        self.color = color
        self.baseline = baseline
        self.animated = animated
    }

    /// A sparkline of money amounts.
    init(amounts: [Decimal], height: CGFloat = 28, color: Color? = nil, baseline: Decimal? = nil, animated: Bool = true) {
        self.init(
            values: amounts.map(\.doubleValue),
            height: height,
            color: color,
            baseline: baseline?.doubleValue,
            animated: animated
        )
    }

    /// True when the line ends at or above where it started.
    nonisolated static func isUp(_ values: [Double]) -> Bool {
        guard let first = values.first, let last = values.last else { return true }
        return last >= first
    }

    var body: some View {
        if values.count < 2 {
            Color.clear.frame(height: height)
        } else {
            let tint = color ?? (Self.isUp(values) ? DS.Palette.up : DS.Palette.down)
            let all = baseline.map { values + [$0] } ?? values
            let lo = all.min() ?? 0
            let hi = all.max() ?? 1
            let span = abs(hi - lo) < 1e-9 ? 1 : hi - lo
            Chart {
                if let baseline {
                    RuleMark(y: .value("Baseline", baseline))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: DS.baselineDash))
                }
                ForEach(values.indices, id: \.self) { i in
                    LineMark(x: .value("i", i), y: .value("v", values[i]))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartXScale(domain: 0...(values.count - 1))
            .chartYScale(domain: lo...(lo + span))
            .chartPlotStyle { $0.padding(.vertical, 2) }
            .chartDrawIn(duration: ChartDrawIn.sparkDuration, enabled: animated, bleed: 2)
            .frame(height: height)
            .accessibilityHidden(true)
        }
    }
}

#Preview {
    List {
        EntityRow("Checking", subtitle: "Bank", systemImage: "building.columns.fill") {
            HStack(spacing: 12) {
                Sparkline(values: [10, 11, 10.5, 12, 12.4, 12.1, 13], baseline: 10.8)
                    .frame(width: 60, height: 24)
                EntityRowValue("$2,031.08", detail: "+2.08%", detailColor: DS.Palette.up)
            }
        }
    }
}
