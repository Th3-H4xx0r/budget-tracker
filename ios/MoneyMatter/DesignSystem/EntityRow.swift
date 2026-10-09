import SwiftUI

/// The row for one thing in a list: an account, a transaction, a budget, a payee. Use it
/// as the label of a `NavigationLink` inside a `List`, which adds the chevron and makes the
/// whole row the tap target.
///
/// - **Leading** (optional): a 32 pt `IconTile`, a logo, or a monogram.
/// - **Title:** `.headline`, one line.
/// - **Subtitle:** `.subheadline` `.secondary`, one or two lines.
/// - **Trailing:** a value (`EntityRowValue`), a `StatusDot`, or one `StatusBadge`. Never a
///   row of buttons: secondary actions go in `.swipeActions` and `.contextMenu`.
///
/// At accessibility text sizes the trailing slot moves under the text. VoiceOver reads the
/// row as one element.
///
///     NavigationLink(value: AccountsRoute.account(id: account.id)) {
///         EntityRow(account.name, subtitle: "Bank · USD", systemImage: "building.columns.fill") {
///             EntityRowValue("$2,031.08", detail: "+2.1%", detailColor: DS.Palette.up)
///         }
///     }
struct EntityRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    /// 1 or 2.
    var subtitleLineLimit: Int
    private let leading: Leading
    private let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A row with custom leading and trailing views.
    init(
        _ title: String,
        subtitle: String? = nil,
        subtitleLineLimit: Int = 1,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleLineLimit = subtitleLineLimit
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Space.m))
        layout {
            HStack(spacing: DS.Space.m) {
                leading
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(verbatim: title)
                        .font(.headline)
                        .lineLimit(stacked ? nil : 1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(stacked ? nil : min(max(subtitleLineLimit, 1), 2))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            trailing
                .layoutPriority(1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

extension EntityRow where Leading == EmptyView {
    /// A row with no leading image.
    init(_ title: String, subtitle: String? = nil, subtitleLineLimit: Int = 1, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, subtitle: subtitle, subtitleLineLimit: subtitleLineLimit) {
            EmptyView()
        } trailing: {
            trailing()
        }
    }
}

extension EntityRow where Leading == EmptyView, Trailing == EmptyView {
    /// A text-only row.
    init(_ title: String, subtitle: String? = nil, subtitleLineLimit: Int = 1) {
        self.init(title, subtitle: subtitle, subtitleLineLimit: subtitleLineLimit) {
            EmptyView()
        } trailing: {
            EmptyView()
        }
    }
}

extension EntityRow where Leading == IconTile<IconTileSymbol> {
    /// A row led by a 32 pt `IconTile` around an SF Symbol.
    init(
        _ title: String,
        subtitle: String? = nil,
        subtitleLineLimit: Int = 1,
        systemImage: String,
        tint: Color = DS.Palette.accent,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(title, subtitle: subtitle, subtitleLineLimit: subtitleLineLimit) {
            IconTile(systemImage: systemImage, color: tint)
        } trailing: {
            trailing()
        }
    }
}

extension EntityRow where Leading == IconTile<IconTileSymbol>, Trailing == EmptyView {
    /// A row led by a 32 pt `IconTile`, with nothing trailing.
    init(_ title: String, subtitle: String? = nil, subtitleLineLimit: Int = 1, systemImage: String, tint: Color = DS.Palette.accent) {
        self.init(title, subtitle: subtitle, subtitleLineLimit: subtitleLineLimit, systemImage: systemImage, tint: tint) {
            EmptyView()
        }
    }
}

/// A trailing figure for an `EntityRow`: the value in `.body` with monospaced digits over
/// an optional `.footnote` detail. Colour only for meaning.
///
///     EntityRowValue("$2,031.08", detail: "+$41.48 · +2.08%", detailColor: DS.Palette.up)
struct EntityRowValue: View {
    let value: String
    var valueColor: Color?
    var detail: String?
    var detailColor: Color?

    init(_ value: String, color: Color? = nil, detail: String? = nil, detailColor: Color? = nil) {
        self.value = value
        self.valueColor = color
        self.detail = detail
        self.detailColor = detailColor
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.Space.xxs) {
            Text(verbatim: value)
                .font(.body)
                .foregroundStyle(valueColor ?? Color.primary)
            if let detail {
                Text(verbatim: detail)
                    .font(.footnote)
                    .foregroundStyle(detailColor ?? Color.secondary)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// A tinted rounded square holding a glyph: the colour at 15 % behind the glyph in the
/// colour. Corners are 30 % of the side, continuous. Scales with Dynamic Type.
///
///     IconTile(systemImage: "cart.fill", color: categoryColor)
///     IconTile(color: .blue, size: 64) { Image("Logo").resizable() }
struct IconTile<Glyph: View>: View {
    let color: Color
    private let glyph: Glyph
    @ScaledMetric private var size: CGFloat

    /// Any glyph (a brand mark, a monogram) at half the tile's side.
    init(color: Color = DS.Palette.accent, size: CGFloat = IconTileMetrics.size, @ViewBuilder glyph: () -> Glyph) {
        self.color = color
        self.glyph = glyph()
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        glyph
            .frame(width: size * 0.5, height: size * 0.5)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(DS.tintFill), in: .rect(cornerRadius: size * DS.Radius.iconTileFraction, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension IconTile where Glyph == IconTileSymbol {
    /// A tile around an SF Symbol.
    init(systemImage: String, color: Color = DS.Palette.accent, size: CGFloat = IconTileMetrics.size) {
        self.init(color: color, size: size) { IconTileSymbol(systemImage: systemImage) }
    }
}

extension IconTile where Glyph == IconTileText {
    /// A tile around one or two letters, for monograms and categories without a symbol.
    init(text: String, color: Color = DS.Palette.accent, size: CGFloat = IconTileMetrics.size) {
        self.init(color: color, size: size) { IconTileText(text: text) }
    }
}

nonisolated enum IconTileMetrics {
    /// The row tile's side.
    static let size: CGFloat = 32
}

/// The symbol inside an `IconTile`, scaled to fit the glyph box.
struct IconTileSymbol: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
    }
}

/// Letters inside an `IconTile`, fitted to the glyph box.
struct IconTileText: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 100, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.01)
            .lineLimit(1)
    }
}

/// The Settings-app row icon: a white filled glyph on a solid 30 pt rounded square with
/// 24 % corners. Only for navigation lists such as the Settings hub, where the colour tells
/// destinations apart.
///
///     Label { Text("Categories") } icon: { SettingsIconTile(systemImage: "tag", color: .orange) }
struct SettingsIconTile: View {
    let systemImage: String
    let color: Color

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 30

    init(systemImage: String, color: Color) {
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Image(systemName: systemImage)
            .symbolVariant(.fill)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: .rect(cornerRadius: size * DS.Radius.settingsTileFraction, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview("Rows") {
    NavigationStack {
        List {
            Section("Accounts") {
                NavigationLink(value: 1) {
                    EntityRow("Checking", subtitle: "Bank · USD", systemImage: "building.columns.fill") {
                        EntityRowValue("$2,031.08", detail: "+2.08%", detailColor: DS.Palette.up)
                    }
                }
                NavigationLink(value: 2) {
                    EntityRow("Credit card", subtitle: "Card") {
                        IconTile(text: "CC", color: .orange)
                    } trailing: {
                        StatusBadge(label: "Archived", color: .secondary)
                    }
                }
            }
            Section {
                Label { Text(verbatim: "Categories") } icon: { SettingsIconTile(systemImage: "tag", color: .orange) }
                Label { Text(verbatim: "Security") } icon: { SettingsIconTile(systemImage: "lock", color: .gray) }
            }
        }
        .navigationDestination(for: Int.self) { Text(verbatim: "Detail \($0)") }
    }
}
