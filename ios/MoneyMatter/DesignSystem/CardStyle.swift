import SwiftUI

extension View {
    /// The content card used on Home and in detail headers: grouped secondary background,
    /// continuous corners, no glass (content stays standard).
    func cardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Liquid Glass for interactive or floating cards only, such as the Home review card and
    /// the review stack card. Wrap sibling glass views in a `GlassEffectContainer`.
    func glassCardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = 24, tint: Color? = nil) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A card section title with an optional trailing action, e.g. "Latest Transactions · See All".
struct CardHeader<Accessory: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            accessory
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
    .background(Color(.systemGroupedBackground))
}
