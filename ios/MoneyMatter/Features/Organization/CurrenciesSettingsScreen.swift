import MoneyMatterKit
import SwiftUI

/// Settings › Currencies: the user's currencies with their exchange rates, adding and
/// removing currencies, custom or live rates, and changing the base currency.
/// Mirrors the web `settings/subpages/currencies` page and `api/currencies.ts`.
struct CurrenciesSettingsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData

    @State private var rates: LoadState<[OrgExchangeRate]> = .idle
    @State private var changeStatus: OrgBaseCurrencyChangeStatus?
    @State private var isAdding = false
    @State private var confirmingRemove: UserCurrency?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Currencies")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add Currency", systemImage: "plus")
                    }
                    .disabled(changeStatus?.state.isInFlight == true)
                }
            }
            .task {
                await referenceData.loadIfNeeded()
                await loadRates()
                await checkChangeStatus()
            }
            .refreshable {
                await referenceData.refreshCurrencies()
                await loadRates()
                await checkChangeStatus()
            }
            .sheet(isPresented: $isAdding) {
                OrgCurrencyAddSheet(existingCodes: Set(referenceData.userCurrencies.map(\.currencyCode))) {
                    await referenceData.refreshCurrencies()
                    await loadRates()
                }
            }
            .confirmationDialog(
                "Remove Currency?",
                isPresented: Binding(
                    get: { confirmingRemove != nil },
                    set: { if !$0 { confirmingRemove = nil } }
                ),
                titleVisibility: .visible,
                presenting: confirmingRemove
            ) { currency in
                Button("Remove \(currency.currencyCode)", role: .destructive) {
                    Task { await remove(currency) }
                }
            } message: { _ in
                Text("You can add it again later.")
            }
            .errorAlert($alert)
    }

    private var baseCurrency: UserCurrency? {
        referenceData.userCurrencies.first(where: \.isDefaultCurrency)
    }

    private var otherCurrencies: [UserCurrency] {
        referenceData.userCurrencies
            .filter { !$0.isDefaultCurrency }
            .sorted { $0.currencyCode < $1.currencyCode }
    }

    @ViewBuilder
    private var content: some View {
        let currencies = referenceData.userCurrencies
        if currencies.isEmpty, !referenceData.hasLoaded, let error = referenceData.lastError {
            LoadFailedView(error: error) { await referenceData.refreshCurrencies() }
        } else if currencies.isEmpty, referenceData.isLoading || !referenceData.hasLoaded {
            List {
                ForEach(0..<4, id: \.self) { _ in
                    Text(verbatim: "USD · US Dollar · 1.0000")
                }
            }
            .redactedWhileLoading(true)
        } else {
            List {
                if let changeStatus, changeStatus.state.isInFlight {
                    Section {
                        OrgBaseCurrencyProgressRow(status: changeStatus)
                    }
                }
                if let error = rates.error {
                    InlineRetryView(ErrorMessage.message(for: error)) { await loadRates() }
                }
                if let baseCurrency {
                    Section {
                        OrgCurrencyRow(currency: baseCurrency, rate: nil, baseCode: nil, usage: usage(of: baseCurrency))
                    } header: {
                        Text("Base Currency")
                    } footer: {
                        Text("Totals and reports are shown in your base currency.")
                    }
                }
                Section("Other Currencies") {
                    if otherCurrencies.isEmpty {
                        ContentUnavailableView {
                            Label("No Other Currencies", systemImage: "dollarsign.arrow.circlepath")
                        } description: {
                            Text("Add a currency to hold accounts in it.")
                        } actions: {
                            Button("Add Currency") { isAdding = true }
                        }
                    }
                    ForEach(otherCurrencies) { currency in
                        NavigationLink {
                            OrgCurrencyDetailScreen(currencyCode: currency.currencyCode)
                        } label: {
                            OrgCurrencyRow(
                                currency: currency,
                                rate: rate(for: currency),
                                baseCode: baseCurrency?.currencyCode,
                                usage: usage(of: currency)
                            )
                        }
                        .swipeActions {
                            if usage(of: currency) == 0 {
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    confirmingRemove = currency
                                }
                            }
                        }
                    }
                }
            }
            .redactedWhileLoading(rates.isLoading && rates.value == nil)
            .disabled(changeStatus?.state.isInFlight == true)
        }
    }

    private func rate(for currency: UserCurrency) -> OrgExchangeRate? {
        rates.value?.first { $0.baseCode == currency.currencyCode && $0.quoteCode == baseCurrency?.currencyCode }
            ?? rates.value?.first { $0.baseCode == currency.currencyCode }
    }

    private func usage(of currency: UserCurrency) -> Int {
        referenceData.accounts.filter { $0.currencyCode == currency.currencyCode }.count
    }

    private func loadRates() async {
        if rates.value == nil { rates = .loading }
        do {
            rates = .loaded(try await services.orgCoreSend(Endpoints.orgUserExchangeRates()))
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation { rates = .failed(apiError) }
        }
    }

    private func checkChangeStatus() async {
        guard let status = try? await services.orgCoreSend(Endpoints.orgBaseCurrencyChangeStatus()) else { return }
        changeStatus = status
        guard status.state.isInFlight else { return }
        let final = await OrgBaseCurrencyPolling.waitForCompletion(services: services) { changeStatus = $0 }
        changeStatus = final
        if final?.state == .failed {
            alert = ErrorAlert(
                title: String(localized: "Base Currency Not Changed"),
                message: final?.error ?? String(localized: "The change failed. Try again.")
            )
        }
        await referenceData.refresh()
        await loadRates()
    }

    private func remove(_ currency: UserCurrency) async {
        do {
            _ = try await services.orgCoreSend(Endpoints.orgDeleteUserCurrency(code: currency.currencyCode))
            await referenceData.refreshCurrencies()
            await loadRates()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Rows

private struct OrgCurrencyRow: View {
    let currency: UserCurrency
    let rate: OrgExchangeRate?
    let baseCode: String?
    let usage: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(MoneyFormat.symbol(for: currency.currencyCode))
                .font(.headline)
                .frame(width: 40, height: 40)
                .background(Color(.secondarySystemFill), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(currency.currencyCode).font(.headline)
                Text(currency.currency?.currency ?? currency.currencyCode)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if usage > 0 {
                    Text("Used by \(usage) accounts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let rate, let baseCode {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "\(OrgRateFormat.string(rate.rate)) \(baseCode)")
                        .monospacedDigit()
                    Text(rate.custom ? "Custom" : "Live")
                        .font(.caption)
                        .foregroundStyle(rate.custom ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            }
        }
    }
}

private struct OrgBaseCurrencyProgressRow: View {
    let status: OrgBaseCurrencyChangeStatus

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("Changing Base Currency")
                    .font(.headline)
                Text("Recalculating balances and history. This can take a few minutes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let step = status.step {
                    Text(verbatim: step)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum OrgRateFormat {
    static func string(_ rate: Decimal) -> String {
        rate.formatted(.number.precision(.fractionLength(0...4)))
    }

    /// `1 / rate`, rounded for display and for the inverse direction of a custom pair.
    static func inverse(of rate: Decimal) -> Decimal? {
        guard rate > 0 else { return nil }
        return MoneyFormat.rounded(1 / rate, digits: 6)
    }
}

/// Polls `GET /user/currencies/change-base/status` until the job leaves queued/running.
enum OrgBaseCurrencyPolling {
    @MainActor
    static func waitForCompletion(
        services: AppServices,
        onUpdate: (OrgBaseCurrencyChangeStatus) -> Void
    ) async -> OrgBaseCurrencyChangeStatus? {
        var failures = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.5))
            do {
                let status = try await services.orgCoreSend(Endpoints.orgBaseCurrencyChangeStatus())
                onUpdate(status)
                failures = 0
                if !status.state.isInFlight { return status }
            } catch {
                failures += 1
                if failures >= 5 { return nil }
            }
        }
        return nil
    }
}

// MARK: - Detail

private struct OrgCurrencyDetailScreen: View {
    let currencyCode: String

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var rates: LoadState<[OrgExchangeRate]> = .idle
    @State private var isLive = true
    @State private var forwardRate: Decimal?
    @State private var inverseRate: Decimal?
    @State private var isSaving = false
    @State private var confirmingBase = false
    @State private var confirmingRemove = false
    @State private var changeStatus: OrgBaseCurrencyChangeStatus?
    @State private var alert: ErrorAlert?

    private var currency: UserCurrency? { referenceData.userCurrency(code: currencyCode) }
    private var baseCode: String? { referenceData.userCurrencies.first(where: \.isDefaultCurrency)?.currencyCode }
    private var usage: Int { referenceData.accounts.filter { $0.currencyCode == currencyCode }.count }

    private var currentRate: OrgExchangeRate? {
        rates.value?.first { $0.baseCode == currencyCode && $0.quoteCode == baseCode }
    }

    var body: some View {
        Form {
            if let changeStatus, changeStatus.state.isInFlight {
                Section { OrgBaseCurrencyProgressRow(status: changeStatus) }
            }
            Section {
                switch rates {
                case .failed(let error):
                    InlineRetryView(ErrorMessage.message(for: error)) { await loadRates() }
                default:
                    Toggle("Live Rate Updates", isOn: Binding(get: { isLive }, set: { setLive($0) }))
                    if let baseCode {
                        LabeledContent {
                            TextField("Rate", value: $forwardRate, format: .number.precision(.fractionLength(0...6)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .onChange(of: forwardRate) { _, value in
                                    guard let value, let inverse = OrgRateFormat.inverse(of: value) else { return }
                                    if inverseRate != inverse, !isLive { inverseRate = inverse }
                                }
                        } label: {
                            Text(verbatim: "1 \(currencyCode) = … \(baseCode)")
                        }
                        .disabled(isLive)
                        LabeledContent {
                            TextField("Rate", value: $inverseRate, format: .number.precision(.fractionLength(0...6)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        } label: {
                            Text(verbatim: "1 \(baseCode) = … \(currencyCode)")
                        }
                        .disabled(true)
                    }
                }
            } header: {
                Text("Exchange Rate")
            } footer: {
                Text("Live rates update daily. Turn them off to set your own rate; balances in this currency are recalculated with it.")
            }
            if !isLive, rates.value != nil {
                Section {
                    Button {
                        Task { await saveCustomRate() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save Rate") }
                    }
                    .disabled(isSaving || (forwardRate ?? 0) <= 0)
                }
            }
            Section {
                Button("Set as Base Currency", systemImage: "star") { confirmingBase = true }
            } footer: {
                Text("All amounts are recalculated in the new base currency. This runs in the background and can take a few minutes.")
            }
            Section {
                Button("Remove Currency", systemImage: "trash", role: .destructive) { confirmingRemove = true }
                    .disabled(usage > 0)
            } footer: {
                if usage > 0 {
                    Text("\(usage) accounts use \(currencyCode). Move or delete them before removing it.")
                }
            }
        }
        .disabled(changeStatus?.state.isInFlight == true)
        .navigationTitle(currency?.currency?.currency ?? currencyCode)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRates() }
        .confirmationDialog("Change Base Currency?", isPresented: $confirmingBase, titleVisibility: .visible) {
            Button("Change to \(currencyCode)", role: .destructive) { Task { await changeBase() } }
        } message: {
            Text("Every balance, budget, and report is recalculated in \(currencyCode). You can't edit data until it finishes.")
        }
        .confirmationDialog("Remove \(currencyCode)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await remove() } }
        }
        .errorAlert($alert)
    }

    private func loadRates() async {
        if rates.value == nil { rates = .loading }
        do {
            let loaded = try await services.orgCoreSend(Endpoints.orgUserExchangeRates())
            rates = .loaded(loaded)
            syncForm()
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation { rates = .failed(apiError) }
        }
    }

    private func syncForm() {
        isLive = !(currentRate?.custom ?? false)
        forwardRate = currentRate.map { MoneyFormat.rounded($0.rate, digits: 6) }
        inverseRate = currentRate.flatMap { OrgRateFormat.inverse(of: $0.rate) }
    }

    private func setLive(_ live: Bool) {
        if live {
            isLive = true
            guard currentRate?.custom == true else { return }
            Task { await restoreLiveRate() }
        } else {
            isLive = false
        }
    }

    private func restoreLiveRate() async {
        guard let baseCode else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await services.orgCoreSend(Endpoints.orgDeleteCustomRates([
                OrgExchangeRateKey(baseCode: currencyCode, quoteCode: baseCode),
                OrgExchangeRateKey(baseCode: baseCode, quoteCode: currencyCode),
            ]))
            await loadRates()
            await referenceData.refreshAccounts()
        } catch {
            alert = ErrorAlert(error)
            syncForm()
        }
    }

    private func saveCustomRate() async {
        guard let baseCode, let forwardRate, forwardRate > 0, let inverse = OrgRateFormat.inverse(of: forwardRate) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await services.orgCoreSend(Endpoints.orgEditExchangeRates([
                OrgExchangeRatePair(baseCode: currencyCode, quoteCode: baseCode, rate: forwardRate),
                OrgExchangeRatePair(baseCode: baseCode, quoteCode: currencyCode, rate: inverse),
            ]))
            await loadRates()
            await referenceData.refreshAccounts()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func changeBase() async {
        do {
            let started = try await services.orgCoreSend(Endpoints.orgChangeBaseCurrency(code: currencyCode))
            changeStatus = OrgBaseCurrencyChangeStatus(state: started.state == .unknown ? .queued : started.state, jobId: started.jobId)
            let final = await OrgBaseCurrencyPolling.waitForCompletion(services: services) { changeStatus = $0 }
            changeStatus = final
            await referenceData.refresh()
            if final?.state == .failed {
                alert = ErrorAlert(
                    title: String(localized: "Base Currency Not Changed"),
                    message: final?.error ?? String(localized: "The change failed. Try again.")
                )
            } else {
                dismiss()
            }
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func remove() async {
        do {
            _ = try await services.orgCoreSend(Endpoints.orgDeleteUserCurrency(code: currencyCode))
            await referenceData.refreshCurrencies()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Add

private struct OrgCurrencyAddSheet: View {
    let existingCodes: Set<String>
    let onAdded: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var all: LoadState<[Currency]> = .idle
    @State private var selection: String?
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    var body: some View {
        NavigationStack {
            Group {
                switch all {
                case .idle, .loading:
                    List {
                        ForEach(0..<10, id: \.self) { _ in Text(verbatim: "EUR · Euro") }
                    }
                    .redactedWhileLoading(true)
                case .failed(let error):
                    LoadFailedView(error: error) { await load() }
                case .loaded(let currencies):
                    CurrencyList(
                        currencies: currencies.filter { !existingCodes.contains($0.code) && !$0.isDisabled },
                        pinnedCodes: ["USD", "EUR", "GBP"].filter { !existingCodes.contains($0) },
                        selection: $selection
                    )
                }
            }
            .disabled(isSaving)
            .navigationTitle("Add Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if isSaving {
                    ToolbarItem(placement: .confirmationAction) { ProgressView() }
                }
            }
            .task { await load() }
            .onChange(of: selection) { _, code in
                guard let code else { return }
                Task { await add(code) }
            }
            .errorAlert($alert)
        }
    }

    private func load() async {
        all = .loading
        do {
            all = .loaded(try await services.orgCoreSend(Endpoints.currencies()))
        } catch {
            all = .failed(APIError(error))
        }
    }

    private func add(_ code: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await services.orgCoreSend(Endpoints.addUserCurrencies(codes: [code]))
            await onAdded()
            dismiss()
        } catch {
            selection = nil
            alert = ErrorAlert(error)
        }
    }
}
