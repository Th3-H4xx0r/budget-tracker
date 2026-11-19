import SwiftUI
import UIKit

/// A card in its own window above everything in the app, sheets and covers included, while it
/// is shown.
@MainActor
final class OverlayWindow {
    private var window: UIWindow?
    private let level: UIWindow.Level

    init(level: UIWindow.Level = .alert + 1) { self.level = level }

    /// Puts `content` up, unless it already is.
    func show(_ content: () -> some View) {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.accessibilityViewIsModal = true
        let made = UIWindow(windowScene: scene)
        made.windowLevel = level
        made.backgroundColor = .clear
        made.rootViewController = host
        made.isHidden = false
        window = made
        UIAccessibility.post(notification: .screenChanged, argument: host.view)
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }
}
