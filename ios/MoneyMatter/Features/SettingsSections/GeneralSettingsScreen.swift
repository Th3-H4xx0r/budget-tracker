import MoneyMatterKit
import SwiftUI

/// Settings > App > General: statistics, transfer matching, savings categories, account picker
/// defaults, the upcoming list, and optional transaction form fields. Mirrors the web General page.
struct GeneralSettingsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var model = SettingsPreferencesModel()

    var body: some View {
        Form {
            switch model.state {
            case .failed(let error):
                LoadFailedView(error: error) { await model.load(services: services) }
            case .loaded(let preferences):
                sections(preferences)
            case .idle, .loading:
                sections(SettingsUserPreferences())
                    .redactedWhileLoading(true)
            }
        }
        .navigationTitle("General")
        .task {
            await referenceData.loadIfNeeded()
            await model.loadIfNeeded(services: services)
        }
        .refreshable { await model.load(services: services) }
        .errorAlert($model.alert)
    }

    @ViewBuilder
    private func sections(_ preferences: SettingsUserPreferences) -> some View {
        Section {
            toggle(
                "Include Credit Limits in Statistics",
                isOn: preferences.includeCreditLimitInStats,
                patch: { SettingsPreferencesPatch(includeCreditLimitInStats: $0) },
                apply: { $0.includeCreditLimitInStats = $1 }
            )
        } footer: {
            Text("Counts the available credit on credit cards as part of your balance in statistics.")
        }

        Section {
            toggle(
                "Match Transfers with Manual Accounts",
                isOn: preferences.matchTransfersWithManualAccounts,
                patch: { SettingsPreferencesPatch(matchTransfersWithManualAccounts: $0) },
                apply: { $0.matchTransfersWithManualAccounts = $1 }
            )
        } footer: {
            Text("Lets bank sync link a synced transaction with a matching one you entered by hand as a transfer.")
        }

        Section {
            NavigationLink {
                GeneralSavingsCategoriesPicker(model: model)
            } label: {
                LabeledContent("Savings Categories") {
                    Text(preferences.savingsCategoryIds.isEmpty
                        ? String(localized: "None")
                        : String(localized: "\(preferences.savingsCategoryIds.count) selected"))
                }
            }
        } footer: {
            Text("Spending in these categories counts as savings in cash flow, not as an expense. Subcategories are included.")
        }

        Section {
            Picker("Default Account", selection: Binding(
                get: { preferences.defaultAccountId ?? "" },
                set: { value in
                    let id = value.isEmpty ? nil : value
                    Task {
                        await model.save(
                            SettingsPreferencesPatch(defaultAccountId: id.map { .set($0) } ?? .clear),
                            optimistic: { $0.defaultAccountId = id },
                            services: services
                        )
                    }
                }
            )) {
                Text("None").tag("")
                ForEach(pickableAccounts(preferences)) { account in
                    Text(account.name).tag(account.id)
                }
            }
            toggle(
                "Show Archived Accounts",
                isOn: preferences.showArchivedInDropdowns,
                patch: { SettingsPreferencesPatch(showArchivedInDropdowns: $0) },
                apply: { $0.showArchivedInDropdowns = $1 }
            )
        } header: {
            Text("Account Pickers")
        } footer: {
            Text("The default account is preselected when you add a transaction. Archived accounts can also be offered in account pickers.")
        }

        Section {
            toggle(
                "Show Upcoming Transactions",
                isOn: !preferences.hideUpcomingTransactions,
                patch: { SettingsPreferencesPatch(hideUpcomingTransactions: !$0) },
                apply: { $0.hideUpcomingTransactions = !$1 }
            )
        } footer: {
            Text("Pins overdue and soon-due planned transactions to the top of the transaction list.")
        }

        Section {
            ForEach(SettingsTransactionOptionalField.allCases, id: \.self) { field in
                Toggle(isOn: Binding(
                    get: { preferences.optionalTransactionFields.contains(field) },
                    set: { isOn in
                        var fields = preferences.optionalTransactionFields.filter { $0 != field }
                        if isOn { fields.append(field) }
                        let ordered = SettingsTransactionOptionalField.allCases.filter(fields.contains)
                        Task {
                            await model.save(
                                SettingsPreferencesPatch(optionalTransactionFields: ordered),
                                optimistic: { $0.optionalTransactionFields = ordered },
                                services: services
                            )
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(for: field))
                        Text(detail(for: field))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            toggle(
                "Map Picker",
                isOn: preferences.mapPicker,
                patch: { SettingsPreferencesPatch(mapPicker: $0) },
                apply: { $0.mapPicker = $1 }
            )
            .disabled(!preferences.optionalTransactionFields.contains(.location))
        } header: {
            Text("Transaction Form Fields")
        } footer: {
            Text("Extra fields to show when adding or editing a transaction. A field that already holds a value is always shown. The map picker loads map tiles and address search from OpenStreetMap.")
        }
    }

    private func pickableAccounts(_ preferences: SettingsUserPreferences) -> [Account] {
        referenceData.accounts.filter { account in
            account.status != .archived || preferences.showArchivedInDropdowns || account.id == preferences.defaultAccountId
        }
    }

    private func toggle(
        _ title: LocalizedStringKey,
        isOn: Bool,
        patch: @escaping (Bool) -> SettingsPreferencesPatch,
        apply: @escaping (inout SettingsUserPreferences, Bool) -> Void
    ) -> some View {
        Toggle(title, isOn: Binding(
            get: { isOn },
            set: { value in
                Task {
                    await model.save(patch(value), optimistic: { apply(&$0, value) }, services: services)
                }
            }
        ))
    }

    private func title(for field: SettingsTransactionOptionalField) -> LocalizedStringKey {
        switch field {
        case .externalUrl: "Link"
        case .externalReference: "Reference"
        case .location: "Location"
        case .originalAmount: "Original Amount"
        }
    }

    private func detail(for field: SettingsTransactionOptionalField) -> LocalizedStringKey {
        switch field {
        case .externalUrl: "A web link, such as an order or receipt page."
        case .externalReference: "An invoice, order, or reference number."
        case .location: "Where the transaction happened."
        case .originalAmount: "The amount in a foreign currency before conversion."
        }
    }
}

/// Multi-select of the categories whose spending counts as savings.
private struct GeneralSavingsCategoriesPicker: View {
    let model: SettingsPreferencesModel

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var searchText = ""

    private var selected: Set<String> { Set(model.preferences?.savingsCategoryIds ?? []) }

    private var categories: [MoneyMatterKit.Category] {
        let all = referenceData.categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        List {
            if referenceData.categories.isEmpty {
                ContentUnavailableView {
                    Label("No Categories", systemImage: "square.grid.2x2")
                } actions: {
                    Button("Refresh") { Task { await referenceData.refreshCategories() } }
                }
            }
            ForEach(categories) { category in
                Button {
                    toggle(category.id)
                } label: {
                    HStack {
                        Text(category.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selected.contains(category.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityAddTraits(selected.contains(category.id) ? .isSelected : [])
            }
        }
        .navigationTitle("Savings Categories")
        .searchable(text: $searchText)
    }

    private func toggle(_ id: String) {
        var ids = model.preferences?.savingsCategoryIds ?? []
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        Task {
            await model.save(
                SettingsPreferencesPatch(savingsCategoryIds: ids),
                optimistic: { $0.savingsCategoryIds = ids },
                services: services
            )
        }
    }
}
