import MoneyMatterKit
import SwiftUI

/// Creates an account, or edits one's name, category, credit limit, stats exclusion, and
/// (for manually managed accounts) current balance.
struct AccountFormSheet: View {
    enum Mode {
        case create
        case edit(Account)
    }

    let mode: Mode

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var currencyCode: String?
    @State private var category: AccountCategory
    @State private var initialBalanceText = ""
    @State private var creditLimitText: String
    @State private var currentBalanceText: String
    @State private var excludeFromStats: Bool
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var errorAlert: ErrorAlert?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _currencyCode = State(initialValue: nil)
            _category = State(initialValue: .general)
            _creditLimitText = State(initialValue: "")
            _currentBalanceText = State(initialValue: "")
            _excludeFromStats = State(initialValue: false)
        case .edit(let account):
            _name = State(initialValue: account.name)
            _currencyCode = State(initialValue: account.currencyCode)
            _category = State(initialValue: account.accountCategory)
            _creditLimitText = State(initialValue: account.creditLimit == 0 ? "" : EditorAmountParser.text(account.creditLimit))
            _currentBalanceText = State(initialValue: EditorAmountParser.text(account.currentBalance))
            _excludeFromStats = State(initialValue: account.excludeFromStats)
        }
    }

    private var editedAccount: Account? {
        if case .edit(let account) = mode { return account }
        return nil
    }

    private var categoryOptions: [AccountCategory] {
        var options = AccountCategory.creatable
        if let current = editedAccount?.accountCategory, !options.contains(current) {
            options.append(current)
        }
        return options
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    if editedAccount == nil {
                        Picker("Currency", selection: $currencyCode) {
                            Text("Choose").tag(String?.none)
                            ForEach(referenceData.userCurrencies) { currency in
                                Text(verbatim: currency.currency.map { "\(currency.currencyCode) · \($0.currency)" } ?? currency.currencyCode)
                                    .tag(String?.some(currency.currencyCode))
                            }
                        }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(categoryOptions, id: \.self) { option in
                            Text(AccountCategoryLabel.text(for: option)).tag(option)
                        }
                    }
                }
                Section {
                    if editedAccount == nil {
                        amountRow("Initial Balance", text: $initialBalanceText, allowsNegative: true)
                    }
                    if category == .creditCard {
                        amountRow("Credit Limit", text: $creditLimitText, allowsNegative: false)
                    }
                    if editedAccount?.isSystem == true {
                        amountRow("Current Balance", text: $currentBalanceText, allowsNegative: true)
                    }
                } footer: {
                    if editedAccount?.isSystem == true {
                        Text("Changing the current balance adds a balance adjustment.")
                    }
                }
                if editedAccount != nil {
                    Section {
                        Toggle("Exclude from Statistics", isOn: $excludeFromStats)
                    } footer: {
                        Text("Excluded accounts don't count toward net worth or statistics.")
                    }
                }
                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editedAccount == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                    }
                }
            }
            .onAppear {
                if currencyCode == nil {
                    currencyCode = session.baseCurrency?.currencyCode ?? referenceData.userCurrencies.first?.currencyCode
                }
            }
            .errorAlert($errorAlert)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func amountRow(_ title: LocalizedStringKey, text: Binding<String>, allowsNegative: Bool) -> some View {
        LabeledContent(title) {
            TextField("0", text: text)
                .keyboardType(allowsNegative ? .numbersAndPunctuation : .decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    /// Empty fields are fine; typed text must parse as a number.
    private func isValidOptionalAmount(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || EditorAmountParser.parse(trimmed) != nil
    }

    private func validate() -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Enter a name.")
        }
        if editedAccount == nil, currencyCode == nil {
            return String(localized: "Choose a currency.")
        }
        for text in [initialBalanceText, creditLimitText, currentBalanceText] where !isValidOptionalAmount(text) {
            return String(localized: "Enter amounts as numbers.")
        }
        return nil
    }

    private func save() async {
        if let message = validate() {
            withAnimation { validationMessage = message }
            return
        }
        validationMessage = nil
        isSaving = true
        defer { isSaving = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let creditLimit = category == .creditCard ? EditorAmountParser.parse(creditLimitText) : nil
        do {
            let saved: Account
            if let account = editedAccount {
                var request = AccountUpdateRequest()
                if trimmedName != account.name { request.name = trimmedName }
                if category != account.accountCategory { request.accountCategory = category }
                if let creditLimit, creditLimit != account.creditLimit { request.creditLimit = creditLimit }
                if excludeFromStats != account.excludeFromStats { request.excludeFromStats = excludeFromStats }
                if account.isSystem, let balance = EditorAmountParser.parse(currentBalanceText), balance != account.currentBalance {
                    request.currentBalance = balance
                }
                saved = try await services.accounts.updateAccount(id: account.id, request)
            } else {
                saved = try await services.accounts.createAccount(AccountCreateRequest(
                    name: trimmedName,
                    currencyCode: currencyCode ?? "",
                    accountCategory: category,
                    initialBalance: EditorAmountParser.parse(initialBalanceText),
                    creditLimit: creditLimit
                ))
            }
            referenceData.upsert(saved)
            if editedAccount?.currentBalance != saved.currentBalance, editedAccount != nil {
                TransactionChangeFeed.shared.publish(.invalidated)
            }
            dismiss()
        } catch {
            let apiError = APIError(error)
            if case .validation = apiError {
                withAnimation { validationMessage = ErrorMessage.message(for: apiError) }
            } else {
                errorAlert = ErrorAlert(error)
            }
        }
    }
}
