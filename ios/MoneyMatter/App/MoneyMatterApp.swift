import SwiftUI

@main
struct MoneyMatterApp: App {
    @State private var dependencies = AppDependencies.live()

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
    }
}
