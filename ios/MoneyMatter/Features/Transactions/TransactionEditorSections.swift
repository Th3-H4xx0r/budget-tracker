import MoneyMatterKit
import SwiftUI

/// Display names for payment types.
enum TransactionPaymentTypeLabel {
    static let selectable: [PaymentType] = [.creditCard, .debitCard, .cash, .bankTransfer, .webPayment, .mobilePayment, .voucher]

    static func title(_ type: PaymentType) -> String {
        switch type {
        case .bankTransfer: String(localized: "Bank Transfer")
        case .voucher: String(localized: "Voucher")
        case .webPayment: String(localized: "Web Payment")
        case .cash: String(localized: "Cash")
        case .mobilePayment: String(localized: "Mobile Payment")
        case .creditCard: String(localized: "Credit Card")
        case .debitCard: String(localized: "Debit Card")
        case .unknown: String(localized: "Other")
        }
    }
}

/// Up to 10 split rows with a remaining-amount line. The remainder stays on the main category.
struct TransactionSplitsSection: View {
    @Bindable var model: TransactionEditorModel
    let currencyCode: String?

    @Environment(ReferenceDataStore.self) private var referenceData

    var body: some View {
        Section {
            ForEach($model.splits) { $row in
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink {
                        TransactionCategoryPicker(
                            isSelected: { $0 == row.categoryId },
                            onSelect: { row.categoryId = $0.id }
                        )
                    } label: {
                        if let category = referenceData.category(id: row.categoryId) {
                            HStack(spacing: 8) {
                                CategoryIcon(category: category, size: 22)
                                Text(category.name)
                            }
                        } else {
                            Text("Choose Category")
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        TextField("Amount", text: $row.amountText)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                        TextField("Note", text: $row.note)
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { model.splits.remove(atOffsets: $0) }

            if model.canAddSplit {
                Button("Add Split", systemImage: "plus.circle") {
                    withAnimation { model.splits.append(.init()) }
                }
            }
        } header: {
            Text("Splits")
        } footer: {
            if !model.splits.isEmpty {
                remainingLine
            } else {
                Text("Split the amount across several categories. Up to 10 splits.")
            }
        }
    }

    private var remainingLine: some View {
        let remaining = model.remainingAfterSplits
        let digits = referenceData.digits(for: currencyCode) ?? 2
        return HStack(spacing: 4) {
            Text("Left on the main category:")
            Text(verbatim: currencyCode.map { MoneyFormat.string(remaining, currencyCode: $0, digits: digits) } ?? "\(remaining)")
                .monospacedDigit()
                .foregroundStyle(remaining < 0 ? .red : .secondary)
        }
    }
}

/// Payment type, planned toggle, original amount, location, and the refund link.
struct TransactionDetailsFieldsSection: View {
    @Bindable var model: TransactionEditorModel
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var isPickingLocation = false

    var body: some View {
        Section {
            if model.kind != .transfer, !model.keepsTransferNature {
                Picker("Payment Type", selection: $model.paymentType) {
                    ForEach(TransactionPaymentTypeLabel.selectable, id: \.self) { type in
                        Text(TransactionPaymentTypeLabel.title(type)).tag(type)
                    }
                }
            }
            if model.showsPlannedToggle {
                Toggle(isOn: $model.isPlanned) {
                    Label("Planned", systemImage: "calendar.badge.clock")
                }
            }
            if model.showsRefund {
                NavigationLink {
                    TransactionPickScreen(purpose: .refundOriginal(
                        transactionId: model.editedTransaction?.id,
                        type: model.kind == .income ? .income : .expense,
                        amount: model.amount,
                        accountId: model.accountId
                    )) { picked in
                        model.refundOf = picked
                    }
                } label: {
                    LabeledContent("Refund Of") {
                        Text(model.refundOf.map(refundSummary) ?? String(localized: "None"))
                            .lineLimit(1)
                    }
                }
                if model.refundOf != nil {
                    Button("Remove Refund Link", role: .destructive) {
                        model.refundOf = nil
                    }
                }
            }
            Button {
                isPickingLocation = true
            } label: {
                LabeledContent("Location") {
                    Text(model.location == nil ? String(localized: "None") : String(localized: "Pinned"))
                }
            }
            .foregroundStyle(.primary)
        } footer: {
            if model.showsPlannedToggle {
                Text("Planned transactions are expected payments. They can be matched with the real one later, also on bank-connected accounts.")
            }
        }
        .sheet(isPresented: $isPickingLocation) {
            TransactionLocationPickerSheet(location: model.location) { model.location = $0 }
        }

        Section("Original Amount") {
            LabeledContent("Amount") {
                TextField("Optional", text: $model.originalAmountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
            Picker("Currency", selection: $model.originalCurrencyCode) {
                Text("None").tag(String?.none)
                ForEach(currencyCodes, id: \.self) { code in
                    Text(verbatim: code).tag(String?.some(code))
                }
            }
        }
    }

    private var currencyCodes: [String] {
        var codes = referenceData.userCurrencies.map(\.currencyCode)
        if let code = model.originalCurrencyCode, !codes.contains(code) { codes.append(code) }
        return codes.sorted()
    }

    private func refundSummary(_ transaction: Transaction) -> String {
        let digits = referenceData.digits(for: transaction.currencyCode) ?? 2
        let amount = MoneyFormat.string(transaction.amount, currencyCode: transaction.currencyCode, digits: digits)
        return "\(amount) · \(transaction.time.formatted(date: .abbreviated, time: .omitted))"
    }
}
