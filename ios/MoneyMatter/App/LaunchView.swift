import MoneyMatterKit
import SwiftUI

/// Shown while the saved session is checked, with a retry when that fails.
struct LaunchView: View {
    @Environment(SessionStore.self) private var session
    @State private var isSigningOut = false
    @State private var showsCloudflareAccess = false

    var body: some View {
        Group {
            if let error = session.launchError {
                switch error {
                case .cloudflareBlocked:
                    ContentUnavailableView {
                        Label("Cloudflare Blocked the Connection", systemImage: "lock.shield")
                    } description: {
                        Text(ErrorMessage.message(for: error))
                    } actions: {
                        Button("Update Cloudflare Token") {
                            showsCloudflareAccess = true
                        }
                        .buttonStyle(.glassProminent)

                        Button("Try Again") {
                            Task { await session.retryLaunch() }
                        }

                        signOutButton
                    }
                default:
                    ContentUnavailableView {
                        Label("Can't Reach Your Server", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(ErrorMessage.message(for: error))
                    } actions: {
                        Button("Try Again") {
                            Task { await session.retryLaunch() }
                        }
                        .buttonStyle(.glassProminent)

                        signOutButton
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel("Loading your account")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showsCloudflareAccess) {
            CloudflareAccessSheet()
        }
    }

    private var signOutButton: some View {
        Button("Sign Out", role: .destructive) {
            isSigningOut = true
            Task {
                await session.signOut()
                isSigningOut = false
            }
        }
        .disabled(isSigningOut)
    }
}
