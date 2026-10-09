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

    /// `text` as a plain string, for row subtitles.
    var label: String {
        switch self {
        case .ended:
            String(localized: "Ended")
        case .upcoming(let days):
            switch days {
            case 0: String(localized: "Starts today")
            case 1: String(localized: "Starts tomorrow")
            default: String(localized: "Starts in \(days) days")
            }
        case .active(let days):
            switch days {
            case 0: String(localized: "Last day")
            case 1: String(localized: "1 day left")
            default: String(localized: "\(days) days left")
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

    /// The accent while within the limit, red once over it.
    static func utilizationColor(_ rate: Double) -> Color {
        rate > 100 ? DS.Palette.down : DS.Palette.accent
    }

    /// What a budget has spent: the negative of its net balance, never below zero.
    static func spent(_ stats: PlanningBudgetStats?) -> Decimal {
        max(0, -(stats?.balance ?? 0))
    }

    /// "$120.00 left" or "$40.00 over", red when over.
    static func remaining(spent: Decimal, limit: Decimal, currencyCode: String) -> (text: String, color: Color) {
        if spent > limit {
            let over = MoneyFormat.string(spent - limit, currencyCode: currencyCode)
            return (String(localized: "\(over) over"), DS.Palette.down)
        }
        let left = MoneyFormat.string(limit - spent, currencyCode: currencyCode)
        return (String(localized: "\(left) left"), Color.secondary)
    }

    static func typeLabel(_ type: PlanningBudgetType) -> Text {
        switch type {
        case .category: Text("Category budget")
        case .manual, .unknown: Text("Manual budget")
        }
    }
}

/// A thin utilization bar in the accent, red once the budget is over its limit, with an
/// optional "Used" caption and percent above it.
struct BudgetUtilizationBar: View {
    let rate: Double
    var showsLabel = true

    private var clamped: Double { min(max(rate, 0), 100) / 100 }
    private var color: Color { BudgetFormatting.utilizationColor(rate) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            if showsLabel {
                HStack {
                    Text("Used")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(rate / 100, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(rate > 100 ? DS.Palette.down : Color.secondary)
                }
                .font(.caption)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .tertiarySystemFill))
                    Capsule().fill(color).frame(width: proxy.size.width * clamped)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Budget used"))
        .accessibilityValue(Text(rate / 100, format: .percent.precision(.fractionLength(0))))
    }
}

/// Income, expenses, and net as a three-column `StatGrid`.
struct BudgetStatTriplet: View {
    let stats: PlanningBudgetStats?
    let currencyCode: String

    var body: some View {
        let net = stats?.balance ?? 0
        StatGrid(columns: 3) {
            StatCell(
                label: String(localized: "Income"),
                value: MoneyFormat.string(stats?.actualIncome ?? 0, currencyCode: currencyCode),
                valueColor: DS.Palette.up
            )
            StatCell(
                label: String(localized: "Expenses"),
                value: MoneyFormat.string(abs(stats?.actualExpense ?? 0), currencyCode: currencyCode)
            )
            StatCell(
                label: String(localized: "Net"),
                value: MoneyFormat.string(net, currencyCode: currencyCode),
                valueColor: net >= 0 ? DS.Palette.up : DS.Palette.down
            )
        }
        .redactedWhileLoading(stats == nil)
    }
}
