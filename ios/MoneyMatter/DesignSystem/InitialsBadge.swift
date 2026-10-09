import MoneyMatterKit
import SwiftUI

/// A circular monogram, for avatars and logo-less accounts or payees.
struct InitialsBadge: View {
    let text: String
    var colorHex: String?
    @ScaledMetric private var size: CGFloat

    init(_ text: String, colorHex: String? = nil, size: CGFloat = 32) {
        self.text = text
        self.colorHex = colorHex
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex).map(AnyShapeStyle.init) ?? AnyShapeStyle(Color.accentColor.gradient))
            .overlay {
                Text(verbatim: String(text.prefix(2)).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
