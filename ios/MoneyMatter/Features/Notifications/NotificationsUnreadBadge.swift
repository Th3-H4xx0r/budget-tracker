import MoneyMatterKit
import Observation
import SwiftUI

/// The unread notification count, shared by the Home bell and the notifications list.
@Observable
final class NotificationsUnreadCounter {
    static let shared = NotificationsUnreadCounter()

    private(set) var count = 0

    func refresh(client: APIClient?) async {
        guard let client, let latest = try? await client.send(Endpoints.inboxUnreadCount()) else { return }
        count = latest
    }

    func set(_ value: Int) {
        count = max(0, value)
    }
}

/// Overlays the unread count on the view it modifies, typically the Home bell button's
/// label, and keeps it fresh while the view is on screen.
///
/// Attach with `.notificationsUnreadBadge()`, or use `NotificationsBellLabel()` as the
/// bell button's label.
struct NotificationsUnreadBadge: ViewModifier {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var counter = NotificationsUnreadCounter.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if counter.count > 0 {
                    Text(counter.count > 99 ? "99+" : "\(counter.count)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(.red, in: .capsule)
                        .offset(x: 8, y: -6)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityValue(counter.count > 0 ? Text("\(counter.count) unread") : Text(verbatim: ""))
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await counter.refresh(client: services.client)
                    try? await Task.sleep(for: .seconds(60))
                }
            }
    }
}

extension View {
    /// Shows the unread notification count on this view. See `NotificationsUnreadBadge`.
    func notificationsUnreadBadge() -> some View {
        modifier(NotificationsUnreadBadge())
    }
}

/// A bell icon with the unread badge, for a toolbar button's label.
struct NotificationsBellLabel: View {
    var body: some View {
        Image(systemName: "bell")
            .notificationsUnreadBadge()
            .accessibilityLabel("Notifications")
    }
}
