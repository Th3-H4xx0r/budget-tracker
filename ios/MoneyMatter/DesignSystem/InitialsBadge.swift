import MoneyMatterKit
import SwiftUI

/// A monogram in `IconTile` styling, for avatars and logo-less accounts or payees: up to
/// two letters in the colour on a 15 % tint of it, with 30 % continuous corners.
struct InitialsBadge: View {
    let text: String
    var colorHex: String?
    private let size: CGFloat

    init(_ text: String, colorHex: String? = nil, size: CGFloat = 32) {
        self.text = text
        self.colorHex = colorHex
        self.size = size
    }

    var body: some View {
        IconTile(
            text: String(text.prefix(2)).uppercased(),
            color: Color(hex: colorHex) ?? DS.Palette.accent,
            size: size
        )
    }
}

/// The signed-in user's initials as a toolbar button that opens Settings. Home places it
/// in its trailing toolbar slot.
struct ProfileButton: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.presentSettings()
        } label: {
            InitialsBadge(session.user?.initials ?? "?", size: 30)
        }
        .accessibilityLabel("Profile and Settings")
    }
}

#Preview {
    HStack {
        InitialsBadge("PK")
        InitialsBadge("LL", colorHex: "#aa3300", size: 44)
    }
}
