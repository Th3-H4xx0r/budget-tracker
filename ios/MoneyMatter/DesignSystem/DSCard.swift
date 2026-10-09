import SwiftUI

/// The container for a hero or a chart: a solid secondary grouped panel with 22 pt
/// continuous corners and 16 pt padding. No blur, border, gradient or shadow, as in Stocks
/// and Wallet.
///
/// Only for content that is not row-shaped (a balance chart, a spending donut, a hero
/// figure). Rows and key-value pairs go in an inset-grouped `List`. Never nest a card in a
/// card. `.cardStyle()` and `.glassCardStyle()` draw the same panel.
///
///     DSCard("Spending") {
///         SpendingDonut(...)
///     }
struct DSCard<Content: View>: View {
    private let title: String?
    private let padding: EdgeInsets
    private let content: Content

    /// `padding` defaults to `DS.cardPadding` (16) on every side.
    init(padding: CGFloat = DS.cardPadding, @ViewBuilder content: () -> Content) {
        self.title = nil
        self.padding = EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
        self.content = content()
    }

    init(padding: EdgeInsets, @ViewBuilder content: () -> Content) {
        self.title = nil
        self.padding = padding
        self.content = content()
    }

    /// A card with a `.headline` title over its content, 12 pt apart.
    init(_ title: String, padding: CGFloat = DS.cardPadding, @ViewBuilder content: () -> Content) {
        self.title = title
        self.padding = EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
        self.content = content()
    }

    var body: some View {
        Group {
            if let title {
                VStack(alignment: .leading, spacing: DS.cardGroupSpacing) {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    content
                }
            } else {
                content
            }
        }
        .dsCardSurface(padding: padding, cornerRadius: DS.Radius.card)
    }
}

extension View {
    /// The `DSCard` panel around any content: padding, full width, the panel colour on a
    /// continuous rounded rectangle.
    func dsCardSurface(padding: EdgeInsets, cornerRadius: CGFloat = DS.Radius.card) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Surface.panel, in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            DSCard {
                HeroValueHeader("$5,890.05", change: "+$62.13 (+1.07%)", direction: .up, status: "Updated just now")
            }
            DSCard("Spending") {
                Text(verbatim: "A chart goes here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding()
    }
    .background(DS.Surface.canvas)
}
