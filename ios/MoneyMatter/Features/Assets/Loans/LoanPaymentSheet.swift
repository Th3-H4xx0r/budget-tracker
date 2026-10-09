import MoneyMatterKit
import SwiftUI

/// Records a payment into a loan from one of the user's accounts, as a transfer to the loan.
struct LoanPaymentSheet: View {
    let loan: Loan
    let onSaved: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var accountID: String?
    @State private var amount: Decimal?
    @State private var loanAmount: Decimal?
    @State private var date = Date.now
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Outstanding") {
                        Text(MoneyFormat.string(loan.outstanding, currencyCode: loan.currencyCode, digits: referenceData.digits(for: loan.currencyCode)))
                            .monospacedDigit()
                    }
                    if let planned = loan.loanDetails.plannedPayment, planned > 0 {
                        Button("Use Planned Payment: \(MoneyFormat.string(planned, currencyCode: loan.currencyCode))") {
                            if isCrossCurrency {
                                loanAmount = min(planned, loan.outstanding)
                            } else {
                                amount = min(planned, loan.outstanding)
                            }
                        }
                        .font(.subheadline)
                    }
                }

                Section {
                    Picker("From Account", selection: $accountID) {
                        Text("Choose").tag(String?.none)
                        ForEach(sourceAccounts) { account in
                            Text(account.name).tag(String?.some(account.id))
                        }
                    }
                    LabeledContent("Amount") {
                        TextField("0.00", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                        if let source = selectedAccount {
                            Text(source.currencyCode).foregroundStyle(.secondary)
                        }
                    }
                    if isCrossCurrency {
                        LabeledContent("Applied to Loan") {
                            TextField("0.00", value: $loanAmount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                            Text(loan.currencyCode).foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                } footer: {
                    if isOverpaying {
                        Text("The payment is more than the outstanding balance.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Record Payment")
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
            .task {
                if referenceData.accounts.isEmpty { await referenceData.loadIfNeeded() }
            }
        }
    }

    private var sourceAccounts: [Account] {
        referenceData.activeAccounts.filter {
            $0.id != loan.id && $0.accountCategory != .loan && $0.accountCategory != .vehicle
        }
    }

    private var selectedAccount: Account? {
        sourceAccounts.first { $0.id == accountID }
    }

    private var isCrossCurrency: Bool {
        guard let selectedAccount else { return false }
        return selectedAccount.currencyCode != loan.currencyCode
    }

    private var appliedAmount: Decimal? {
        isCrossCurrency ? loanAmount : amount
    }

    private var isOverpaying: Bool {
        guard let applied = appliedAmount else { return false }
        return applied > loan.outstanding
    }

    private var isValid: Bool {
        guard selectedAccount != nil, let amount, amount > 0, let applied = appliedAmount, applied > 0 else { return false }
        return !isOverpaying
    }

    private func save() async {
        guard let client = services.client, let source = selectedAccount, let amount, let applied = appliedAmount else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.send(Endpoints.loanPayment(
                loanId: loan.id,
                fromAccountId: source.id,
                amount: amount,
                loanAmount: applied,
                time: date
            ))
            onSaved()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
