import Foundation
import MoneyMatterKit
import Observation

enum AppTab: Hashable, CaseIterable {
    case home
    case accounts
    case transactions
}

/// Pushes within the Home tab's stack.
enum HomeRoute: Hashable {
    case transaction(id: String)
    case account(id: String)
    case reviewPage(ReviewListStatus)
}

/// Pushes within the Accounts tab's stack.
enum AccountsRoute: Hashable {
    case account(id: String)
    case transaction(id: String)
}

/// Pushes within the Transactions tab's stack.
enum TransactionsRoute: Hashable {
    case transaction(id: String)
    case reviewPage(ReviewListStatus)
}

/// A request to open the review card stack.
struct ReviewStackRequest: Identifiable, Hashable {
    let id = UUID()
    /// The expected card count, e.g. the summary's `unreviewedCount`.
    var expectedTotal: Int?
}

/// Tab selection, each tab's navigation path, and app-level presentations. Created per
/// signed-in session and read with `@Environment(AppRouter.self)`.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var homePath: [HomeRoute] = []
    var accountsPath: [AccountsRoute] = []
    var transactionsPath: [TransactionsRoute] = []
    var isSettingsPresented = false
    var reviewStack: ReviewStackRequest?

    /// Switches tabs, optionally returning the destination tab to its root.
    func show(_ tab: AppTab, popToRoot: Bool = false) {
        if popToRoot {
            switch tab {
            case .home: homePath.removeAll()
            case .accounts: accountsPath.removeAll()
            case .transactions: transactionsPath.removeAll()
            }
        }
        selectedTab = tab
    }

    func presentSettings() {
        isSettingsPresented = true
    }

    func presentReviewStack(expectedTotal: Int? = nil) {
        reviewStack = ReviewStackRequest(expectedTotal: expectedTotal)
    }
}
