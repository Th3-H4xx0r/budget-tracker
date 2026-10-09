import MoneyMatterKit
import SwiftUI
import UIKit

/// Shared pieces of the payee screens.
enum OrgPayeeSupport {
    /// The connected client, or a network failure when services are stubbed.
    static func client(_ services: AppServices) throws -> APIClient {
        guard let client = services.client else { throw APIError.network(URLError(.notConnectedToInternet)) }
        return client
    }

    /// `#rrggbb` lowercase, as the API stores logo colours.
    static func hex(from color: Color) -> String {
        let resolved = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", channel(red), channel(green), channel(blue))
    }

    static func baseCurrencyCode(_ referenceData: ReferenceDataStore) -> String {
        referenceData.userCurrencies.first(where: \.isDefaultCurrency)?.currencyCode ?? "USD"
    }

    /// True for a 409 from a payee name or alias write.
    static func isConflict(_ error: any Error) -> Bool {
        if case .server(let statusCode, _, _) = APIError(error), statusCode == 409 { return true }
        return false
    }

    static func title(for mode: OrgPayeeCategorizationMode) -> String {
        switch mode {
        case .enforce: String(localized: "Always Apply")
        case .hint: String(localized: "Suggest Only")
        case .off: String(localized: "Off")
        case .unknown: String(localized: "Unknown")
        }
    }

    static func hint(for mode: OrgPayeeCategorizationMode) -> String {
        switch mode {
        case .enforce: String(localized: "New transactions from this payee get the default category.")
        case .hint: String(localized: "The default category is a starting point; AI can pick a better one from the description.")
        case .off: String(localized: "The default category isn't used; AI categorizes from scratch.")
        case .unknown: ""
        }
    }

    static func title(for sort: OrgPayeeSortField) -> String {
        switch sort {
        case .transactionCount: String(localized: "Transactions")
        case .netFlow: String(localized: "Net Flow")
        case .name: String(localized: "Name")
        case .lastSeen: String(localized: "Last Seen")
        }
    }
}

/// The payee's monogram: custom initials on their colour, else the name's first letter.
struct OrgPayeeLogoBadge: View {
    let name: String
    let initials: String?
    let colorHex: String?
    var size: CGFloat = 36

    var body: some View {
        let custom = initials?.trimmingCharacters(in: .whitespaces)
        if let custom, !custom.isEmpty {
            InitialsBadge(custom, colorHex: colorHex ?? "#7c3aed", size: size)
        } else {
            InitialsBadge(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased(), colorHex: nil, size: size)
        }
    }
}

/// The signed net flow in the base currency: income green, spending primary.
struct OrgPayeeNetFlowText: View {
    let amount: Decimal
    let currencyCode: String

    var body: some View {
        AmountText(
            amount,
            currencyCode: currencyCode,
            style: amount > 0 ? .income : (amount < 0 ? .expense : .neutral),
            showsPlusSign: amount > 0
        )
        .monospacedDigit()
    }
}
