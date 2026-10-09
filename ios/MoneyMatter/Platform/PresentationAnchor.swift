import AuthenticationServices
import UIKit

/// The person dismissed a system sign-in sheet. Callers treat it as a no-op, not an error.
struct AuthenticationCancelled: Error, Equatable {}

enum PresentationAnchor {
    /// The key window of the foreground scene, for system authentication sheets.
    static func current() -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let window = scene?.keyWindow ?? scene?.windows.first {
            return window
        }
        guard let scene else {
            preconditionFailure("A sign-in sheet was requested with no window scene connected.")
        }
        return UIWindow(windowScene: scene)
    }
}
