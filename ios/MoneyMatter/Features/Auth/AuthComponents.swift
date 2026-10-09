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
        .background(DS.Surface.canvas.ignoresSafeArea())
    }
}

// MARK: - Header

/// The app mark: a 64 pt icon tile with a white glyph on a solid accent fill, corners at
/// 30 % of the side. `IconTile` draws a 15 % tint, so the solid app-icon variant lives here.
private struct AuthAppMark: View {
    var systemImage = "chart.pie.fill"
    @ScaledMetric(relativeTo: .title) private var scaledSize: CGFloat = 64

    /// Capped so the tile doesn't crowd the form at accessibility text sizes.
    private var size: CGFloat { min(scaledSize, 88) }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                DS.Palette.accent,
                in: .rect(cornerRadius: size * DS.Radius.iconTileFraction, style: .continuous)
            )
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
        VStack(spacing: DS.Space.m) {
            AuthAppMark(systemImage: systemImage)
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

/// The connected server as a `StatusBadge`-style accent capsule; tapping it starts a
/// server change. The 44 pt tap target extends beyond the small capsule.
struct ServerChip: View {
    let host: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "server.rack")
                Text(verbatim: host)
                    .truncationMode(.middle)
                Image(systemName: "chevron.right")
            }
            .dsBadge(DS.Palette.accent)
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

/// Stacks icon-led field rows in one inset-grouped panel, separated like a grouped form.
struct AuthFieldCard<Content: View>: View {
    @ViewBuilder var content: Content
    @ScaledMetric(relativeTo: .body) private var iconWidth = AuthFieldMetrics.iconWidth

    var body: some View {
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
        .background(DS.Surface.panel, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
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
                    .monospacedDigit()
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

/// An inline form error drawn as an `ErrorRow`, read by VoiceOver as one "Error:" element.
struct AuthBanner: View {
    let message: String

    var body: some View {
        ErrorRow(message)
            .fixedSize(horizontal: false, vertical: true)
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
    /// The spinner colour; prominent buttons pass `DS.Palette.onAccent` so it reads on the fill.
    var spinnerTint: Color?
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
                    .tint(spinnerTint)
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
