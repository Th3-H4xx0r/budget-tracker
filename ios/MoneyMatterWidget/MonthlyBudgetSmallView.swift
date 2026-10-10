import Charts
import MoneyMatterKit
import SwiftUI
import WidgetKit

/// Home Screen small widget: the month's spending, how it stands against the budget, the
/// cumulative spending line against a dashed budget line, and when it was last updated.
/// Always drawn on a dark background.
struct MonthlyBudgetSmallView: View {
    let entry: MonthlyBudgetEntry

    var body: some View {
        content
            .environment(\.colorScheme, .dark)
            .containerBackground(for: .widget) {
                Color("WidgetBackground")
            }
            .widgetURL(BudgetWidgetFormat.url(for: entry.snapshot))
    }

    @ViewBuilder private var content: some View {
        if let snapshot = entry.snapshot {
            BudgetSmallContent(snapshot: snapshot, now: entry.date)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                BudgetAppMark()
                Spacer(minLength: 0)
                Text("Open MoneyMatter to see this month's spending")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct BudgetSmallContent: View {
    let snapshot: MonthlySpendingSnapshot
    let now: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isFullColor: Bool { renderingMode == .fullColor }

    /// Red when over budget; otherwise white, which the accented mode tints.
    private var emphasis: Color {
        snapshot.isOverBudget && isFullColor ? .red : .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(BudgetWidgetFormat.amount(snapshot.spent, snapshot))
                        .font(.title.bold())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                    Text("Spent this month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                BudgetAppMark()
            }

            if snapshot.hasBudget {
                statusLine
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(emphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 6)
                    .widgetAccentable()

                BudgetSpendingChart(snapshot: snapshot, lineColor: emphasis)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 4)
            } else {
                Spacer(minLength: 4)
                Text("Set a monthly budget in MoneyMatter")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .widgetAccentable()
                Spacer(minLength: 4)
            }

            BudgetWidgetFormat.freshness(snapshot.updatedAt, now: now)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var statusLine: some View {
        if let overBy = snapshot.overBy, snapshot.isOverBudget {
            Text("\(BudgetWidgetFormat.amount(overBy, snapshot)) over budget")
        } else if let remaining = snapshot.remaining {
            Text("\(BudgetWidgetFormat.amount(remaining, snapshot)) left")
        }
    }
}

/// Cumulative spending from day 0 against a dashed rule at the budget. The x-axis spans the
/// whole month so the line's length shows how far through the month it is.
private struct BudgetSpendingChart: View {
    let snapshot: MonthlySpendingSnapshot
    let lineColor: Color

    private struct Point: Identifiable {
        let day: Int
        let value: Double
        var id: Int { day }
    }

    private var points: [Point] {
        [Point(day: 0, value: 0)] + snapshot.dailyCumulative.enumerated().map { index, value in
            Point(day: index + 1, value: Self.double(value))
        }
    }

    private var budget: Double { Self.double(snapshot.budget ?? 0) }

    private var yMax: Double {
        max(budget, Self.double(snapshot.spent), 1) * 1.08
    }

    var body: some View {
        let points = points
        Chart {
            RuleMark(y: .value("Budget", budget))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.secondary)

            ForEach(points) { point in
                LineMark(x: .value("Day", point.day), y: .value("Spent", point.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(lineColor)
            }

            if let last = points.last {
                PointMark(x: .value("Day", last.day), y: .value("Spent", last.value))
                    .symbolSize(28)
                    .foregroundStyle(lineColor)
            }
        }
        .chartXScale(domain: 0...max(snapshot.month.dayCount(), 1))
        .chartYScale(domain: 0...yMax)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .widgetAccentable()
        .accessibilityLabel(Text("Cumulative spending this month"))
    }

    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

/// The app mark: a white pie glyph on an accent tile, as on the sign-in screen.
struct BudgetAppMark: View {
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: "chart.pie.fill")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor, in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}
