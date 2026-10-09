import SwiftUI

/// A secondary action as an accent-coloured list row: a leading symbol and a label, the
/// whole row tappable. Use it instead of tinted capsule buttons.
///
///     Section {
///         InlineActionRow("Add budget", systemImage: "plus") { isAdding = true }
///         InlineActionRow("Delete account", systemImage: "trash", role: .destructive) { … }
///     }
struct InlineActionRow: View {
    let title: String
    var systemImage: String?
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: DS.Space.m) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .fontWeight(.semibold)
                        .frame(width: IconTileMetrics.size)
                        .accessibilityHidden(true)
                }
                Text(verbatim: title)
                Spacer(minLength: 0)
            }
            .font(.body)
            .foregroundStyle(role == .destructive ? AnyShapeStyle(DS.Palette.danger) : AnyShapeStyle(.tint))
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }
}

/// A group header outside a list section: `.title3.bold()` in sentence case, with an
/// optional trailing accessory such as a small segmented `Picker` or a "See all" button.
///
///     DSGroupHeader("Spending") {
///         Picker("Range", selection: $range) { … }
///             .pickerStyle(.segmented)
///             .fixedSize()
///     }
struct DSGroupHeader<Accessory: View>: View {
    let title: String
    private let accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s) {
            Text(verbatim: title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.s)
            accessory
                .font(.subheadline)
        }
        .textCase(nil)
    }
}

extension DSGroupHeader where Accessory == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// An inline error: red text on a 15 % red tint with 12 pt continuous corners, and an
/// optional Retry that shows a spinner while it runs. Failures stay in the interface
/// rather than in an alert.
///
///     ErrorRow("Couldn't load accounts.") { await model.reload() }
///     ErrorRow(title: "Can't Connect", message: "Check your connection.")
struct ErrorRow: View {
    let title: String?
    let message: String
    var retry: (() async -> Void)?

    @State private var isRetrying = false
    @Environment(\.colorScheme) private var colorScheme

    init(_ message: String, retry: (() async -> Void)? = nil) {
        self.title = nil
        self.message = message
        self.retry = retry
    }

    init(title: String?, message: String, retry: (() async -> Void)? = nil) {
        self.title = title
        self.message = message
        self.retry = retry
    }

    var body: some View {
        let ink = DS.Palette.onTint(DS.Palette.danger, in: colorScheme)
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                if let title {
                    Text(verbatim: title)
                        .font(.subheadline.weight(.semibold))
                }
                Text(verbatim: message)
                    .font(.subheadline)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button {
                    isRetrying = true
                    Task {
                        await retry()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                    } else {
                        Text("Retry")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .disabled(isRetrying)
            }
        }
        .padding(DS.Space.l)
        .background(DS.Palette.danger.opacity(DS.tintFill), in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
    }
}

/// A 44 pt Liquid Glass circle with a symbol, for the floating controls on hero screens
/// (Home's notifications and profile buttons). An optional badge count sits on its corner.
///
///     GlassCircleButton(systemImage: "bell", badge: unreadCount, accessibilityLabel: "Notifications") {
///         isShowingNotifications = true
///     }
struct GlassCircleButton<Label: View>: View {
    let accessibilityLabel: String
    var badge: Int
    let action: () -> Void
    private let label: Label

    init(badge: Int = 0, accessibilityLabel: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.badge = badge
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .overlay(alignment: .topTrailing) {
            if badge > 0 {
                Text(verbatim: badge > 99 ? "99+" : "\(badge)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.onAccent)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(DS.Palette.accent, in: .capsule)
                    .offset(x: 4, y: -4)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(badge > 0 ? Text("\(badge) unread") : Text(verbatim: ""))
    }
}

extension GlassCircleButton where Label == Image {
    init(systemImage: String, badge: Int = 0, accessibilityLabel: String, action: @escaping () -> Void) {
        self.init(badge: badge, accessibilityLabel: accessibilityLabel, action: action) {
            Image(systemName: systemImage)
        }
    }
}

#Preview {
    List {
        Section {
            InlineActionRow("Add budget", systemImage: "plus") {}
            InlineActionRow("Delete account", systemImage: "trash", role: .destructive) {}
        } header: {
            DSGroupHeader("Budgets")
        }
        ErrorRow("Couldn't load accounts.") {}
        HStack {
            GlassCircleButton(systemImage: "bell", badge: 3, accessibilityLabel: "Notifications") {}
            GlassCircleButton(systemImage: "person.crop.circle", accessibilityLabel: "Profile") {}
        }
    }
}
