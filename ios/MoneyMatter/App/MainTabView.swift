import MoneyMatterKit
import SwiftUI

/// The signed-in shell: five tabs, the Settings sheet, and the review stack cover.
/// Each tab's root view lives in `Features/<Tab>/` and owns its `NavigationStack`.
struct MainTabView: View {
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeTab()
            }
            Tab("Accounts", systemImage: "wallet.bifold", value: AppTab.accounts) {
                AccountsTab()
            }
            Tab("Transactions", systemImage: "list.bullet.rectangle.portrait", value: AppTab.transactions) {
                TransactionsTab()
            }
            Tab("Planning", systemImage: "calendar.badge.clock", value: AppTab.planning) {
                PlanningTab()
            }
            Tab("Insights", systemImage: "chart.xyaxis.line", value: AppTab.insights) {
                InsightsTab()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $router.isSettingsPresented) {
            SettingsView()
        }
        .fullScreenCover(item: $router.reviewStack) { request in
            ReviewStackScreen(request: request)
        }
        .shareInvitationLinks()
        .task {
            #if DEBUG
            DebugLaunch.applyInitialScreen(to: router)
            #endif
            await referenceData.loadIfNeeded()
        }
        // Last, so the sheet and cover content can read the router too.
        .environment(router)
    }
}
