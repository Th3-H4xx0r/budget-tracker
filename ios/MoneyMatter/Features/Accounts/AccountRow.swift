import MoneyMatterKit
import SwiftUI

/// User-facing names for account categories.
enum AccountCategoryLabel {
    static func text(for category: AccountCategory) -> String {
        switch category {
        case .general: String(localized: "General")
        case .cash: String(localized: "Cash")
        case .currentAccount: String(localized: "Current Account")
        case .creditCard: String(localized: "Credit Card")
        case .saving: String(localized: "Savings")
        case .bonus: String(localized: "Bonus")
        case .insurance: String(localized: "Insurance")
        case .investment: String(localized: "Investment")
        case .loan: String(localized: "Loan")
        case .overdraft: String(localized: "Overdraft")
        case .crypto: String(localized: "Crypto")
        case .vehicle: String(localized: "Vehicle")
        case .unknown: String(localized: "Other")
        }
    }
}

/// An account's monogram: its logo initials, else the first letters of its name.
enum AccountInitials {
    static func text(for account: Account) -> String {
        if let initials = account.logoInitials, !initials.isEmpty { return initials }
        let words = account.name.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters
    }
}

/// Initials badge, name, category, and balance in the account currency.
struct AccountRow: View {
    let account: Account
    var digits: Int?

    var body: some View {
        HStack(spacing: 12) {
            InitialsBadge(AccountInitials.text(for: account), colorHex: account.logoColor, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .lineLimit(1)
                Text(AccountCategoryLabel.text(for: account.accountCategory))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            AmountText(account.currentBalance, currencyCode: account.currencyCode, digits: digits)
                .font(.body.weight(.medium))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
