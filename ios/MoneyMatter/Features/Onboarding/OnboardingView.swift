import MoneyMatterKit
import SwiftUI

/// Base-currency selection for a user who doesn't have one yet.
struct OnboardingView: View {
    let user: User

    @Environment(SessionStore.self) private var session
    @Environment(AppDependencies.self) private var dependencies
    @State private var model = OnboardingViewModel()
    @State private var confirmsSignOut = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Base Currency")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Sign Out") { confirmsSignOut = true }
                            .disabled(model.isSaving)
                    }
                    if model.currencies.value != nil {
                        ToolbarItem(placement: .confirmationAction) {
                            continueButton
                        }
                    }
                }
        }
        .task {
            guard let service = dependencies.services?.identity else { return }
            await model.load(using: service)
        }
        .errorAlert($model.alert)
        .confirmationDialog("Sign out of MoneyMatter?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await session.signOut() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.currencies {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Surface.canvas.ignoresSafeArea())
        case .failed(let error):
            LoadFailedView(error: error) {
                guard let service = dependencies.services?.identity else { return }
                await model.reload(using: service)
            }
        case .loaded(let currencies):
            OnboardingCurrencyList(
                currencies: currencies,
                pinnedCodes: model.suggestedCodes,
                prompt: "Welcome, \(user.displayName). Choose the currency MoneyMatter uses for totals, charts, and reports. You can still add accounts in other currencies.",
                selection: $model.selection
            )
        }
    }

    @ViewBuilder
    private var continueButton: some View {
        if model.isSaving {
            ProgressView()
        } else {
            Button("Continue") {
                Task { await model.save(session: session) }
            }
            .dsProminentButton()
            .disabled(model.selection == nil)
        }
    }
}

/// The base-currency choices as an inset-grouped, searchable list: suggested currencies
/// pinned on top, then every currency, each an `EntityRow` led by its code in a tile.
private struct OnboardingCurrencyList: View {
    let currencies: [Currency]
    /// Codes shown in a "Suggested" section, in order.
    var pinnedCodes: [String] = []
    var prompt: LocalizedStringKey?
    @Binding var selection: String?

    @State private var query = ""

    var body: some View {
        List {
            if let prompt, query.isEmpty {
                Section {
                } footer: {
                    Text(prompt)
                }
            }
            if query.isEmpty, !pinned.isEmpty {
                Section("Suggested") {
                    ForEach(pinned) { row(for: $0) }
                }
            }
            Section(query.isEmpty ? "All Currencies" : "Results") {
                ForEach(filtered) { row(for: $0) }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Search by name or code")
        .overlay {
            if !query.isEmpty, filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private var pinned: [Currency] {
        let byCode = Dictionary(currencies.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        return pinnedCodes.compactMap { byCode[$0] }
    }

    private var filtered: [Currency] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let sorted = currencies.sorted { $0.code < $1.code }
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter {
            $0.code.localizedCaseInsensitiveContains(trimmed) || $0.currency.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func row(for currency: Currency) -> some View {
        let isSelected = selection == currency.code
        return Button {
            selection = currency.code
        } label: {
            EntityRow(currency.currency, subtitle: currency.code) {
                IconTile(text: currency.code, color: DS.Palette.accent)
            } trailing: {
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
