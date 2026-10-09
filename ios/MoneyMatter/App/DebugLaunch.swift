#if DEBUG
import Foundation
import MoneyMatterKit

/// Debug-only launch seeding for simulator QA and screenshots. `xcrun simctl launch` forwards
/// `SIMCTL_CHILD_`-prefixed variables into the app's environment:
/// - `MM_DEBUG_SERVER` + `MM_DEBUG_TOKEN`: saved before session restore, so launch signs straight in.
/// - `MM_DEBUG_SCREEN`: `accounts`, `transactions`, `planning`, `insights`, `review-page`, `review-stack`, or `settings`.
enum DebugLaunch {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static func seedSession(serverStore: any ServerStoring, tokenStore: any TokenStoring) {
        guard
            let address = environment["MM_DEBUG_SERVER"],
            let server = try? ServerEndpoint(validating: address)
        else { return }
        serverStore.saveServer(server)
        // Without a token, launch lands on Sign In for that server.
        if let token = environment["MM_DEBUG_TOKEN"] {
            try? tokenStore.saveToken(token, for: server)
        }
    }

    static func applyInitialScreen(to router: AppRouter) {
        switch environment["MM_DEBUG_SCREEN"] {
        case "accounts": router.show(.accounts)
        case "transactions": router.show(.transactions)
        case "planning": router.show(.planning)
        case "insights": router.show(.insights)
        case "review-page": router.openReviewPage(.unreviewed)
        case "review-stack": router.presentReviewStack()
        case "settings": router.presentSettings()
        default: break
        }
    }
}
#endif
