import SwiftUI

// MARK: - Screen

/// A scrollable auth screen: a centred column, at most 420pt wide, over the brand background.
/// The column is vertically centred while it fits and scrolls once Dynamic Type or the keyboard
/// makes it taller than the screen.
struct AuthScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background { AuthBackground() }
    }
}

/// The grouped background with a soft accent glow at the top.
struct AuthBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let radius = max(proxy.size.width, proxy.size.height) * 0.6
            ZStack {
                Color(.systemGroupedBackground)
                RadialGradient(
                    colors: [Color.accentColor.opacity(glowOpacity), Color.accentColor.opacity(0)],
                    center: .top,
                    startRadius: 0,
                    endRadius: radius
                )
                RadialGradient(
                    colors: [Color.indigo.opacity(glowOpacity * 0.5), Color.indigo.opacity(0)],
                    center: UnitPoint(x: 0.95, y: 0),
                    startRadius: 0,
                    endRadius: radius * 0.6
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var glowOpacity: Double { colorScheme == .dark ? 0.3 : 0.18 }
}

// MARK: - Header

/// The app mark as an app-icon-style tile: a white symbol on an accent gradient.
struct AppMarkBadge: View {
    var systemImage = "chart.pie.fill"
    @ScaledMetric(relativeTo: .title) private var scaledSize: CGFloat = 64

    /// Capped so the tile doesn't crowd the form at accessibility text sizes.
    private var size: CGFloat { min(scaledSize, 88) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.mix(with: .white, by: 0.18),
                            Color.accentColor.mix(with: .black, by: 0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
            .shadow(color: Color.accentColor.opacity(0.35), radius: 14, y: 6)
            .accessibilityHidden(true)
    }
}

/// The app mark, a title, an optional explanation, and an optional accessory such as the server chip.
struct AuthHeader<Accessory: View>: View {
    let title: Text
    var subtitle: Text?
    var systemImage = "chart.pie.fill"
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 14) {
            AppMarkBadge(systemImage: systemImage)
            VStack(spacing: 6) {
                title
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    subtitle
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            accessory
        }
        .frame(maxWidth: .infinity)
    }
}

extension AuthHeader where Accessory == EmptyView {
    init(title: Text, subtitle: Text? = nil, systemImage: String = "chart.pie.fill") {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage) { EmptyView() }
    }
}

/// A compact capsule showing the connected server; tapping it starts a server change.
struct ServerChip: View {
    let host: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .imageScale(.small)
                Text(verbatim: host)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: .capsule)
            .overlay { Capsule().strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5) }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Server: \(host)"))
        .accessibilityHint(Text("Choose a different server."))
    }
}

// MARK: - Fields

private enum AuthFieldMetrics {
    static let iconWidth: CGFloat = 22
    static let leadingPadding: CGFloat = 16
    static let iconSpacing: CGFloat = 12
}

/// Stacks icon-led field rows in one rounded material card, separated like a grouped form.
struct AuthFieldCard<Content: View>: View {
    @ViewBuilder var content: Content
    @ScaledMetric(relativeTo: .body) private var iconWidth = AuthFieldMetrics.iconWidth

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    subviews[index]
                    if index < subviews.count - 1 {
                        Divider()
                            .padding(.leading, AuthFieldMetrics.leadingPadding + iconWidth + AuthFieldMetrics.iconSpacing)
                    }
                }
            }
        }
        .background(.regularMaterial, in: shape)
        .overlay { shape.strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5) }
    }
}

/// One field in an `AuthFieldCard`, led by a symbol that takes the tint while the field has focus.
struct AuthFieldRow<Field: View>: View {
    let systemImage: String
    var isActive = false
    @ViewBuilder var field: Field
    @ScaledMetric(relativeTo: .body) private var iconWidth = AuthFieldMetrics.iconWidth

