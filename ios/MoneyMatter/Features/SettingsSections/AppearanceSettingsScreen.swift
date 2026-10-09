import MoneyMatterKit
import SwiftUI

/// Settings > App > Appearance: theme (stored on this device), how currencies are shown, hiding
/// zero-balance accounts, and which asset sections the account sidebar shows.
struct AppearanceSettingsScreen: View {
    @Environment(AppServices.self) private var services
    @AppStorage(SettingsAppearanceTheme.storageKey) private var theme = SettingsAppearanceTheme.system.rawValue
    @State private var model = SettingsPreferencesModel()

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(SettingsAppearanceTheme.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Theme")
            } footer: {
                Text("System follows your device's Light or Dark appearance.")
            }

            switch model.state {
            case .failed(let error):
                Section {
                    InlineRetryView(ErrorMessage.message(for: error)) { await model.load(services: services) }
                }
            case .loaded(let preferences):
                syncedSections(preferences)
            case .idle, .loading:
                syncedSections(SettingsUserPreferences())
                    .redactedWhileLoading(true)
            }
        }
        .navigationTitle("Appearance")
        .task { await model.loadIfNeeded(services: services) }
        .refreshable { await model.load(services: services) }
        .errorAlert($model.alert)
    }

    @ViewBuilder
    private func syncedSections(_ preferences: SettingsUserPreferences) -> some View {
        Section {
            Picker("Currency Symbols", selection: Binding(
                get: { preferences.currencyDisplay },
                set: { value in
                    Task {
                        await model.save(
                            SettingsPreferencesPatch(currencyDisplay: value),
                            optimistic: { $0.currencyDisplay = value },
                            services: services
                        )
                    }
                }
            )) {
                Text("Distinct (CA$, A$)").tag(SettingsCurrencyDisplay.symbol)
                Text("Local ($)").tag(SettingsCurrencyDisplay.narrowSymbol)
            }
        } header: {
            Text("Currency")
        } footer: {
            Text("Distinct symbols tell dollar currencies apart. Local symbols are shorter but show every dollar as $.")
        }

        Section {
            Toggle("Hide Zero Balances", isOn: Binding(
                get: { preferences.hideZeroBalances },
                set: { value in
                    Task {
                        await model.save(
                            SettingsPreferencesPatch(hideZeroBalances: value),
                            optimistic: { $0.hideZeroBalances = value },
                            services: services
                        )
                    }
                }
            ))
        } header: {
            Text("Accounts")
        } footer: {
            Text("Hides accounts with a zero balance, and groups left empty by that, from the account sidebar.")
        }

        Section {
            sectionToggle("Investments", systemImage: "chart.line.uptrend.xyaxis", keyPath: \.portfolios, preferences: preferences)
            sectionToggle("Ventures", systemImage: "briefcase", keyPath: \.ventures, preferences: preferences)
            sectionToggle("Vehicles", systemImage: "car", keyPath: \.vehicles, preferences: preferences)
            sectionToggle("Loans", systemImage: "banknote", keyPath: \.loans, preferences: preferences)
        } header: {
            Text("Sidebar Sections")
        } footer: {
            Text("Choose which asset sections appear in the account sidebar. Bank accounts are always shown.")
        }
    }

    private func sectionToggle(
        _ title: LocalizedStringKey,
        systemImage: String,
        keyPath: WritableKeyPath<SettingsSidebarSections, Bool>,
        preferences: SettingsUserPreferences
    ) -> some View {
        Toggle(isOn: Binding(
            get: { preferences.sidebarSections[keyPath: keyPath] },
            set: { value in
                var sections = preferences.sidebarSections
                sections[keyPath: keyPath] = value
                Task {
                    await model.save(
                        SettingsPreferencesPatch(sidebarSections: sections),
                        optimistic: { $0.sidebarSections = sections },
                        services: services
                    )
                }
            }
        )) {
            Label(title, systemImage: systemImage)
        }
    }
}
