import MoneyMatterKit
import SwiftUI
import WidgetKit

/// Lock Screen circular: a capacity gauge of spent over budget with the percentage.
struct BudgetCircularView: View {
    let snapshot: MonthlySpendingSnapshot?

    var body: some View {
        Group {
            if let snapshot, let fraction = snapshot.fraction {
                Gauge(value: min(max(fraction, 0), 1)) {
                    Image(systemName: "chart.pie.fill")
                } currentValueLabel: {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .minimumScaleFactor(0.5)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .accessibilityLabel(Text("Monthly budget used"))
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "chart.pie.fill")
                        .font(.title3)
                        .accessibilityLabel(Text("Set a monthly budget in MoneyMatter"))
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(BudgetWidgetFormat.url(for: snapshot))
    }
}

/// Lock Screen inline: "$412 left" or "$988 over".
struct BudgetInlineView: View {
    let snapshot: MonthlySpendingSnapshot?

    var body: some View {
        label
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(BudgetWidgetFormat.url(for: snapshot))
    }

    @ViewBuilder private var label: some View {
        if let snapshot, let overBy = snapshot.overBy, snapshot.isOverBudget {
            Text("\(BudgetWidgetFormat.amount(overBy, snapshot)) over")
        } else if let snapshot, let remaining = snapshot.remaining {
            Text("\(BudgetWidgetFormat.amount(remaining, snapshot)) left")
        } else {
            Text("Set a monthly budget")
        }
    }
}

/// Lock Screen rectangular: spent, the budget, and a mini bar.
struct BudgetRectangularView: View {
    let snapshot: MonthlySpendingSnapshot?

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(BudgetWidgetFormat.url(for: snapshot))
    }

    @ViewBuilder private var content: some View {
        if let snapshot, let budget = snapshot.budget, let fraction = snapshot.fraction {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(BudgetWidgetFormat.amount(snapshot.spent, snapshot)) spent")
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                Text("of \(BudgetWidgetFormat.amount(budget, snapshot)) budget")
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                Gauge(value: min(max(fraction, 0), 1)) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .accessibilityLabel(Text("Monthly budget used"))
            }
        } else if let snapshot {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(BudgetWidgetFormat.amount(snapshot.spent, snapshot)) spent")
                    .font(.headline)
                    .monospacedDigit()
                    .widgetAccentable()
                Text("Set a monthly budget in MoneyMatter")
                    .font(.caption)
                    .lineLimit(2)
            }
        } else {
            Text("Open MoneyMatter to see this month's spending")
                .font(.caption)
                .lineLimit(3)
        }
    }
}
