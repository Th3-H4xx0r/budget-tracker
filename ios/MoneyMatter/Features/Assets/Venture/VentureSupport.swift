import MoneyMatterKit
import SwiftUI

/// Display names for venture enums.
enum VentureLabels {
    static func status(_ value: VentureDealStatus) -> LocalizedStringResource {
        switch value {
        case .outstanding: "Outstanding"
        case .partialExit: "Partial Exit"
        case .fullyExited: "Fully Exited"
        case .writtenOff: "Written Off"
        case .unknown: "Unknown"
        }
    }

    static func eventType(_ value: VentureEventType) -> LocalizedStringResource {
        switch value {
        case .initialInvestment: "Initial Investment"
        case .capitalCall: "Capital Call"
        case .distribution: "Distribution"
        case .navUpdate: "NAV Update"
        case .exit: "Exit"
        case .writedown: "Write-Down"
        case .feePayment: "Fee Payment"
        case .unknown: "Event"
        }
    }

    static func cashFlow(_ value: VentureCashFlowMode) -> LocalizedStringResource {
        switch value {
        case .linked: "Linked Transactions"
        case .outOfWallet: "Outside Tracked Accounts"
        case .none: "No Cash Movement"
        case .unknown: "Unknown"
        }
    }

    static func spvSubtype(_ value: VentureSPVSubtype) -> LocalizedStringResource {
        switch value {
        case .singleCompany: "Single Company"
        case .multiCompany: "Multi Company"
        case .unknown: "Other"
        }
    }

    static func eventSymbol(_ value: VentureEventType) -> String {
        switch value {
        case .initialInvestment: "arrow.down.to.line"
        case .capitalCall: "arrow.down.circle"
        case .distribution: "arrow.up.circle"
        case .navUpdate: "chart.line.uptrend.xyaxis"
        case .exit: "flag.checkered"
        case .writedown: "arrow.down.right"
        case .feePayment: "percent"
        case .unknown: "circle"
        }
    }

    static func statusColor(_ value: VentureDealStatus) -> Color {
        switch value {
        case .outstanding: .blue
        case .partialExit: .orange
        case .fullyExited: .green
        case .writtenOff: .secondary
        case .unknown: .secondary
        }
    }
}

/// A capsule with the deal's status.
struct VentureStatusBadge: View {
    let status: VentureDealStatus

    var body: some View {
        Text(VentureLabels.status(status))
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(VentureLabels.statusColor(status))
            .background(VentureLabels.statusColor(status).opacity(0.14), in: .capsule)
    }
}

/// Formatting and parsing for venture fractions and multiples.
enum VentureFormat {
    /// `0.2` → `20%`.
    static func percent(_ fraction: Decimal?, signed: Bool = false) -> String {
        guard let fraction else { return "—" }
        let value = NSDecimalNumber(decimal: fraction).doubleValue
        var style = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(0...2))
        if signed { style = style.sign(strategy: .always(includingZero: false)) }
        return value.formatted(style)
    }

    /// `1.53` → `1.53x`.
    static func multiple(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let number = NSDecimalNumber(decimal: value).doubleValue
        return number.formatted(.number.precision(.fractionLength(2))) + "x"
    }

    /// `0.2` → `"20"` for a percent text field.
    static func percentText(_ fraction: Decimal) -> String {
        EditorAmountParser.text(fraction * 100)
    }

    /// `"20"` → `0.2`; nil when the text isn't a number between 0 and 100.
    static func fraction(fromPercentText text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        guard let percent = EditorAmountParser.parse(trimmed), percent >= 0, percent <= 100 else { return nil }
        return percent / 100
    }

    static func date(_ day: CalendarDate) -> String {
        day.startDate().formatted(date: .abbreviated, time: .omitted)
    }
}

/// A labelled text field for numbers, right-aligned with tabular digits.
struct VentureNumberField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var prompt: LocalizedStringKey = "0"

    var body: some View {
        LabeledContent(title) {
            TextField(prompt, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}
