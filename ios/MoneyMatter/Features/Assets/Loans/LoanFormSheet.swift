import MoneyMatterKit
import SwiftUI

/// Creates a loan, or edits one when `loan` is set. Edits send only changed fields.
struct LoanFormSheet: View {
    let loan: Loan?
    let onSaved: (Loan) -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var currencyCode = ""
    @State private var loanType: LoanType = .personal
    @State private var originalPrincipal: Decimal?
    @State private var balance: Decimal?
    @State private var balanceAsOf = Date.now
    @State private var interestRate: Decimal?
    @State private var termMonths: Int?
    @State private var startDate = Date.now
    @State private var minPayment: Decimal?
    @State private var plannedPayment: Decimal?
    @State private var paymentDay: Int?
    @State private var lenderName = ""
    @State private var accountNumber = ""
    @State private var isSaving = false
    @State private var alert: ErrorAlert?
    @State private var didPrefill = false

    private var isEditing: Bool { loan != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    if !isEditing {
                        Picker("Type", selection: $loanType) {
                            ForEach(LoanType.supported, id: \.self) { type in
                                Label(type.loanDisplayName, systemImage: type.loanSymbol).tag(type)
                            }
                        }
                        Picker("Currency", selection: $currencyCode) {
                            ForEach(currencyCodes, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                    }
                    TextField("Lender (optional)", text: $lenderName)
                    TextField("Account Number (optional)", text: $accountNumber)
                }

                Section {
                    if !isEditing {
                        amountField("Original Principal", value: $originalPrincipal)
                    }
                    amountField(isEditing ? "Current Balance" : "Outstanding Balance", value: $balance)
                    if isEditing && balanceChanged {
                        DatePicker("Balance As Of", selection: $balanceAsOf, in: ...Date.now, displayedComponents: .date)
                    }
                } header: {
                    Text("Amounts")
                } footer: {
                    if isEditing {
                        Text("Changing the balance records a correction in the timeline.")
                    } else {
                        Text("The outstanding balance is what you still owe today.")
                    }
                }

                Section("Terms") {
                    LabeledContent("Interest Rate (APR)") {
                        TextField("0.00", value: $interestRate, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                        Text("%").foregroundStyle(.secondary)
                    }
                    LabeledContent("Term (Months)") {
                        TextField("Optional", value: $termMonths, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    DatePicker("Start Date", selection: $startDate, in: ...Date.now, displayedComponents: .date)
                }

                Section {
                    amountField("Planned Payment", value: $plannedPayment)
                    amountField("Minimum Payment", value: $minPayment)
                    if let suggested = suggestedMinimum, minPayment != suggested {
                        Button("Use Suggested Minimum: \(MoneyFormat.string(suggested, currencyCode: effectiveCurrency))") {
                            minPayment = suggested
                        }
                        .font(.subheadline)
                    }
                    Picker("Payment Day", selection: $paymentDay) {
                        Text("None").tag(Int?.none)
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(Int?.some(day))
                        }
                    }
                } header: {
                    Text("Payments")
                } footer: {
                    Text("The planned payment drives the payoff projection.")
                }
            }
            .navigationTitle(isEditing ? "Edit Loan" : "New Loan")
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
                            .disabled(!isValid)
                    }
                }
            }
            .errorAlert($alert)
            .interactiveDismissDisabled(isSaving)
            .onAppear(perform: prefill)
        }
    }

    private func amountField(_ title: LocalizedStringKey, value: Binding<Decimal?>) -> some View {
        LabeledContent(title) {
            TextField("0.00", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    private var currencyCodes: [String] {
        var codes = referenceData.userCurrencies.map(\.currencyCode)
        if !currencyCode.isEmpty, !codes.contains(currencyCode) { codes.insert(currencyCode, at: 0) }
        return codes
    }

    private var effectiveCurrency: String {
        loan?.currencyCode ?? (currencyCode.isEmpty ? "USD" : currencyCode)
    }

    private var suggestedMinimum: Decimal? {
        LoanMath.minimumPayment(
            principal: originalPrincipal ?? loan?.loanDetails.originalPrincipal ?? 0,
            interestRate: interestRate ?? 0,
            termMonths: termMonths
        )
    }

    private var balanceChanged: Bool {
        guard let loan, let balance else { return false }
        return balance != loan.outstanding
    }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let rate = interestRate, rate >= 0, rate < 100 else { return false }
        if let termMonths, !(1...1200).contains(termMonths) { return false }
        if (balance ?? 0) < 0 || (minPayment ?? 0) < 0 || (plannedPayment ?? 0) < 0 { return false }
        if isEditing { return true }
        guard !currencyCode.isEmpty, let principal = originalPrincipal, principal > 0, balance != nil else { return false }
        return true
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        if let loan {
            let details = loan.loanDetails
            name = loan.name
            currencyCode = loan.currencyCode
            loanType = details.loanType
            originalPrincipal = details.originalPrincipal
            balance = loan.outstanding
            interestRate = details.interestRate
            termMonths = details.termMonths
            startDate = details.startDate.startDate()
            minPayment = details.minPayment
            plannedPayment = details.plannedPayment
            paymentDay = details.paymentDayOfMonth
            lenderName = details.lenderName ?? ""
            accountNumber = details.accountNumber ?? ""
        } else {
            currencyCode = referenceData.userCurrencies.first(where: \.isDefaultCurrency)?.currencyCode
                ?? referenceData.userCurrencies.first?.currencyCode
                ?? ""
        }
    }

    private func optionalText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() async {
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved: Loan
            if let loan {
                let request = updateRequest(for: loan)
                guard !request.isEmpty else {
                    dismiss()
                    return
                }
                saved = try await client.send(Endpoints.loanUpdate(id: loan.id, request))
            } else {
                let request = LoanCreateRequest(
                    name: name.trimmingCharacters(in: .whitespaces),
                    currencyCode: currencyCode,
                    initialBalance: balance ?? 0,
                    loanType: loanType,
                    originalPrincipal: originalPrincipal ?? 0,
                    interestRate: interestRate ?? 0,
                    termMonths: termMonths,
                    startDate: CalendarDate(date: startDate),
                    minPayment: minPayment,
                    plannedPayment: plannedPayment,
                    paymentDayOfMonth: paymentDay,
                    lenderName: optionalText(lenderName),
                    accountNumber: optionalText(accountNumber)
                )
                saved = try await client.send(Endpoints.loanCreate(request))
            }
            await referenceData.refreshAccounts()
            onSaved(saved)
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func updateRequest(for loan: Loan) -> LoanUpdateRequest {
        let details = loan.loanDetails
        var request = LoanUpdateRequest()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName != loan.name { request.name = trimmedName }
        if balanceChanged, let balance {
            request.currentBalance = balance
            request.currentBalanceAsOf = CalendarDate(date: balanceAsOf)
        }
        if let interestRate, interestRate != details.interestRate { request.interestRate = interestRate }
        if termMonths != details.termMonths { request.termMonths = termMonths.map { FieldUpdate.set($0) } ?? .clear }
        let start = CalendarDate(date: startDate)
        if start != details.startDate { request.startDate = start }
        if minPayment != details.minPayment { request.minPayment = minPayment.map { FieldUpdate.set($0) } ?? .clear }
        if plannedPayment != details.plannedPayment { request.plannedPayment = plannedPayment.map { FieldUpdate.set($0) } ?? .clear }
        if paymentDay != details.paymentDayOfMonth { request.paymentDayOfMonth = paymentDay.map { FieldUpdate.set($0) } ?? .clear }
        let lender = optionalText(lenderName)
        if lender != details.lenderName { request.lenderName = lender.map { FieldUpdate.set($0) } ?? .clear }
        let number = optionalText(accountNumber)
        if number != details.accountNumber { request.accountNumber = number.map { FieldUpdate.set($0) } ?? .clear }
        return request
    }
}
