import MoneyMatterKit
import SwiftUI

/// Minimal Settings, opened as a sheet from the Home avatar: profile, server, and sign out.
struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsSignOut = false
    @State private var confirmsChangeServer = false
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                profileSection

                Section {
                    LabeledContent("Address", value: session.server?.hostAndPort ?? "")
                    Button("Change Server") { confirmsChangeServer = true }
                        .disabled(isWorking)
                } header: {
                    Text("Server")
                } footer: {
                    Text("Changing the server signs you out.")
                }

                Section {
                    Button("Sign Out", role: .destructive) { confirmsSignOut = true }
                        .disabled(isWorking)
                }

                Section {
                    LabeledContent("Version", value: AppConfig.appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .confirmationDialog("Sign out of MoneyMatter?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    run { await session.signOut() }
                }
            }
            .confirmationDialog("Change Server?", isPresented: $confirmsChangeServer, titleVisibility: .visible) {
                Button("Sign Out and Change Server", role: .destructive) {
                    run { await session.changeServer() }
                }
            } message: {
                Text("You'll be signed out and can choose a different MoneyMatter server.")
            }
        }
    }

    private var profileSection: some View {
        Section("Profile") {
            HStack(spacing: 14) {
                InitialsBadge(session.user?.initials ?? "?", size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.user?.displayName ?? "")
                        .font(.headline)
                    if let email = session.user?.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)

            if let base = session.baseCurrency {
                LabeledContent("Base Currency", value: base.currency?.currency ?? base.currencyCode)
            }
        }
    }

    private func run(_ action: @escaping () async -> Void) {
        isWorking = true
        Task {
            await action()
            isWorking = false
        }
    }
}
