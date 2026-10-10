import MoneyMatterKit
import SwiftUI
import UserNotifications

@main
struct MoneyMatterApp: App {
    @State private var dependencies = AppDependencies.live()

    init() {
        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            if AppConfig.isRunningUnitTests {
                // The test host launches the app; skip session restore so tests stay offline.
                Color.clear
            } else {
                RootView()
                    .settingsAppearanceTheme()
                    .environment(dependencies)
                    .environment(dependencies.session)
                    .environment(dependencies.referenceData)
            }
        }
        .backgroundTask(.appRefresh(SharedContainer.budgetRefreshTaskIdentifier)) {
            await MonthlyBudgetAlerts.runBackgroundRefresh()
        }
    }
}
