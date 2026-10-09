import SwiftUI

/// The symbol, title, and explanation at the top of the auth screens.
struct AuthHeader: View {
    let title: LocalizedStringKey
    let subtitle: Text
    var systemImage = "chart.pie.fill"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            subtitle
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }
}

/// Stacks fields in one rounded group with separators, like a grouped form section.
struct AuthFieldGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    subviews[index]
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                    if index < subviews.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

/// A server or validation message under a form.
struct FormMessage: View {
    let text: String
    var isError = true

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "info.circle.fill")
        }
        .font(.footnote)
        .foregroundStyle(isError ? Color.red : Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A full-width button label that swaps to a spinner while its action runs.
struct ProgressButtonLabel: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let isWorking: Bool

    var body: some View {
        ZStack {
            Group {
                if let systemImage {
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

extension View {
    /// Centres auth content in a readable column.
    func authColumn() -> some View {
        self
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
    }
}
