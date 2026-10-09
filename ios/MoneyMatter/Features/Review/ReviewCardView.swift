import MoneyMatterKit
import SwiftUI

/// The transaction on top of the review stack: payee or note, amount, account, date and
/// time, and category, on a glass card tinted by the drag direction.
struct ReviewCardView: View {
    let transaction: Transaction
    /// -1...1: negative leans to Check later (amber), positive to Looks good (green).
    var lean: Double = 0

    @Environment(ReferenceDataStore.self) private var referenceData

    var body: some View {
        let category = referenceData.category(id: transaction.categoryId)
        let account = referenceData.account(id: transaction.accountId)

        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                CategoryIcon(category: category, isTransfer: transaction.isTransfer)
                Spacer()
                if transaction.reviewDeferredAt != nil {
                    Label("Saved for later", systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title(category: category))
                    .font(.title2.weight(.semibold))
                    .lineLimit(3)
                AmountText(transaction: transaction, digits: referenceData.digits(for: transaction.currencyCode))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 10) {
                detail("Account", systemImage: "wallet.bifold", value: account?.name ?? String(localized: "Unknown account"))
                detail("Date", systemImage: "calendar", value: transaction.time.formatted(date: .abbreviated, time: .shortened))
                detail(
                    "Category",
                    systemImage: "tag",
                    value: category?.name ?? (transaction.isTransfer ? String(localized: "Transfer") : String(localized: "Uncategorized"))
                )
            }
        }
        .padding(8)
        .glassCardStyle(padding: 20, cornerRadius: 32, tint: tint)
        .overlay(alignment: .top) {
            stamp
        }
    }

    private var tint: Color? {
        guard lean != 0 else { return nil }
        let color: Color = lean > 0 ? .green : .orange
        return color.opacity(min(abs(lean), 1) * 0.45)
    }

    @ViewBuilder
    private var stamp: some View {
        if abs(lean) > 0.15 {
            Text(lean > 0 ? "Looks Good" : "Check Later")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(lean > 0 ? Color.green : Color.orange, in: .capsule)
                .opacity(min(abs(lean) * 1.5, 1))
                .offset(y: -14)
                .accessibilityHidden(true)
        }
    }

    private func title(category: Category?) -> String {
        if let payee = referenceData.payee(id: transaction.payeeId)?.name, !payee.isEmpty { return payee }
        if let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { return note }
        if let category { return category.name }
        return transaction.isTransfer ? String(localized: "Transfer") : String(localized: "Transaction")
    }

    private func detail(_ label: LocalizedStringKey, systemImage: String, value: String) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
        } label: {
            Label(label, systemImage: systemImage)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}
