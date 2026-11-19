import MoneyMatterKit
import SwiftUI

/// The "Update available" card: the app mark, version and size, what's new, and Install Now.
struct AppUpdateSheet: View {
    let offer: AppUpdateOffer
    var installing = false
    var error: String?
    var onInstall: () -> Void = {}
    var onLater: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.xl) {
                header
                if !items.isEmpty { whatsNew }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DS.Space.xl)
        }
        .safeAreaInset(edge: .bottom) { actions }
    }

    private var header: some View {
        VStack(spacing: DS.Space.s) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(DS.Palette.onAccent)
                .frame(width: 72, height: 72)
                .background(DS.Palette.accent, in: .rect(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            Text("Update available")
                .font(.title2.weight(.semibold))
                .padding(.top, DS.Space.xs)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    /// "Version 1.2 (build 263022206) · 67.6 MB"; the build as digits, never "263,022,206".
    private var subtitle: String {
        var parts = [offer.version.isEmpty
            ? String(localized: "Build \(String(offer.build))")
            : String(localized: "Version \(offer.version) (build \(String(offer.build)))")]
        if offer.size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: offer.size, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    /// The notes one line per item, with the bullet the publisher typed taken off.
    private var items: [String] {
        offer.notes.split(whereSeparator: \.isNewline).map {
            var line = $0.trimmingCharacters(in: .whitespaces)
            if let first = line.first, "•-*".contains(first) { line.removeFirst() }
            return line.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    private var whatsNew: some View {
        DSCard("What\u{2019}s New") {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
                        Text(verbatim: "•").foregroundStyle(.secondary)
                        Text(item).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(spacing: DS.Space.s) {
            Button(action: onInstall) {
                Group {
                    if installing { ProgressView() } else { Text("Install Now") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(installing)
            Button("Not Now", action: onLater)
                .controlSize(.large)
                .disabled(installing)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.m)
        .background(.bar)
    }
}

/// The card bound to the live center, over a dimmed backdrop; shown in an `OverlayWindow`.
struct AppUpdateCard: View {
    let center: AppUpdateCenter

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { if !center.installing { center.later() } }
            if let offer = center.offer {
                AppUpdateSheet(
                    offer: offer,
                    installing: center.installing,
                    error: center.error,
                    onInstall: { Task { await center.install() } },
                    onLater: { center.later() }
                )
                .frame(maxWidth: 460, maxHeight: 460)
                .background(.regularMaterial, in: .rect(cornerRadius: 28, style: .continuous))
                .padding(DS.Space.m)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.12), value: center.offer)
    }
}

#Preview {
    Color.clear.overlay {
        AppUpdateSheet(
            offer: AppUpdateOffer(
                build: 263_022_206,
                version: "1.2",
                notes: "• Faster sync\n• Fixes for the review stack",
                installURL: URL(string: "itms-services://x")!,
                size: 67_627_216
            )
        )
    }
}
