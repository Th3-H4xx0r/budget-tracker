import MoneyMatterKit
import SwiftUI

/// One form for every portfolio cash action: deposit, withdraw, transfer to or from an
/// account, and currency exchange.
struct PortfolioCashActionSheet: View {
    let action: PortfolioCashAction
    let portfolioID: String
    let balances: [PortfolioCashBalance]
    let onSaved: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var currencyCode: String?
    @State private var toCurrencyCode: String?
    @State private var accountID: String?
    @State private var targetPortfolioID: String?
    @State private var otherPortfolios: [Portfolio] = []
    @State private var amountText = ""
    @State private var toAmountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var isAdjustment = false
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var errorAlert: ErrorAlert?

    private var accounts: [Account] {
        referenceData.activeAccounts.filter { $0.accountCategory != .vehicle }
    }

    private var selectedAccount: Account? {
        accounts.first { $0.id == accountID }
    }

    private var allCurrencyCodes: [String] {
        let codes = referenceData.userCurrencies.map(\.currencyCode) + balances.map(\.currencyCode)
        return Array(Set(codes)).sorted()
    }

    private var balanceCurrencyCodes: [String] {
        let codes = balances.filter { $0.totalCash > 0 }.map(\.currencyCode)
        return codes.isEmpty ? allCurrencyCodes : codes
    }

