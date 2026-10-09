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
        case .failed(let error):
            LoadFailedView(error: error) {
                guard let service = dependencies.services?.identity else { return }
                await model.reload(using: service)
            }
        case .loaded(let currencies):
            CurrencyList(
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
            .disabled(model.selection == nil)
        }
    }
}
