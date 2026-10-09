import MoneyMatterKit
import SwiftUI

/// The standard transaction row, in the `EntityRow` structure: a category `IconTile`, the
/// title in `.headline`, an "account · time" subtitle, and the amount over a detail line
/// (the fraud badge for rows marked as fraud).
///
/// Title rule: payee name, else note, else category name.
struct TransactionRow: View {
    let transaction: Transaction
    let category: Category?
    let accountName: String?
    let payeeName: String?
    var digits: Int?
    /// Show the date as well as the time, for lists that aren't grouped by day.
    var showsDate = false

    var body: some View {
        EntityRow(title, subtitle: subtitle) {
            CategoryIconTile(category: category, isTransfer: transaction.isTransfer)
        } trailing: {
            VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                AmountText(transaction: transaction, digits: digits)
                    .font(.body)
                    .lineLimit(1)
                if transaction.isFraud {
                    FraudBadge()
                }
            }
        }
        .padding(.vertical, DS.Space.xxs)
    }

    private var title: String {
        if let payeeName, !payeeName.isEmpty { return payeeName }
        if let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { return note }
        if let category { return category.name }
        return transaction.isTransfer ? String(localized: "Transfer") : String(localized: "Transaction")
    }

    private var subtitle: String {
        let time = showsDate
            ? transaction.time.formatted(date: .abbreviated, time: .shortened)
            : transaction.time.formatted(date: .omitted, time: .shortened)
        guard let accountName, !accountName.isEmpty else { return time }
        return "\(accountName) · \(time)"
    }
}

/// The badge on rows marked as fraud: a red `StatusBadge`.
struct FraudBadge: View {
    var body: some View {
        StatusBadge(label: String(localized: "Fraud"), color: DS.Palette.danger)
    }
}

/// A `TransactionRow` that looks up the category, account, payee, and currency digits in
/// the session's `ReferenceDataStore`.
struct ResolvedTransactionRow: View {
    @Environment(ReferenceDataStore.self) private var referenceData
    let transaction: Transaction
    var showsDate = false

    var body: some View {
        TransactionRow(
            transaction: transaction,
            category: referenceData.category(id: transaction.categoryId),
            accountName: referenceData.account(id: transaction.accountId)?.name,
            payeeName: referenceData.payee(id: transaction.payeeId)?.name,
            digits: referenceData.digits(for: transaction.currencyCode),
            showsDate: showsDate
        )
    }
}

#Preview {
    let food = Category(id: "c", name: "Food & Drinks", color: "#e74c3c", icon: "food-20-filled")
    List {
        TransactionRow(
            transaction: Transaction(id: "1", amount: Decimal(string: "84.21")!, time: .now, transactionType: .expense, accountId: "a", currencyCode: "USD", categoryId: "c"),
            category: food,
            accountName: "Checking",
            payeeName: "Lidl"
        )
        TransactionRow(
            transaction: Transaction(id: "2", amount: 1500, time: .now, transactionType: .income, accountId: "a", currencyCode: "USD", note: "Salary"),
            category: nil,
            accountName: "Checking",
            payeeName: nil
        )
        TransactionRow(
            transaction: Transaction(id: "3", amount: 40, time: .now, transactionType: .expense, accountId: "a", currencyCode: "USD", reviewStatus: .fraud),
            category: food,
            accountName: "Card",
            payeeName: "Unknown merchant"
        )
        TransactionRow(
            transaction: Transaction(id: "4", amount: 200, time: .now, transactionType: .expense, accountId: "a", currencyCode: "USD", transferNature: .betweenUserAccounts),
            category: nil,
            accountName: "Checking",
            payeeName: nil
        )
    }
}
