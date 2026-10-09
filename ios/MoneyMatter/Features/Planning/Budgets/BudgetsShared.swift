import MoneyMatterKit
import SwiftUI

/// Where a budget sits relative to today, from its optional start and end dates. Mirrors the
/// web card's status banner.
enum BudgetTimeStatus: Equatable {
    case ended
    case upcoming(daysUntil: Int)
    case active(daysLeft: Int)

    init?(budget: PlanningBudget, now: Date = .now, calendar: Calendar = .current) {
        let start = budget.startDate
        let end = budget.endDate
        guard start != nil || end != nil else { return nil }
        if let end, end < now {
            self = .ended
        } else if let start, start > now {
            self = .upcoming(daysUntil: Self.days(from: now, to: start, calendar: calendar))
        } else if let end {
            self = .active(daysLeft: Self.days(from: now, to: end, calendar: calendar))
        } else {
            return nil
        }
    }

    private static func days(from: Date, to: Date, calendar: Calendar) -> Int {
        max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    var text: Text {
        switch self {
        case .ended:
            Text("Ended")
        case .upcoming(let days):
            switch days {
            case 0: Text("Starts today")
            case 1: Text("Starts tomorrow")
            default: Text("Starts in \(days) days")
            }
        case .active(let days):
            switch days {
            case 0: Text("Last day")
            case 1: Text("1 day left")
            default: Text("\(days) days left")
            }
        }
    }

    var tint: Color {
        switch self {
        case .ended: .secondary
        case .upcoming: .blue
        case .active: .green
        }
    }
}

enum BudgetFormatting {
    static func dateRange(start: Date?, end: Date?) -> Text? {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        switch (start, end) {
        case let (start?, end?): return Text("\(start.formatted(style)) – \(end.formatted(style))")
        case let (start?, nil): return Text("From \(start.formatted(style))")
        case let (nil, end?): return Text("Until \(end.formatted(style))")
        case (nil, nil): return nil
        }
    }

    /// Green under 70%, orange to 90%, red above, as on the web.
    static func utilizationColor(_ rate: Double) -> Color {
        if rate > 90 { return .red }
        if rate > 70 { return .orange }
        return .green
    }

    static func typeLabel(_ type: PlanningBudgetType) -> Text {
        switch type {
        case .category: Text("Category budget")
        case .manual, .unknown: Text("Manual budget")
        }
    }
}

/// A capsule progress bar with the percent of the limit used.
struct BudgetUtilizationBar: View {
    let rate: Double
    var showsLabel = true

    private var clamped: Double { min(max(rate, 0), 100) / 100 }
    private var color: Color { BudgetFormatting.utilizationColor(rate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsLabel {
                HStack {
                    Text("Used")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(rate / 100, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .fontWeight(.medium)
                        .foregroundStyle(color)
                }
                .font(.caption)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(color).frame(width: proxy.size.width * clamped)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Budget used"))
        .accessibilityValue(Text(rate / 100, format: .percent.precision(.fractionLength(0))))
    }
}

/// Income, expenses, and net in three compact columns.
struct BudgetStatTriplet: View {
    let stats: PlanningBudgetStats?
    let currencyCode: String

    var body: some View {
        HStack(alignment: .top) {
            column(title: "Income", amount: stats?.actualIncome ?? 0, style: .income)
            column(title: "Expenses", amount: stats?.actualExpense ?? 0, style: .neutral)
            column(
                title: "Net",
                amount: stats?.balance ?? 0,
                style: (stats?.balance ?? 0) >= 0 ? .income : .expense
            )
        }
        .redactedWhileLoading(stats == nil)
    }

    private func column(title: LocalizedStringKey, amount: Decimal, style: AmountStyle) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            AmountText(style == .neutral ? abs(amount) : amount, currencyCode: currencyCode, style: style)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