    var body: some View {
        HStack(spacing: AuthFieldMetrics.iconSpacing) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            field
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, AuthFieldMetrics.leadingPadding)
        .padding(.trailing, 12)
        .frame(minHeight: 52)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

/// A password field with a show/hide toggle. Focus follows the field across the toggle.
struct PasswordField<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let focus: FocusState<Value?>.Binding
    let focusValue: Value
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if isRevealed {
                    TextField(title, text: $text, prompt: Text(title))
                } else {
                    SecureField(title, text: $text, prompt: Text(title))
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused(focus, equals: focusValue)

            Button {
                let wasFocused = focus.wrappedValue == focusValue
                isRevealed.toggle()
                // The swapped-in field is a new view, so focus is handed to it on the next update.
                if wasFocused {
                    Task { focus.wrappedValue = focusValue }
                }
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(isRevealed ? Text("Hide Password") : Text("Show Password"))
        }
    }
}

/// Password strength under the sign-up form: a four-segment meter plus the length rule.
struct PasswordStrengthHint: View {
    let password: String
    let minimumLength: Int
    let isTooShort: Bool

    private enum Strength: Int {
        case tooShort, weak, fair, good, strong
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !password.isEmpty {
                HStack(spacing: 4) {
                    ForEach(1...4, id: \.self) { segment in
                        Capsule()
                            .fill(segment <= max(strength.rawValue, 1) ? color : Color(.tertiarySystemFill))
                            .frame(height: 4)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: strength)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isTooShort {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
                if let label, !isTooShort {
                    Text(label).fontWeight(.semibold).foregroundStyle(.primary)
                }
                Text("Use at least \(minimumLength) characters for your password.")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var strength: Strength {
        guard password.count >= minimumLength else { return .tooShort }
        let classes = [
            password.contains(where: \.isLowercase),
            password.contains(where: \.isUppercase),
            password.contains(where: \.isNumber),
            password.contains { !$0.isLetter && !$0.isNumber }
        ].filter { $0 }.count
        var score = 1
        if password.count >= 12 { score += 1 }
        if classes >= 3 { score += 1 }
        if classes == 4 || password.count >= 16 { score += 1 }
        return Strength(rawValue: min(score, 4)) ?? .strong
    }

    private var label: LocalizedStringKey? {
        switch strength {
        case .tooShort: nil
        case .weak: "Weak."
        case .fair: "Fair."
        case .good: "Good."
        case .strong: "Strong."
        }
    }

    private var color: Color {
        switch strength {
        case .tooShort: .red
        case .weak: .orange
        case .fair: .yellow
        case .good: .mint
        case .strong: .green
        }
    }
}

// MARK: - Messages

/// An inline error banner: a warning symbol and the message on a red-tinted material.
struct AuthBanner: View {
    let message: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            ZStack {
                shape.fill(.regularMaterial)
                shape.fill(Color.red.opacity(0.14))
            }
        }
        .overlay { shape.strokeBorder(Color.red.opacity(0.3), lineWidth: 0.75) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Error: \(message)"))
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
    }
}

/// A divider with a short centred caption, such as "or continue with".
struct AuthSeparator: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            VStack { Divider() }
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            VStack { Divider() }
        }
    }
}

// MARK: - Buttons

/// A full-width button label that swaps to a spinner while its action runs.
/// `image` is for brand marks; pass it with the rendering mode the mark needs.
struct ProgressButtonLabel: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var image: Image?
    let isWorking: Bool
    @ScaledMetric(relativeTo: .body) private var markSize: CGFloat = 18

    var body: some View {
        ZStack {
            Group {
                if let image {
                    HStack(spacing: 8) {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: markSize, height: markSize)
                            .accessibilityHidden(true)
                        Text(title)
                    }
                } else if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .opacity(isWorking ? 0 : 1)
            if isWorking {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .fontWeight(.semibold)
    }
}

/// A one-line footer link: a muted question followed by the action in the tint colour.
struct AuthFooterLink: View {
    let prompt: LocalizedStringKey
    let action: LocalizedStringKey
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            Text("\(Text(prompt).foregroundStyle(.secondary)) \(Text(action).fontWeight(.semibold).foregroundStyle(.tint))")
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .font(.subheadline)
        .buttonStyle(.plain)
    }
}
