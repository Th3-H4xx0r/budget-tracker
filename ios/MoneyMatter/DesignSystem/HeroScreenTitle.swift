import SwiftUI

extension View {
    /// The "hero as title" pattern of Stocks, Wallet and Health for screens led by a big
    /// money figure: the bar stays inline, and its compact title fades in only once the
    /// hero has scrolled away, so the title never competes with the figure.
    ///
    /// Track the hero with `.onScrollVisibilityChange(threshold: 0.1)` on its amount view,
    /// inside the scroll or list content. List screens without a hero keep the large title.
    ///
    ///     @State private var heroVisible = true
    ///
    ///     List {
    ///         HeroValueHeader(…)
    ///             .onScrollVisibilityChange(threshold: 0.1) { heroVisible = $0 }
    ///     }
    ///     .heroScreenTitle("Accounts", isHeroVisible: heroVisible)
    func heroScreenTitle(_ title: LocalizedStringKey, isHeroVisible: Bool) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .opacity(isHeroVisible ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: isHeroVisible)
                }
            }
    }
}
