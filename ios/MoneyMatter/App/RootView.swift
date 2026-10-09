import MoneyMatterKit
import SwiftUI

/// Routes between the server, sign-in, onboarding, and signed-in experiences.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        content
            .animation(.smooth, value: session.state)
            .task {
                await session.restore()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .launching:
            LaunchView()
        case .needsServer:
            ServerView()
        case .signedOut:
            AuthFlowView()
        case .needsOnboarding(let user):
            OnboardingView(user: user)
        case .signedIn(let user, _):
            if let services = dependencies.services {
                MainTabView()
                    .environment(services)
                    // A new user or server gets fresh tab state.
                    .id("\(dependencies.connection.endpoint?.originString ?? "")#\(user.id)")
            } else {
                LaunchView()
            }
        }
    }
}
