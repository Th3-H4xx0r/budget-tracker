import MoneyMatterKit
import SwiftUI

// Display labels for the recurring-payments screens. Members carry a `recurring` prefix
// because the enums are shared Kit types other areas may extend too.

extension SubscriptionFrequency {
    static var recurringSelectable: [SubscriptionFrequency] { allCases.filter { $0 != .unknown } }

    var recurringLabel: LocalizedStringKey {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .semiAnnual: "Every 6 months"
        case .annual: "Yearly"
        case .unknown: "Custom"
        }
    }
}

extension SubscriptionType {
    static var recurringSelectable: [SubscriptionType] { allCases.filter { $0 != .unknown } }

    var recurringLabel: LocalizedStringKey {
        switch self {
        case .subscription: "Subscription"
        case .bill: "Bill"
        case .installment: "Installment"
        case .unknown: "Other"
        }
    }

    var recurringSymbol: String {
        switch self {
        case .subscription: "repeat"
        case .bill: "doc.text"
        case .installment: "list.number"
        case .unknown: "questionmark.circle"
        }
    }
}

extension SubscriptionPeriodStatus {
    var recurringLabel: LocalizedStringKey {
        switch self {
        case .upcoming: "Upcoming"
        case .paid: "Paid"
        case .overdue: "Overdue"
        case .skipped: "Skipped"
        case .unknown: "Unknown"
        }
    }

    var recurringColor: Color {
        switch self {
        case .paid: .green
        case .overdue: .red
        case .skipped: .secondary
        case .upcoming, .unknown: .orange
        }
    }
}

extension RecurringSortKey {
    var label: LocalizedStringKey {
        switch self {
        case .dueDate: "Due Date"
        case .amount: "Amount"
        case .name: "Name"
        case .recent: "Recently Added"
        }
    }
}

extension RecurringGroupKey {
    var label: LocalizedStringKey {
        switch self {
        case .overdue: "Overdue"
        case .dueSoon: "Due Soon"
        case .thisMonth: "This Month"
        case .later: "Later"
        case .noSchedule: "No Schedule"
        case .active: "Active"
        case .paused: "Paused"
        }
    }
}

extension RecurringRemindPreset {
    var label: LocalizedStringKey {
        switch self {
        case .onDueDate: "On the due date"
        case .oneDay: "1 day before"
        case .twoDays: "2 days before"
        case .threeDays: "3 days before"
        case .fiveDays: "5 days before"
        case .oneWeek: "1 week before"
        case .twoWeeks: "2 weeks before"
        case .oneMonth: "1 month before"
        case .unknown: "Custom"
        }
    }
}

extension RecurringAutomationMode {
    var label: LocalizedStringKey {
        switch self {
        case .match: "Match imported transactions"
        case .record: "Record automatically"
        case .manual: "Manual"
        }
    }
}

extension CalendarDate {
    var recurringFormatted: String {
        startDate().formatted(date: .abbreviated, time: .omitted)
    }
}

/// The subscription's monogram: its custom initials, or the first letters of its name.
struct RecurringLogoBadge: View {
    let name: String
    let initials: String?
    let colorHex: String?
    var size: CGFloat = 36

    var body: some View {
        InitialsBadge(resolvedInitials, colorHex: colorHex, size: size)
            .accessibilityHidden(true)
    }

    private var resolvedInitials: String {
        if let initials, !initials.isEmpty { return initials }
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// "in 3 days", "today", "2 days overdue" for a due date.
struct RecurringDueText: View {
    let dueDate: CalendarDate
    let today: CalendarDate

    var body: some View {
        let days = RecurringGrouping.days(until: dueDate, today: today)
        Group {
            if days < 0 {
                Text("\(-days) days overdue").foregroundStyle(.red)
            } else if days == 0 {
                Text("Due today").foregroundStyle(.orange)
            } else if days == 1 {
                Text("Due tomorrow")
            } else {
                Text("Due in \(days) days")
            }
        }
    }
}
