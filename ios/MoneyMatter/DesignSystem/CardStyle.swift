import SwiftUI

extension View {
    /// The `DSCard` panel: 16 pt padding, the secondary grouped surface, 22 pt continuous
    /// corners, no shadow or border. For heroes, charts and summaries that aren't
    /// row-shaped; never nested.
    func cardStyle(padding: CGFloat = DS.cardPadding, cornerRadius: CGFloat = DS.Radius.card) -> some View {
        dsCardSurface(
            padding: EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding),
            cornerRadius: cornerRadius
        )
    }

    /// The same `DSCard` panel as `cardStyle()`: Liquid Glass is reserved for floating
    /// controls, never cards. A `tint` lays a 15 % wash of that colour over the panel, for
    /// state feedback such as a review card mid-swipe.
    func glassCardStyle(padding: CGFloat = DS.cardPadding, cornerRadius: CGFloat = DS.Radius.card, tint: Color? = nil) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                ZStack {
                    shape.fill(DS.Surface.panel)
                    if let tint {
                        shape.fill(tint.opacity(DS.tintFill))
                    }
                }
            }
    }
}

/// A card's title: plain `.headline` primary text (no icon, colour or upper case), with an
/// optional trailing accessory in `.subheadline`, e.g. "Latest transactions · See all".
struct CardHeader<Accessory: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.s)
            accessory
                .font(.subheadline)
        }
    }
}

extension CardHeader where Accessory == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title: title) { EmptyView() }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Latest Transactions") {
                    Button("See All") {}
                }
                Text("Card content")
            }
            .cardStyle()

            Label("12 transactions to review", systemImage: "checkmark.shield")
                .glassCardStyle()
        }
        .padding()
    }
    .background(DS.Surface.canvas)
}
