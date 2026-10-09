import MoneyMatterKit
import SwiftUI

/// The date range shared by the net worth and investment reports, as a quick preset or a
/// custom range. Defaults to the last 12 months, as on the web.
struct InsightsNetWorthPeriod: Equatable {
    enum Preset: String, CaseIterable, Identifiable {
        case last3Months
        case last6Months
        case last12Months
        case thisYear
        case previousYear
        case last3Years
        case last5Years

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .last3Months: "Last 3 Months"
            case .last6Months: "Last 6 Months"
            case .last12Months: "Last 12 Months"
            case .thisYear: "This Year"
            case .previousYear: "Previous Year"
            case .last3Years: "Last 3 Years"
            case .last5Years: "Last 5 Years"
            }
        }
    }

    var preset: Preset?
    var from: CalendarDate
    var to: CalendarDate

    static func preset(_ preset: Preset, now: Date = .now) -> InsightsNetWorthPeriod {
        let current = MonthPeriod(containing: now)
        let monthsBack: Int
        switch preset {
        case .last3Months: monthsBack = 2
        case .last6Months: monthsBack = 5
        case .last12Months: monthsBack = 11
        case .last3Years: monthsBack = 35
        case .last5Years: monthsBack = 59
        case .thisYear:
            return InsightsNetWorthPeriod(
                preset: preset,
                from: CalendarDate(year: current.year, month: 1, day: 1),
                to: CalendarDate(year: current.year, month: 12, day: 31)
            )
        case .previousYear:
            return InsightsNetWorthPeriod(
                preset: preset,
                from: CalendarDate(year: current.year - 1, month: 1, day: 1),
                to: CalendarDate(year: current.year - 1, month: 12, day: 31)
            )
        }
        var start = current
        for _ in 0..<monthsBack { start = start.previous }
        return InsightsNetWorthPeriod(preset: preset, from: start.firstDay, to: current.lastDay())
    }

    static var `default`: InsightsNetWorthPeriod { .preset(.last12Months) }

    var label: String {
        let style = Date.FormatStyle().month(.abbreviated).year()
        let start = from.startDate().formatted(style)
        let end = to.startDate().formatted(style)
        return start == end ? start : "\(start) – \(end)"
    }
}

/// A toolbar menu that picks the report period: presets plus a custom range sheet.
struct InsightsNetWorthPeriodMenu: View {
    @Binding var period: InsightsNetWorthPeriod
    @State private var isCustomPresented = false

    var body: some View {
        Menu {
            Picker("Period", selection: Binding(
                get: { period.preset },
                set: { newValue in
                    if let newValue { period = .preset(newValue) }
                }
            )) {
                ForEach(InsightsNetWorthPeriod.Preset.allCases) { preset in
                    Text(preset.title).tag(Optional(preset))
                }
            }
            Divider()
            Button("Custom Range…", systemImage: "calendar") {
                isCustomPresented = true
            }
        } label: {
            Label(period.label, systemImage: "calendar")
        }
        .accessibilityLabel(Text("Period: \(period.label)"))
        .sheet(isPresented: $isCustomPresented) {
            InsightsNetWorthCustomRangeSheet(period: $period)
        }
    }
}

private struct InsightsNetWorthCustomRangeSheet: View {
    @Binding var period: InsightsNetWorthPeriod
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date

    init(period: Binding<InsightsNetWorthPeriod>) {
        _period = period
        _start = State(initialValue: period.wrappedValue.from.startDate())
        _end = State(initialValue: period.wrappedValue.to.startDate())
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Start", selection: $start, in: ...end, displayedComponents: .date)
                DatePicker("End", selection: $end, in: start..., displayedComponents: .date)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        period = InsightsNetWorthPeriod(
                            preset: nil,
                            from: CalendarDate(date: start),
                            to: CalendarDate(date: end)
                        )
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// The data-quality warning shown when a report carried holdings at cost or converted a
/// currency at a placeholder rate.
struct InsightsNetWorthDegradedNotice: View {
    let degraded: NetWorthDegraded
    private static let maxListed = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Some values are approximate", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            if !degraded.unpricedSecurities.isEmpty {
                let listed = degraded.unpricedSecurities.prefix(Self.maxListed).map(\.label).formatted(.list(type: .and))
                let extra = degraded.unpricedSecurities.count - Self.maxListed
                if extra > 0 {
                    Text("No price data for \(listed) and \(extra) more, so they're carried at cost.")
                } else {
                    Text("No price data for \(listed), so they're carried at cost.")
                }
            }
            if !degraded.fxFallbackCurrencies.isEmpty {
                Text("No exchange rate for \(degraded.fxFallbackCurrencies.formatted(.list(type: .and))), so amounts in them were converted 1:1.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .cardStyle()
    }
}

/// A titled figure for the report summary rows.
struct InsightsNetWorthStatCard<Detail: View>: View {
    let title: LocalizedStringKey
    let value: String
    var valueColor: Color = .primary
    @ViewBuilder var detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            detail
        }
        .accessibilityElement(children: .combine)
        .cardStyle()
    }
}

extension InsightsNetWorthStatCard where Detail == EmptyView {
    init(title: LocalizedStringKey, value: String, valueColor: Color = .primary) {
        self.init(title: title, value: value, valueColor: valueColor) { EmptyView() }
    }
}

/// Shared colors and formatting helpers for the net worth and investment reports.
enum InsightsNetWorthStyle {
    static let saved = Color.green
    static let grown = Color.blue
    static let liabilities = Color.red
    static let portfolioPalette: [Color] = [.blue, .orange, .purple, .pink, .teal, .indigo, .yellow, .cyan, .brown, .mint]
    static let others = Color.gray

    static func color(for kind: NetWorthAssetKind) -> Color {
        switch kind {
        case .cash: .green
        case .investments: .blue
        case .vehicles: .orange
        case .ventures: .purple
        }
    }

    static func title(for kind: NetWorthAssetKind) -> LocalizedStringKey {
        switch kind {
        case .cash: "Cash & Accounts"
        case .investments: "Investments"
        case .vehicles: "Vehicles"
        case .ventures: "Ventures"
        }
    }

    static func title(for kind: NetWorthLiabilityKind) -> LocalizedStringKey {
        switch kind {
        case .creditCard: "Credit Cards"
        case .loan: "Loans"
        case .overdraft: "Overdrafts"
        }
    }

    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// The x-axis label for a bucket, coarse enough for the granularity.
    static func bucketLabel(_ date: CalendarDate, yearly: Bool) -> String {
        if yearly { return String(date.year) }
        return date.startDate().formatted(.dateTime.month(.abbreviated).year(.twoDigits))
    }

    static func percent(_ value: Double, fractionDigits: Int = 1) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0...fractionDigits)))
    }
}

/// A colored dot and caption for chart legends.
struct InsightsNetWorthLegendItem: View {
    let title: Text
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            title.font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Wraps legend items onto as many rows as needed.
struct InsightsNetWorthFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + 6
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + 6
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
