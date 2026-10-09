import MoneyMatterKit
import SwiftUI

/// The standard transaction row: category circle, title, "account · time" subtitle,
/// coloured amount, and a Fraud capsule for rows marked as fraud.
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            CategoryIcon(category: category, isTransfer: transaction.isTransfer)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                    AmountText(transaction: transaction, digits: digits)
                        .font(.body.weight(.medium))
                    if transaction.isFraud {
                        FraudBadge()
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
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

/// The red capsule on rows marked as fraud.
struct FraudBadge: View {
    var body: some View {
        Text("Fraud")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red, in: .capsule)
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
