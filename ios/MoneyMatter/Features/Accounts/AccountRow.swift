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

/// An `EntityRow` for an account: its initials tile, name over category, and the balance in
/// the account currency over its bank-sync state.
struct AccountRow: View {
    let account: Account
    var digits: Int?

    @State private var monitor = BankSyncMonitor.shared

    var body: some View {
        EntityRow(account.name, subtitle: AccountCategoryLabel.text(for: account.accountCategory)) {
            InitialsBadge(AccountInitials.text(for: account), colorHex: account.logoColor)
        } trailing: {
            VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                AmountText(account.currentBalance, currencyCode: account.currencyCode, digits: digits)
                    .font(.body)
                    .lineLimit(1)
                syncState
            }
        }
    }

    @ViewBuilder
    private var syncState: some View {
        if account.bankDataProviderConnectionId != nil {
            if monitor.needsRelink(account) {
                StatusBadge(label: String(localized: "Reconnect"), color: DS.Palette.warning)
                    .accessibilityLabel(Text("Bank connection needs reconnecting"))
            } else if monitor.status?.status(forAccountID: account.id)?.status == .syncing {
                StatusDot(String(localized: "Syncing"), color: DS.Palette.accent, pulsing: true, font: .footnote)
            }
        }
    }
}

extension View {
    /// A hero row in an inset-grouped list: no panel behind it, so the value sits on the canvas
    /// the way IntelliStock's dashboard hero does.
    func accountsHeroRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: DS.Space.s, leading: DS.Space.xs, bottom: DS.Space.s, trailing: DS.Space.xs))
    }
}
