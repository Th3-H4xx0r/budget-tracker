import MoneyMatterKit
import SwiftUI

/// The Settings hub, opened as a sheet from the Home avatar: profile, a section per settings
/// area (each row pushes that area's screen), server, sign out, and version.
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
                organizationSection
                sharingSection
                dataSection
                aiSection
                appSection
                securitySection
                planSection
                if session.user?.isAdmin == true {
                    adminSection
                }

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

    private var organizationSection: some View {
        Section("Organization") {
            NavigationLink { CategoriesSettingsScreen() } label: { Label("Categories", systemImage: "square.grid.2x2") }
            NavigationLink { TagsSettingsScreen() } label: { Label("Tags", systemImage: "tag") }
            NavigationLink { PayeesScreen() } label: { Label("Payees", systemImage: "person.2") }
            NavigationLink { CurrenciesSettingsScreen() } label: { Label("Currencies", systemImage: "dollarsign.circle") }
            NavigationLink { AccountGroupsScreen() } label: { Label("Account Groups", systemImage: "folder") }
        }
    }

    private var sharingSection: some View {
        Section("Sharing") {
            NavigationLink { SharedWithMeScreen() } label: { Label("Shared with Me", systemImage: "person.crop.circle.badge.checkmark") }
            NavigationLink { HouseholdScreen() } label: { Label("Household", systemImage: "house.and.flag") }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            NavigationLink { ImportScreen() } label: { Label("Import", systemImage: "square.and.arrow.down") }
            NavigationLink { ExportScreen() } label: { Label("Export", systemImage: "square.and.arrow.up") }
            NavigationLink { BackupRestoreScreen() } label: { Label("Backup & Restore", systemImage: "externaldrive") }
        }
    }

    private var aiSection: some View {
        Section("AI") {
            NavigationLink { AIFeaturesScreen() } label: { Label("Features", systemImage: "sparkles") }
            NavigationLink { AIKeysScreen() } label: { Label("API Keys", systemImage: "key") }
            NavigationLink { AIEndpointsScreen() } label: { Label("Endpoints", systemImage: "server.rack") }
            NavigationLink { AIIntegrationsScreen() } label: { Label("Integrations (MCP)", systemImage: "puzzlepiece.extension") }
        }
    }

    private var appSection: some View {
        Section("App") {
            NavigationLink { AppearanceSettingsScreen() } label: { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            NavigationLink { LanguageSettingsScreen() } label: { Label("Language", systemImage: "globe") }
            NavigationLink { GeneralSettingsScreen() } label: { Label("General", systemImage: "gearshape") }
        }
    }

    private var securitySection: some View {
        Section("Security") {
            NavigationLink { LoginMethodsScreen() } label: { Label("Login Methods & Passkeys", systemImage: "person.badge.key") }
            NavigationLink { SessionsScreen() } label: { Label("Sessions", systemImage: "iphone.and.arrow.forward") }
            NavigationLink { PasswordScreen() } label: { Label("Password", systemImage: "lock") }
            NavigationLink { DangerZoneScreen() } label: { Label("Danger Zone", systemImage: "exclamationmark.triangle") }
        }
    }

    private var planSection: some View {
        Section {
            NavigationLink { PlanBillingScreen() } label: { Label("Plan & Billing", systemImage: "creditcard") }
        }
    }

    private var adminSection: some View {
        Section {
            NavigationLink { AdminScreen() } label: { Label("Admin", systemImage: "shield.lefthalf.filled") }
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
