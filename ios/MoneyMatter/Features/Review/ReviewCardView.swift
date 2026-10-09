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

        VStack(alignment: .leading, spacing: DS.Space.xl) {
            HStack(alignment: .top) {
                CategoryIconTile(category: category, isTransfer: transaction.isTransfer, size: 44)
                Spacer()
                if transaction.reviewDeferredAt != nil {
                    StatusBadge(label: String(localized: "Saved for later"), color: DS.Palette.warning)
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(title(category: category))
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                AmountText(transaction: transaction, digits: referenceData.digits(for: transaction.currencyCode))
                    .dsValueHero()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            StatGrid(columns: 2) {
                StatCell(label: String(localized: "Account"), value: account?.name ?? String(localized: "Unknown account"))
                StatCell(
                    label: String(localized: "Category"),
                    value: category?.name ?? (transaction.isTransfer ? String(localized: "Transfer") : String(localized: "Uncategorized"))
                )
                StatCell(label: String(localized: "Date"), value: transaction.time.formatted(date: .abbreviated, time: .omitted))
                StatCell(label: String(localized: "Time"), value: transaction.time.formatted(date: .omitted, time: .shortened))
            }
        }
        .glassCardStyle(padding: DS.Space.xl, cornerRadius: DS.Radius.card, tint: tint)
        .overlay(alignment: .top) {
            stamp
        }
    }

    private var tint: Color? {
        guard lean != 0 else { return nil }
        let color: Color = lean > 0 ? DS.Palette.up : DS.Palette.warning
        return color.opacity(min(abs(lean), 1) * 0.45)
    }

    @ViewBuilder
    private var stamp: some View {
        if abs(lean) > 0.15 {
            StatusBadge(
                label: lean > 0 ? String(localized: "Looks Good") : String(localized: "Check Later"),
                color: lean > 0 ? DS.Palette.up : DS.Palette.warning
            )
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
}
