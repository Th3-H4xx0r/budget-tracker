import SwiftUI

/// The app's one badge: a small capsule, `.caption2` semibold, the colour as text
/// (darkened in light mode) on a 15 % tint of itself, padded 7×3. The fraud badge,
/// "Unreviewed", "Archived" and every other tag use it. At most one badge per row.
///
/// `pulsing` adds a small fading dot inside the capsule for a live state; it holds still
/// under Reduce Motion.
///
///     StatusBadge(label: "Fraud", color: DS.Palette.danger)
///     StatusBadge(label: "Unreviewed", color: DS.Palette.warning)
struct StatusBadge: View {
    let label: String
    let color: Color
    var pulsing: Bool

    init(label: String, color: Color, pulsing: Bool = false) {
        self.label = label
        self.color = color
        self.pulsing = pulsing
    }

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            if pulsing {
                PulsingDot(color: color, size: 5, pulsing: true)
            }
            Text(verbatim: label)
        }
        .dsBadge(color)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The badge capsule shared by every small tag: `.caption2` semibold, `color` as text
    /// (via `DS.Palette.onTint`) on a 15 % capsule of `color`.
    func dsBadge(_ color: Color) -> some View {
        modifier(DSBadgeModifier(color: color))
    }
}

private struct DSBadgeModifier: ViewModifier {
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.caption2.weight(.semibold))
            .foregroundStyle(DS.Palette.onTint(color, in: colorScheme))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(DS.tintFill), in: .capsule)
    }
}

/// A small dot that fades between 40 % and full while `pulsing`, and holds still under
/// Reduce Motion.
struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 6
    var pulsing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animate = pulsing && !reduceMotion
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .phaseAnimator(animate ? [1.0, 0.4] : [1.0]) { dot, opacity in
                dot.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 1.2)
            }
            .accessibilityHidden(true)
    }
}

/// A state as a coloured 8 pt dot plus a `.secondary` word: "● Updated just now",
/// "● Paused". The dot carries the colour so lists read calmly. `pulsing` fades the dot
/// for a live state. Not a badge: for a flag, use `StatusBadge`.
///
///     StatusDot("Updated just now", color: DS.Palette.success, pulsing: true)
struct StatusDot: View {
    let label: String
    let color: Color
    var pulsing: Bool
    var font: Font

    @ScaledMetric(relativeTo: .subheadline) private var dotSize: CGFloat = 8

    init(_ label: String, color: Color, pulsing: Bool = false, font: Font = .subheadline) {
        self.label = label
        self.color = color
        self.pulsing = pulsing
        self.font = font
    }

    var body: some View {
        HStack(spacing: 6) {
            PulsingDot(color: color, size: dotSize, pulsing: pulsing)
            Text(verbatim: label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(font)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        LabeledContent("Review") { StatusBadge(label: "Fraud", color: DS.Palette.danger) }
        LabeledContent("Status") { StatusBadge(label: "Unreviewed", color: DS.Palette.warning) }
        LabeledContent("Account") { StatusBadge(label: "Archived", color: .gray) }
        LabeledContent("Sync") { StatusDot("Updated just now", color: DS.Palette.success, pulsing: true) }
    }
}
