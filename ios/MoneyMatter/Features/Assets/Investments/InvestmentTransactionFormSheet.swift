import MoneyMatterKit
import SwiftUI

/// Create or edit a buy or sell, with an optional settlement in another currency.
struct InvestmentTransactionFormSheet: View {
    let portfolioID: String
    let securityID: String
    let securityCurrencyCode: String
    let symbol: String
    let initialCategory: InvestmentTransactionCategory
    let existing: InvestmentTransaction?
    let onSaved: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var category: InvestmentTransactionCategory = .buy
    @State private var date = Date.now
    @State private var quantity: Decimal?
    @State private var price: Decimal?
    @State private var fees: Decimal?
    @State private var note = ""
    @State private var usesSettlement = false
    @State private var settlementCurrencyCode: String?
    @State private var settlementAmount: Decimal?
    @State private var settlementMode: SettlementMode = .fee
    @State private var settlementFees: Decimal?
    @State private var settlementRate: Decimal?
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    enum SettlementMode: String, CaseIterable, Identifiable {
        case fee
        case rate
        case market

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .fee: "Fee"
            case .rate: "Rate"
            case .market: "Market Rate"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $category) {
                        Text(InvestmentTransactionCategory.buy.title).tag(InvestmentTransactionCategory.buy)
                        Text(InvestmentTransactionCategory.sell.title).tag(InvestmentTransactionCategory.sell)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    LabeledContent("Quantity") {
                        TextField("0", value: $quantity, format: PortfolioNumberFormat.input)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    LabeledContent("Price (\(securityCurrencyCode))") {
                        TextField("0.00", value: $price, format: PortfolioNumberFormat.input)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    LabeledContent("Fees") {
                        TextField("0.00", value: $fees, format: PortfolioNumberFormat.input)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    if let gross {
                        LabeledContent("Total") {
                            Text(verbatim: MoneyFormat.string(gross, currencyCode: securityCurrencyCode))
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    Text("A price of zero records a position change with no cash, such as an airdrop or staking reward.")
                }
                Section {
                    Toggle("Settled in Another Currency", isOn: $usesSettlement.animation())
                    if usesSettlement {
                        CurrencyPickerLink(
                            title: "Settlement Currency",
                            currencies: referenceData.userCurrencies.compactMap(\.currency),
                            selection: $settlementCurrencyCode
                        )
                        LabeledContent("Cash Moved") {
                            TextField("0.00", value: $settlementAmount, format: PortfolioNumberFormat.input)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                        if isCrossCurrency {
                            Picker("Derive From", selection: $settlementMode) {
                                ForEach(SettlementMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            switch settlementMode {
                            case .fee:
                                LabeledContent("Settlement Fee") {
                                    TextField("0.00", value: $settlementFees, format: PortfolioNumberFormat.input)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .monospacedDigit()
                                }
                            case .rate:
                                LabeledContent("Rate") {
                                    TextField("1.0", value: $settlementRate, format: PortfolioNumberFormat.input)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .monospacedDigit()
                                }
                            case .market:
                                Text("The fee is derived from the market rate on the trade date.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    if usesSettlement {
                        Text("Enter the total cash that left or entered the portfolio in the settlement currency.")
                    }
                }
                Section {
                    TextField("Note", text: $note)
                }
            }
            .navigationTitle(existing == nil ? Text("\(category == .sell ? "Sell" : "Buy") \(symbol)") : Text("Edit Transaction"))
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
                            .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($alert)
            .onAppear(perform: populate)
        }
    }

    private var gross: Decimal? {
        guard let quantity, let price else { return nil }
        return quantity * price
    }

    private var isCrossCurrency: Bool {
        guard let settlementCurrencyCode else { return false }
        return settlementCurrencyCode != securityCurrencyCode
    }

    private var canSave: Bool {
        guard let quantity, quantity > 0, let price, price >= 0 else { return false }
        if let fees, fees < 0 { return false }
        if usesSettlement {
            guard settlementCurrencyCode != nil, let settlementAmount, settlementAmount >= 0 else { return false }
            if isCrossCurrency, settlementMode == .rate, (settlementRate ?? 0) <= 0 { return false }
        }
        return true
    }

    private var settlement: InvestmentTransactionSettlement? {
        guard usesSettlement, let settlementCurrencyCode, let settlementAmount else { return nil }
        var value = InvestmentTransactionSettlement(currencyCode: settlementCurrencyCode, amount: settlementAmount)
        if !isCrossCurrency {
            value.fees = settlementFees ?? 0
        } else {
            switch settlementMode {
            case .fee: value.fees = settlementFees ?? 0
            case .rate: value.rate = settlementRate
            case .market: break
            }
        }
        return value
    }

    private var day: CalendarDate { CalendarDate(date: date) }

    /// The settlement to send on edit, or `nil` when the stored one is untouched, so its
    /// recorded fee isn't re-derived from the market rate.
    private func changedSettlement(from existing: InvestmentTransaction) -> InvestmentTransactionSettlement? {
        if existing.hasSettlement,
           settlementCurrencyCode == existing.settlementCurrencyCode,
           settlementAmount == existing.settlementAmount,
           settlementMode == .market {
            return nil
        }
        return settlement
    }

    private func populate() {
        category = initialCategory == .sell ? .sell : .buy
        guard let existing else { return }
        if let tradeDay = existing.day { date = tradeDay.startDate() }
        quantity = existing.quantity
        price = existing.price
        fees = existing.fees
        note = existing.name ?? ""
        if existing.hasSettlement {
            usesSettlement = true
            settlementCurrencyCode = existing.settlementCurrencyCode
            settlementAmount = existing.settlementAmount
            settlementMode = .market
        }
    }

    private func save() async {
        guard let quantity, let price else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let existing {
                let request = InvestmentTransactionUpdateRequest(
                    category: category,
                    date: day,
                    quantity: quantity,
                    price: price,
                    fees: fees ?? 0,
                    name: trimmedNote,
                    settlement: changedSettlement(from: existing)
                )
                _ = try await services.investmentsSend(Endpoints.investmentTransactionUpdate(id: existing.id, request))
            } else {
                let request = InvestmentTransactionCreateRequest(
                    portfolioId: portfolioID,
                    securityId: securityID,
                    category: category,
                    date: day,
                    quantity: quantity,
                    price: price,
                    fees: fees ?? 0,
                    name: trimmedNote.isEmpty ? nil : trimmedNote,
                    settlement: settlement
                )
                _ = try await services.investmentsSend(Endpoints.investmentTransactionCreate(request))
            }
            onSaved()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
