import Foundation
import MoneyMatterKit
import Observation
import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home
    case accounts
    case transactions
    case planning
    case insights
}

/// Pushes within the Home tab's stack.
enum HomeRoute: Hashable {
    case transaction(id: String)
    case account(id: String)
    case reviewPage(ReviewListStatus)
    case notifications
}

/// Pushes within the Accounts tab's stack.
enum AccountsRoute: Hashable {
    case account(id: String)
    case transaction(id: String)
    case loans
    case investments
    case venture
    case vehicles
    case bankConnections
}

/// Pushes within the Transactions tab's stack.
enum TransactionsRoute: Hashable {
    case transaction(id: String)
    case reviewPage(ReviewListStatus)
    case groups
    case automations
    case optimizations
}

/// Pushes within the Settings sheet's stack.
enum SettingsRoute: Hashable {
    case monthlyBudget
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
    /// Type-erased so the Planning area can push its own route types.
    var planningPath = NavigationPath()
    /// Type-erased so the Insights area can push its own route types.
    var insightsPath = NavigationPath()
    var isSettingsPresented = false
    var settingsPath: [SettingsRoute] = []
    var reviewStack: ReviewStackRequest?

    /// Switches tabs, optionally returning the destination tab to its root.
    func show(_ tab: AppTab, popToRoot: Bool = false) {
        if popToRoot {
            switch tab {
            case .home: homePath.removeAll()
            case .accounts: accountsPath.removeAll()
            case .transactions: transactionsPath.removeAll()
            case .planning: planningPath = NavigationPath()
            case .insights: insightsPath = NavigationPath()
            }
        }
        selectedTab = tab
    }

    func presentSettings() {
        settingsPath.removeAll()
        isSettingsPresented = true
    }

    /// Presents Settings with the monthly budget screen pushed.
    func presentMonthlyBudgetSettings() {
        settingsPath = [.monthlyBudget]
        isSettingsPresented = true
    }

    func open(_ link: AppDeepLink) {
        switch link {
        case .home:
            reviewStack = nil
            isSettingsPresented = false
            show(.home, popToRoot: true)
        case .monthlyBudgetSettings:
            reviewStack = nil
            presentMonthlyBudgetSettings()
        }
    }

    func presentReviewStack(expectedTotal: Int? = nil) {
        reviewStack = ReviewStackRequest(expectedTotal: expectedTotal)
    }
}
