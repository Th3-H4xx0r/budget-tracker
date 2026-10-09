import MoneyMatterKit
import SwiftUI

/// Shown while the saved session is checked, with a retry when that fails.
struct LaunchView: View {
    @Environment(SessionStore.self) private var session
    @State private var isSigningOut = false

    var body: some View {
        Group {
            if let error = session.launchError {
                ContentUnavailableView {
                    Label("Can't Reach Your Server", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(ErrorMessage.message(for: error))
                } actions: {
                    Button("Try Again") {
                        Task { await session.retryLaunch() }
                    }
                    .buttonStyle(.glassProminent)

                    Button("Sign Out", role: .destructive) {
                        isSigningOut = true
                        Task {
                            await session.signOut()
                            isSigningOut = false
                        }
                    }
                    .disabled(isSigningOut)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel("Loading your account")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