    var body: some View {
        NavigationStack {
            Form {
                switch action {
                case .deposit, .withdraw:
                    Section {
                        currencyPicker("Currency", selection: $currencyCode, codes: action == .withdraw ? balanceCurrencyCodes : allCurrencyCodes)
                        amountField("Amount", text: $amountText)
                        availableHint
                    }
                    Section {
                        Toggle("Balance Adjustment", isOn: $isAdjustment)
                    } footer: {
                        Text("Adjustments correct the balance and don't count as contributions.")
                    }
                case .fromAccount:
                    Section {
                        accountPicker
                        amountField("Amount", text: $amountText)
                        if let selectedAccount {
                            LabeledContent("Account Balance") {
                                AmountText(selectedAccount.currentBalance, currencyCode: selectedAccount.currencyCode)
                            }
                        }
                    } footer: {
                        Text("The amount is in the account's currency and arrives as portfolio cash.")
                    }
                case .toAccount:
                    Section {
                        accountPicker
                        currencyPicker("Pay From", selection: $currencyCode, codes: balanceCurrencyCodes)
                        amountField("Amount", text: $amountText)
                        availableHint
                    }
                case .toPortfolio:
                    Section {
                        Picker("Portfolio", selection: $targetPortfolioID) {
                            Text("Choose").tag(String?.none)
                            ForEach(otherPortfolios) { portfolio in
                                Text(verbatim: portfolio.name).tag(String?.some(portfolio.id))
                            }
                        }
                        currencyPicker("Currency", selection: $currencyCode, codes: balanceCurrencyCodes)
                        amountField("Amount", text: $amountText)
                        availableHint
                    }
                case .exchange:
                    Section {
                        currencyPicker("From", selection: $currencyCode, codes: balanceCurrencyCodes)
                        amountField("Amount Sold", text: $amountText)
                        availableHint
                    }
                    Section {
                        currencyPicker("To", selection: $toCurrencyCode, codes: allCurrencyCodes)
                        amountField("Amount Received", text: $toAmountText)
                        if let rate = exchangeRate {
                            LabeledContent("Rate") {
                                Text(verbatim: rate)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Description (optional)", text: $note)
                }
                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(Text(action.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                    }
                }
            }
            .onAppear(perform: seedDefaults)
            .task {
                guard action == .toPortfolio, let client = services.client else { return }
                let portfolios = (try? await client.send(Endpoints.portfolios())) ?? []
                otherPortfolios = portfolios.filter { $0.id != portfolioID }
            }
            .errorAlert($errorAlert)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var accountPicker: some View {
        Picker("Account", selection: $accountID) {
            Text("Choose").tag(String?.none)
            ForEach(accounts) { account in
                Text(verbatim: "\(account.name) · \(account.currencyCode)").tag(String?.some(account.id))
            }
        }
    }

    @ViewBuilder
    private var availableHint: some View {
        if let code = currencyCode, let balance = balances.first(where: { $0.currencyCode == code }) {
            LabeledContent("Available") {
                AmountText(balance.availableCash, currencyCode: code)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exchangeRate: String? {
        guard let from = parse(amountText), let to = parse(toAmountText), from > 0,
              let fromCode = currencyCode, let toCode = toCurrencyCode
        else { return nil }
        let rate = NSDecimalNumber(decimal: to / from).doubleValue
        return "1 \(fromCode) = \(rate.formatted(.number.precision(.significantDigits(1...6)))) \(toCode)"
    }

    private func currencyPicker(_ title: LocalizedStringKey, selection: Binding<String?>, codes: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("Choose").tag(String?.none)
            ForEach(codes, id: \.self) { code in
                Text(verbatim: code).tag(String?.some(code))
            }
        }
    }

    private func amountField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    private func seedDefaults() {
        guard currencyCode == nil else { return }
        let base = session.baseCurrency?.currencyCode
        switch action {
        case .deposit:
            currencyCode = balances.first?.currencyCode ?? base ?? allCurrencyCodes.first
        case .withdraw, .toAccount, .toPortfolio, .exchange:
            currencyCode = balanceCurrencyCodes.first
            if action == .exchange {
                toCurrencyCode = allCurrencyCodes.first { $0 != currencyCode }
            }
        case .fromAccount:
            break
        }
    }

    private func parse(_ text: String) -> Decimal? {
        EditorAmountParser.parse(text.trimmingCharacters(in: .whitespaces))
    }

    private func save() async {
        guard let amount = parse(amountText), amount > 0 else {
            return fail(String(localized: "Enter an amount greater than zero."))
        }
        let day = CalendarDate(date: date)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = trimmedNote.isEmpty ? nil : trimmedNote
        let endpoint: Endpoint<EmptyResponse>
        switch action {
        case .deposit, .withdraw:
            guard let currencyCode else { return fail(String(localized: "Choose a currency.")) }
            endpoint = Endpoints.portfolioCashTransactionCreate(portfolioId: portfolioID, PortfolioCashTransactionRequest(
                type: action == .deposit ? .deposit : .withdrawal,
                amount: amount,
                currencyCode: currencyCode,
                date: day,
                description: description,
                isAdjustment: isAdjustment
            ))
        case .fromAccount:
            guard let accountID else { return fail(String(localized: "Choose an account.")) }
            endpoint = Endpoints.portfolioTransferFromAccount(portfolioId: portfolioID, PortfolioTransferAccountRequest(
                accountId: accountID,
                amount: amount,
                date: day,
                description: description
            ))
        case .toAccount:
            guard let accountID else { return fail(String(localized: "Choose an account.")) }
            guard let currencyCode else { return fail(String(localized: "Choose a currency.")) }
            endpoint = Endpoints.portfolioTransferToAccount(portfolioId: portfolioID, PortfolioTransferAccountRequest(
                accountId: accountID,
                amount: amount,
                currencyCode: currencyCode,
                date: day,
                description: description
            ))
        case .toPortfolio:
            guard let targetPortfolioID else { return fail(String(localized: "Choose a portfolio.")) }
            guard let currencyCode else { return fail(String(localized: "Choose a currency.")) }
            endpoint = Endpoints.portfolioTransferToPortfolio(portfolioId: portfolioID, PortfolioTransferPortfolioRequest(
                toPortfolioId: targetPortfolioID,
                currencyCode: currencyCode,
                amount: amount,
                date: day,
                description: description
            ))
        case .exchange:
            guard let currencyCode, let toCurrencyCode else { return fail(String(localized: "Choose both currencies.")) }
            guard currencyCode != toCurrencyCode else { return fail(String(localized: "Choose two different currencies.")) }
            guard let toAmount = parse(toAmountText), toAmount > 0 else {
                return fail(String(localized: "Enter the amount received."))
            }
            endpoint = Endpoints.portfolioExchangeCurrency(portfolioId: portfolioID, PortfolioExchangeRequest(
                fromCurrencyCode: currencyCode,
                toCurrencyCode: toCurrencyCode,
                fromAmount: amount,
                toAmount: toAmount,
                date: day,
                description: description
            ))
        }
        guard let client = services.client else { return }
        validationMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.send(endpoint)
            await onSaved()
            dismiss()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func fail(_ message: String) {
        withAnimation { validationMessage = message }
    }
}
