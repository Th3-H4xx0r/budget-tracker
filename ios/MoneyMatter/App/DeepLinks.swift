import Foundation
import MoneyMatterKit
import Observation

/// A `moneymatter://` link the signed-in shell can open.
enum AppDeepLink: Equatable {
    /// `moneymatter://home`
    case home
    /// `moneymatter://settings/monthly-budget`
    case monthlyBudgetSettings

    init?(url: URL) {
        guard url.scheme?.lowercased() == SharedContainer.homeURL.scheme else { return nil }
        let parts = ([url.host() ?? ""] + url.pathComponents)
            .filter { !$0.isEmpty && $0 != "/" }
            .map { $0.lowercased() }
        switch parts {
        case ["home"]: self = .home
        case ["settings", "monthly-budget"]: self = .monthlyBudgetSettings
        default: return nil
        }
    }
}

/// Holds a link received outside the view hierarchy (a notification tap) until the
/// signed-in shell is on screen to open it.
@Observable
final class DeepLinkInbox {
    static let shared = DeepLinkInbox()

    var pending: AppDeepLink?

    func receive(_ url: URL) {
        if let link = AppDeepLink(url: url) { pending = link }
    }
}
