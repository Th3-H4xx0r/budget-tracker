import SwiftUI

/// Which way a figure moved: green with `arrow.up.right`, red with `arrow.down.right`, or
/// secondary with no arrow.
nonisolated enum ChangeDirection: Hashable, Sendable {
    case up, down, flat

    /// The direction of `delta`. Zero counts as up; nil and NaN are flat.
    init(_ delta: Double?) {
        guard let delta, !delta.isNaN else {
            self = .flat
            return
        }
        self = delta >= 0 ? .up : .down
    }

    /// The direction of a money delta. Zero counts as up; nil is flat.
    init(_ delta: Decimal?) {
        guard let delta else {
            self = .flat
            return
        }
        self = delta >= 0 ? .up : .down
    }

    var color: Color {
        switch self {
        case .up: DS.Palette.up
        case .down: DS.Palette.down
        case .flat: Color.secondary
        }
    }

    /// The SF Symbol before the change text, or nil when flat.
    var systemImage: String? {
        switch self {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: nil
        }
    }

    var accessibilityPrefix: String {
        switch self {
        case .up: String(localized: "Up")
        case .down: String(localized: "Down")
        case .flat: ""
        }
    }
}

/// The hero at the top of a value screen, Stocks style: the big figure, the change under
/// it, and one status line.
///
/// - **Value:** `.dsValueHero()`. Pass `numericValue` and the figure rolls between values
///   with `.contentTransition(.numericText(value:))`, animated by `valueAnimation`
///   (`.snappy`; pass nil while scrubbing so the label tracks the finger).
/// - **Change:** `.subheadline` semibold in green or red, with an arrow. `changeLabel` adds
///   a secondary word after it ("This month").
/// - **Status:** one `.footnote` `.secondary` line, optionally with a `StatusDot`.
///
///     HeroValueHeader(
///         MoneyFormat.string(netWorth, currencyCode: base),
///         numericValue: netWorth.doubleValue,
///         valueAnimation: isScrubbing ? nil : .snappy,
///         change: "+$420.10 (+3.2%)",
///         direction: ChangeDirection(delta),
///         status: "Updated just now",
///         statusColor: DS.Palette.success
///     )
struct HeroValueHeader<Status: View>: View {
    let value: String
    var numericValue: Double?
    var valueAnimation: Animation?
    var change: String?
    var direction: ChangeDirection
    var changeLabel: String?
    var alignment: HorizontalAlignment
    private let status: Status

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A hero with a custom status line, set in `.footnote` `.secondary`.
    init(
        _ value: String,
        numericValue: Double? = nil,
        valueAnimation: Animation? = .snappy,
        change: String? = nil,
        direction: ChangeDirection = .flat,
        changeLabel: String? = nil,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder status: () -> Status
    ) {
        self.value = value
        self.numericValue = numericValue
        self.valueAnimation = valueAnimation
        self.change = change
        self.direction = direction
        self.changeLabel = changeLabel
        self.alignment = alignment
        self.status = status()
    }

    var body: some View {
        VStack(alignment: alignment, spacing: DS.Space.xs) {
            Text(verbatim: value)
                .dsValueHero()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(numericValue.map { ContentTransition.numericText(value: $0) } ?? .identity)
                .animation(reduceMotion ? nil : valueAnimation, value: numericValue)

            if let change {
                HStack(spacing: DS.Space.xs) {
                    if let symbol = direction.systemImage {
                        Image(systemName: symbol)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: change)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let changeLabel {
                        Text(verbatim: changeLabel)
                            .fontWeight(.regular)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(direction.color)
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([direction.accessibilityPrefix, change, changeLabel ?? ""]
                    .filter { !$0.isEmpty }
                    .joined(separator: " "))
            }

            status
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

/// The plain status line of a `HeroValueHeader`: text, with an optional status dot before
/// it. Draws nothing without text.
struct HeroStatusLine: View {
    let text: String?
    var dotColor: Color?
    var pulsing = false

    var body: some View {
        if let text {
            if let dotColor {
                StatusDot(text, color: dotColor, pulsing: pulsing, font: .footnote)
            } else {
                Text(verbatim: text)
            }
        }
    }
}

extension HeroValueHeader where Status == HeroStatusLine {
    /// A hero whose status line is plain text; `statusColor` adds a dot.
    init(
        _ value: String,
        numericValue: Double? = nil,
        valueAnimation: Animation? = .snappy,
        change: String? = nil,
        direction: ChangeDirection = .flat,
        changeLabel: String? = nil,
        alignment: HorizontalAlignment = .leading,
        status: String? = nil,
        statusColor: Color? = nil,
        statusPulsing: Bool = false
    ) {
        self.init(
            value,
            numericValue: numericValue,
            valueAnimation: valueAnimation,
            change: change,
            direction: direction,
            changeLabel: changeLabel,
            alignment: alignment
        ) {
            HeroStatusLine(text: status, dotColor: statusColor, pulsing: statusPulsing)
        }
    }
}

#Preview("Hero") {
    List {
        HeroValueHeader(
            "$12,480.22",
            numericValue: 12_480.22,
            change: "+$420.10 (+3.4%)",
            direction: .up,
            changeLabel: "This month",
            status: "Updated just now",
            statusColor: DS.Palette.success
        )
        HeroValueHeader("−$318.40", change: "−2.41%", direction: .down, status: "Since March 1")
    }
}
