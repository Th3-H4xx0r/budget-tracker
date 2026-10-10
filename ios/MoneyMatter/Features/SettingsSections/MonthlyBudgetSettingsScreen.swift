import MoneyMatterKit
import SwiftUI

/// Settings > Budget > Monthly Budget: the monthly spending budget in the base currency and
/// whether crossing 80 % and 100 % of it sends a time-sensitive notification. Saving patches
/// `/user/settings`, then refreshes the widget and checks for a due alert.
struct MonthlyBudgetSettingsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(MonthlyBudgetModel.self) private var budget
    @State private var state: LoadState<MonthlyBudgetSettings> = .idle
    @State private var amountText = ""
    @State private var alertsEnabled = true
    @State private var isSaving = false
    @State private var confirmsClear = false
    @State private var alert: ErrorAlert?
    @FocusState private var isAmountFocused: Bool

    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }

    private var currencySymbol: String {
        Locale.autoupdatingCurrent.currencySymbol(for: currencyCode)
    }

    private var parsedAmount: Decimal? { Self.parseAmount(amountText) }

    /// An empty field clears the budget; anything else must be a positive amount.
    private var isAmountValid: Bool {
        amountText.trimmingCharacters(in: .whitespaces).isEmpty || (parsedAmount ?? 0) > 0
    }

    private var hasChanges: Bool {
        guard let saved = state.value else { return false }
        return parsedAmount != saved.effectiveAmount || alertsEnabled != saved.alertsEnabled
    }

    var body: some View {
        Form {
            switch state {
            case .failed(let error):
                LoadFailedView(error: error) { await load() }
            case .loaded(let settings):
                sections(saved: settings)
            case .idle, .loading:
                sections(saved: .notSet)
                    .redactedWhileLoading(true)
            }
        }
        .navigationTitle("Monthly Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await save(MonthlyBudgetSettings(amount: parsedAmount, alertsEnabled: alertsEnabled)) }
                    }
                    .disabled(!hasChanges || !isAmountValid)
                }
            }
        }
        .confirmationDialog("Clear your monthly budget?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Clear Budget", role: .destructive) {
                Task { await save(MonthlyBudgetSettings(amount: nil, alertsEnabled: alertsEnabled)) }
            }
        } message: {
            Text("Home and the widget stop tracking spending against a budget, and budget alerts stop.")
        }
        .task {
            if case .idle = state { await load() }
        }
        .errorAlert($alert)
    }

    @ViewBuilder
    private func sections(saved: MonthlyBudgetSettings) -> some View {
        Section {
            HStack(spacing: DS.Space.s) {
                Text(verbatim: currencySymbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Amount", text: $amountText, prompt: Text("No budget"))
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .focused($isAmountFocused)
                    .accessibilityLabel(Text("Monthly budget in \(currencyCode)"))
            }
            .padding(.vertical, DS.Space.xs)

            Toggle("Alerts", isOn: $alertsEnabled)
        } header: {
            Text("Spending per month, in \(currencyCode)")
        } footer: {
            Text("We'll notify you at 80% and when you go over.")
        }

        if let snapshot = budget.snapshot, snapshot.hasBudget, saved.effectiveAmount != nil {
            Section("This Month") {
                LabeledContent("Spent") {
                    Text(verbatim: MonthlyBudgetFormat.money(snapshot.spent, currencyCode: snapshot.currencyCode))
                        .monospacedDigit()
                }
                if snapshot.isOverBudget {
                    LabeledContent("Over by") {
                        Text(verbatim: MonthlyBudgetFormat.money(snapshot.overBy ?? 0, currencyCode: snapshot.currencyCode))
                            .monospacedDigit()
                            .foregroundStyle(DS.Palette.danger)
                    }
                } else {
                    LabeledContent("Left") {
                        Text(verbatim: MonthlyBudgetFormat.money(snapshot.remaining ?? 0, currencyCode: snapshot.currencyCode))
                            .monospacedDigit()
                    }
                }
            }
        }

        if saved.effectiveAmount != nil {
            Section {
                InlineActionRow(String(localized: "Clear budget"), systemImage: "trash", role: .destructive) {
                    confirmsClear = true
                }
                .disabled(isSaving)
            }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let client = try settingsSectionsClient(services)
            apply(try await client.send(Endpoints.monthlyBudgetSettings()))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(error) }
        }
    }

    private func save(_ settings: MonthlyBudgetSettings) async {
        let previous = state.value
        isAmountFocused = false
        isSaving = true
        defer { isSaving = false }
        do {
            let client = try settingsSectionsClient(services)
            let saved = try await client.send(Endpoints.patchMonthlyBudgetSettings(settings))
            apply(saved)
            // Before the check below, so a first budget can alert right away.
            if saved.alertsEnabled, saved.effectiveAmount != nil {
                await MonthlyBudgetAlerts.requestAuthorization()
            }
            await budget.settingsDidChange(to: saved, from: previous, client: client)
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func apply(_ settings: MonthlyBudgetSettings) {
        state = .loaded(settings)
        alertsEnabled = settings.alertsEnabled
        amountText = settings.effectiveAmount.map {
            $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        } ?? ""
    }

    /// Reads a typed amount in the current locale, ignoring currency symbols and grouping.
    static func parseAmount(_ text: String, locale: Locale = .autoupdatingCurrent) -> Decimal? {
        let separator = locale.decimalSeparator ?? "."
        let cleaned = String(text.filter { $0.isNumber || String($0) == separator })
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: locale)
    }
}

private extension Locale {
    /// "$" for USD in en-US; the code itself where the locale has no symbol for it.
    func currencySymbol(for code: String) -> String {
        var locale = Locale.Components(locale: self)
        locale.currency = Locale.Currency(code)
        return Locale(components: locale).currencySymbol ?? code
    }
}
