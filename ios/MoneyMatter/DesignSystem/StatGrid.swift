import SwiftUI

/// A Stocks-style grid of figures: two or three equal columns of `StatCell`s, filled left
/// to right, then top to bottom. It sits directly on its surface (a `List` row or a
/// `DSCard`); never on a grey tile.
///
/// At accessibility text sizes the grid drops one column (3 → 2, 2 → 1), so values wrap
/// instead of truncating.
///
///     Section("Details") {
///         StatGrid {
///             StatCell(label: "Account", value: "Checking")
///             StatCell(label: "Category", value: "Groceries")
///             StatCell(label: "Change", value: "+$62.13", valueColor: DS.Palette.up)
///         }
///     }
struct StatGrid<Content: View>: View {
    /// 2 or 3 (clamped to 1...3).
    let columns: Int
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat
    private let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        columns: Int = 2,
        horizontalSpacing: CGFloat = 16,
        verticalSpacing: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.columns = columns
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    var body: some View {
        StatGridLayout(
            columns: Self.effectiveColumns(columns, dynamicTypeSize),
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        ) {
            content
        }
    }

    /// The request clamped to 1...3, minus one at accessibility text sizes (never below 1).
    static func effectiveColumns(_ requested: Int, _ size: DynamicTypeSize) -> Int {
        let clamped = min(max(requested, 1), 3)
        return size.isAccessibilitySize ? max(clamped - 1, 1) : clamped
    }
}

/// One figure in a `StatGrid`: a `.caption` `.secondary` label over a `.body` value with
/// monospaced digits, and an optional `.caption2` footnote. VoiceOver reads it as one
/// element.
///
///     StatCell(label: "Spent", value: "$1,204.18")
///     StatCell(label: "Change", value: "+$62.13", valueColor: DS.Palette.up, footnote: "+12%")
///     StatCell(label: "Amount") { AmountText(transaction: transaction) }
struct StatCell<Value: View>: View {
    let label: String
    var footnote: String?
    private let value: Value

    /// A cell with a custom value view. It gets `.body` and monospaced digits unless it
    /// sets its own.
    init(label: String, footnote: String? = nil, @ViewBuilder value: () -> Value) {
        self.label = label
        self.footnote = footnote
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            value
                .font(.body)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let footnote {
                Text(verbatim: footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension StatCell where Value == Text {
    /// A cell showing `value` as text, in `valueColor` (primary by default). Keep colour
    /// for meaning: green or red changes, or a warning.
    init(label: String, value: String, valueColor: Color? = nil, footnote: String? = nil) {
        self.init(label: label, footnote: footnote) {
            Text(verbatim: value).foregroundStyle(valueColor ?? Color.primary)
        }
    }
}

/// Equal-width columns; each row is as tall as its tallest cell, and cells are pinned to
/// the top-leading corner of their slot.
private struct StatGridLayout: Layout {
    let columns: Int
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth(subviews)
        let heights = rowHeights(subviews, columnWidth: columnWidth(width))
        let height = heights.reduce(0, +) + verticalSpacing * CGFloat(max(heights.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let colWidth = columnWidth(bounds.width)
        var y = bounds.minY
        for (row, height) in rowHeights(subviews, columnWidth: colWidth).enumerated() {
            for col in 0..<columns {
                let index = row * columns + col
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(col) * (colWidth + horizontalSpacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: colWidth, height: height)
                )
            }
            y += height + verticalSpacing
        }
    }

    private func columnWidth(_ total: CGFloat) -> CGFloat {
        max((total - horizontalSpacing * CGFloat(columns - 1)) / CGFloat(columns), 0)
    }

    private func rowHeights(_ subviews: Subviews, columnWidth: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
                .max() ?? 0
        }
    }

    /// The width with no proposal: every column as wide as the widest cell.
    private func idealWidth(_ subviews: Subviews) -> CGFloat {
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return widest * CGFloat(columns) + horizontalSpacing * CGFloat(columns - 1)
    }
}

#Preview {
    List {
        Section("Details") {
            StatGrid(columns: 3) {
                StatCell(label: "Income", value: "$4,200.00", valueColor: DS.Palette.up)
                StatCell(label: "Spent", value: "$2,180.40")
                StatCell(label: "Saved", value: "48%")
            }
        }
    }
    .listStyle(.insetGrouped)
}
