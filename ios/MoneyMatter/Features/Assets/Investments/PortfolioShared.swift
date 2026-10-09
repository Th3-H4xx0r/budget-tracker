import MoneyMatterKit
import SwiftUI

extension AppServices {
    /// Sends an investments endpoint through the signed-in client.
    func investmentsSend<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        guard let client else { throw APIError.network(URLError(.userAuthenticationRequired)) }
        return try await client.send(endpoint)
    }
}

extension PortfolioType {
    var title: LocalizedStringKey {
        switch self {
        case .investment: "Investment"
        case .retirement: "Retirement"
        case .savings: "Savings"
        case .other, .unknown: "Other"
        }
    }

    static var selectable: [PortfolioType] { [.investment, .retirement, .savings, .other] }
}

extension InvestmentTransactionCategory {
    var title: LocalizedStringKey {
        switch self {
        case .buy: "Buy"
        case .sell: "Sell"
        case .dividend: "Dividend"
        case .transfer: "Transfer"
        case .tax: "Tax"
        case .fee: "Fee"
        case .cancel: "Cancel"
        case .other, .unknown: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .buy: "arrow.down.left.circle.fill"
        case .sell: "arrow.up.right.circle.fill"
        case .dividend: "dollarsign.circle.fill"
        default: "circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .buy: .blue
        case .sell: .green
        case .dividend: .teal
        default: .secondary
        }
    }
}

/// A gain or loss amount with its percentage, green when positive and red when negative.
struct PortfolioGainText: View {
    let value: Decimal
    let percent: Decimal?
    let currencyCode: String

    var body: some View {
        let amount = MoneyFormat.string(value, currencyCode: currencyCode, sign: .always)
        Group {
            if let percent {
                Text(verbatim: "\(amount) (\(Self.percentString(percent)))")
            } else {
                Text(verbatim: amount)
            }
        }
        .monospacedDigit()
        .foregroundStyle(value > 0 ? Color.green : (value < 0 ? Color.red : Color.secondary))
    }

    static func percentString(_ percent: Decimal) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(0...2)).sign(strategy: .always(includingZero: false)))
    }
}

/// A plain decimal formatter for quantities and prices, keeping crypto-sized precision.
enum PortfolioNumberFormat {
    static let input = Decimal.FormatStyle.number.precision(.fractionLength(0...10))

    static func quantity(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...8)))
    }
}

/// A transaction row for buys, sells and other trades.
struct InvestmentTransactionListRow: View {
    let transaction: InvestmentTransaction
    var showsSymbol = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category.symbolName)
                .font(.title2)
                .foregroundStyle(transaction.category.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(transaction.category.title)
                        .font(.body.weight(.medium))
                    if showsSymbol, let security = transaction.security {
                        Text(verbatim: "· \(security.displaySymbol)")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    if let date = transaction.date {
                        Text(date, format: .dateTime.day().month(.abbreviated).year())
                    }
                    if let quantity = transaction.quantity {
                        Text(verbatim: "· \(PortfolioNumberFormat.quantity(quantity))")
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: MoneyFormat.string(transaction.amount, currencyCode: transaction.currencyCode))
                    .monospacedDigit()
                    .foregroundStyle(transaction.category == .sell ? Color.green : Color.primary)
                if let price = transaction.price {
                    Text(verbatim: "@ \(MoneyFormat.string(price, currencyCode: transaction.currencyCode))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
