import MoneyMatterKit
import SwiftUI

/// How an amount is coloured: income green, expense primary with a leading minus, transfer
/// secondary.
enum AmountStyle: Hashable {
    case income
    case expense
    case transfer
    case neutral

    init(_ transaction: Transaction) {
        if transaction.isTransfer {
            self = .transfer
        } else {
            self = transaction.transactionType == .income ? .income : .expense
        }
    }

    var color: Color {
        switch self {
        case .income: .green
        case .expense, .neutral: .primary
        case .transfer: .secondary
        }
    }
}

/// A formatted money amount with tabular digits and a spoken VoiceOver label
/// ("minus $84.21" reads as "minus 84 dollars and 21 cents"). Set the font on it like `Text`.
struct AmountText: View {
    let amount: Decimal
    let currencyCode: String
    var digits: Int?
    var style: AmountStyle = .neutral
    var showsPlusSign = false

    /// The signed amount of a transaction, coloured by its type.
    init(transaction: Transaction, digits: Int? = nil) {
        self.amount = transaction.signedAmount
        self.currencyCode = transaction.currencyCode
        self.digits = digits
        self.style = AmountStyle(transaction)
    }

    init(_ amount: Decimal, currencyCode: String, digits: Int? = nil, style: AmountStyle = .neutral, showsPlusSign: Bool = false) {
        self.amount = amount
        self.currencyCode = currencyCode
        self.digits = digits
        self.style = style
        self.showsPlusSign = showsPlusSign
    }

    private var displayedAmount: Decimal {
        switch style {
        case .expense: -abs(amount)
        case .income: abs(amount)
        case .transfer, .neutral: amount
        }
    }

    var body: some View {
        Text(verbatim: MoneyFormat.string(
            displayedAmount,
            currencyCode: currencyCode,
            digits: digits,
            sign: showsPlusSign ? .always : .automatic
        ))
        .monospacedDigit()
        .foregroundStyle(style.color)
        .accessibilityLabel(Text(verbatim: MoneyFormat.spokenString(
            displayedAmount,
            currencyCode: currencyCode,
            digits: digits,
            minusWord: String(localized: "minus", comment: "Spoken before a negative amount")
        )))
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: 8) {
        AmountText(Decimal(string: "84.21")!, currencyCode: "USD", style: .expense)
        AmountText(1500, currencyCode: "EUR", style: .income)
        AmountText(250, currencyCode: "GBP", style: .transfer)
        AmountText(Decimal(string: "12.5")!, currencyCode: "USD", showsPlusSign: true)
    }
    .font(.title3)
}
