import MoneyMatterKit
import SwiftUI
import WidgetKit

struct MonthlyBudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedContainer.monthlyBudgetWidgetKind, provider: MonthlyBudgetProvider()) { entry in
            MonthlyBudgetEntryView(entry: entry)
        }
        .configurationDisplayName("Monthly Budget")
        .description("This month's spending against your monthly budget.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

struct MonthlyBudgetEntryView: View {
    let entry: MonthlyBudgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            BudgetCircularView(snapshot: entry.snapshot)
        case .accessoryInline:
            BudgetInlineView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            BudgetRectangularView(snapshot: entry.snapshot)
        default:
            MonthlyBudgetSmallView(entry: entry)
        }
    }
}

/// Shared wording and formatting for every family.
enum BudgetWidgetFormat {
    /// Whole units, e.g. `$1,388`; the widget is too small for cents.
    static func amount(_ value: Decimal, _ snapshot: MonthlySpendingSnapshot) -> String {
        MoneyFormat.string(value, currencyCode: snapshot.currencyCode, digits: 0)
    }

    static func url(for snapshot: MonthlySpendingSnapshot?) -> URL {
        guard let snapshot, !snapshot.hasBudget else { return SharedContainer.homeURL }
        return SharedContainer.setBudgetURL
    }

    static func freshness(_ updatedAt: Date, now: Date) -> Text {
        switch BudgetFreshness(since: updatedAt, now: now) {
        case .justNow: Text("Updated just now")
        case .minutes(let minutes): Text("\(minutes) min ago")
        case .hours(let hours): Text("\(hours) hr ago")
        case .overHalfADay: Text("Over half a day ago")
        case .overADay: Text("Over a day ago")
        case .days(let days): Text("\(days) days ago")
        }
    }
}

// MARK: - Previews

#Preview("Over", as: .systemSmall) {
    MonthlyBudgetWidget()
} timeline: {
    MonthlyBudgetEntry(date: .now, snapshot: .sampleOver)
    MonthlyBudgetEntry(date: .now, snapshot: .sampleUnder)
    MonthlyBudgetEntry(date: .now, snapshot: .sampleNoBudget)
    MonthlyBudgetEntry(date: .now, snapshot: nil)
}

#Preview("Circular", as: .accessoryCircular) {
    MonthlyBudgetWidget()
} timeline: {
    MonthlyBudgetEntry(date: .now, snapshot: .sampleUnder)
    MonthlyBudgetEntry(date: .now, snapshot: .sampleOver)
}

#Preview("Inline", as: .accessoryInline) {
    MonthlyBudgetWidget()
} timeline: {
    MonthlyBudgetEntry(date: .now, snapshot: .sampleUnder)
    MonthlyBudgetEntry(date: .now, snapshot: .sampleOver)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    MonthlyBudgetWidget()
} timeline: {
    MonthlyBudgetEntry(date: .now, snapshot: .sampleUnder)
    MonthlyBudgetEntry(date: .now, snapshot: .sampleOver)
}
