import MoneyMatterKit
import SwiftUI

/// The Settings hub, opened as a sheet from the Home avatar, laid out like iOS Settings: a
/// profile header, a section per settings area whose rows carry a solid-colour
/// `SettingsIconTile` and push that area's screen, then server, sign out, and version.
struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsSignOut = false
    @State private var confirmsChangeServer = false
    @State private var isWorking = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.settingsPath) {
            List {
                profileSection
                budgetSection
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
                    LabeledContent("Version") {
                        Text(verbatim: AppConfig.appVersion)
                            .monospacedDigit()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .monthlyBudget:
                    MonthlyBudgetSettingsScreen()
                }
            }
            .navigationBarTitleDisplayMode(.large)
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
        Section {
            HStack(spacing: DS.Space.m) {
                IconTile(text: String((session.user?.initials ?? "?").prefix(2)).uppercased(), color: DS.Palette.accent, size: 56)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(session.user?.displayName ?? "")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if let email = session.user?.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, DS.Space.xs)
            .accessibilityElement(children: .combine)

            if let base = session.baseCurrency {
                LabeledContent("Base Currency", value: base.currency?.currency ?? base.currencyCode)
            }
        }
    }

    private var budgetSection: some View {
        Section("Budget") {
            NavigationLink(value: SettingsRoute.monthlyBudget) {
                SettingsHubRow("Monthly Budget", systemImage: "gauge.with.dots.needle.67percent", color: .orange)
            }
        }
    }

    private var organizationSection: some View {
        Section("Organization") {
            NavigationLink { CategoriesSettingsScreen() } label: { SettingsHubRow("Categories", systemImage: "square.grid.2x2", color: .orange) }
            NavigationLink { TagsSettingsScreen() } label: { SettingsHubRow("Tags", systemImage: "tag", color: .pink) }
            NavigationLink { PayeesScreen() } label: { SettingsHubRow("Payees", systemImage: "person.2", color: .teal) }
            NavigationLink { CurrenciesSettingsScreen() } label: { SettingsHubRow("Currencies", systemImage: "dollarsign.circle", color: .green) }
            NavigationLink { AccountGroupsScreen() } label: { SettingsHubRow("Account Groups", systemImage: "folder", color: .indigo) }
        }
    }

    private var sharingSection: some View {
        Section("Sharing") {
            NavigationLink { SharedWithMeScreen() } label: { SettingsHubRow("Shared with Me", systemImage: "person.crop.circle.badge.checkmark", color: .blue) }
            NavigationLink { HouseholdScreen() } label: { SettingsHubRow("Household", systemImage: "house", color: .purple) }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            NavigationLink { ImportScreen() } label: { SettingsHubRow("Import", systemImage: "square.and.arrow.down", color: .gray) }
            NavigationLink { ExportScreen() } label: { SettingsHubRow("Export", systemImage: "square.and.arrow.up", color: .gray) }
            NavigationLink { BackupRestoreScreen() } label: { SettingsHubRow("Backup & Restore", systemImage: "externaldrive", color: .cyan) }
        }
    }

    private var aiSection: some View {
        Section("AI") {
            NavigationLink { AIFeaturesScreen() } label: { SettingsHubRow("Features", systemImage: "sparkles", color: DS.Palette.accent) }
            NavigationLink { AIKeysScreen() } label: { SettingsHubRow("API Keys", systemImage: "key", color: DS.Palette.accent) }
            NavigationLink { AIEndpointsScreen() } label: { SettingsHubRow("Endpoints", systemImage: "server.rack", color: DS.Palette.accent) }
            NavigationLink { AIIntegrationsScreen() } label: { SettingsHubRow("Integrations (MCP)", systemImage: "puzzlepiece.extension", color: .mint) }
        }
    }

    private var appSection: some View {
        Section("App") {
            NavigationLink { AppearanceSettingsScreen() } label: { SettingsHubRow("Appearance", systemImage: "circle.lefthalf.filled", color: .blue) }
            NavigationLink { LanguageSettingsScreen() } label: { SettingsHubRow("Language", systemImage: "globe", color: .red) }
            NavigationLink { GeneralSettingsScreen() } label: { SettingsHubRow("General", systemImage: "gearshape", color: .gray) }
        }
    }

    private var securitySection: some View {
        Section("Security") {
            NavigationLink { LoginMethodsScreen() } label: { SettingsHubRow("Login Methods & Passkeys", systemImage: "person.badge.key", color: .green) }
            NavigationLink { SessionsScreen() } label: { SettingsHubRow("Sessions", systemImage: "iphone", color: .gray) }
            NavigationLink { PasswordScreen() } label: { SettingsHubRow("Password", systemImage: "lock", color: .yellow) }
            NavigationLink { DangerZoneScreen() } label: { SettingsHubRow("Danger Zone", systemImage: "exclamationmark.triangle", color: .red) }
        }
    }

    private var planSection: some View {
        Section {
            NavigationLink { PlanBillingScreen() } label: { SettingsHubRow("Plan & Billing", systemImage: "creditcard", color: .green) }
        }
    }

    private var adminSection: some View {
        Section {
            NavigationLink { AdminScreen() } label: { SettingsHubRow("Admin", systemImage: "shield.lefthalf.filled", color: .brown) }
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

/// One Settings-hub destination: a solid `SettingsIconTile` and the area's name, as the label
/// of a `NavigationLink`.
private struct SettingsHubRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color

    init(_ title: LocalizedStringKey, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            SettingsIconTile(systemImage: systemImage, color: color)
        }
    }
}
