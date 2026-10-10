import MoneyMatterKit
import SwiftUI

/// The monthly budget under the hero: a slim progress bar with what's left, or a small
/// "Set a monthly budget" link when none is set. Both open the budget settings. The
/// over-budget banner sits separately, at the top of Home.
struct HomeBudgetLine: View {
    let model: MonthlyBudgetModel
    let openSettings: () -> Void

    var body: some View {
        if let snapshot = model.snapshot, snapshot.hasBudget {
            BudgetProgressLine(snapshot: snapshot, action: openSettings)
        } else if model.hasLoaded {
            Button("Set a monthly budget", action: openSettings)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .tint(DS.Palette.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "Over budget by $988" in bold on a 15 % red tint, the strongest signal on Home.
struct OverBudgetBanner: View {
    let snapshot: MonthlySpendingSnapshot
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private func money(_ amount: Decimal) -> String {
        MonthlyBudgetFormat.money(amount, currencyCode: snapshot.currencyCode)
    }

    var body: some View {
        let over = money(snapshot.overBy ?? 0)
        let spent = money(snapshot.spent)
        let budget = money(snapshot.budget ?? 0)
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2.weight(.bold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Over budget by \(over)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text("You've spent \(spent) of your \(budget) monthly budget")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .padding(.top, DS.Space.xs)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(DS.Palette.onTint(DS.Palette.danger, in: colorScheme))
            .padding(DS.cardPadding)
            .background(
                DS.Palette.danger.opacity(DS.tintFill),
                in: .rect(cornerRadius: DS.Radius.card, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the monthly budget settings")
    }
}

/// A 4 pt bar in the accent (red once over) over one `.footnote` line: "$1,051 left of
/// $4,000 · 22 days to go", or "Over by $988".
struct BudgetProgressLine: View {
    let snapshot: MonthlySpendingSnapshot
    let action: () -> Void

    private func money(_ amount: Decimal) -> String {
        MonthlyBudgetFormat.money(amount, currencyCode: snapshot.currencyCode)
    }

    private var tint: Color {
        snapshot.isOverBudget ? DS.Palette.danger : DS.Palette.accent
    }

    private var daysToGo: String {
        let today = Calendar.autoupdatingCurrent.component(.day, from: .now)
        let days = max(snapshot.month.dayCount() - today, 0)
        switch days {
        case 0: return String(localized: "last day")
        case 1: return String(localized: "1 day to go")
        default: return String(localized: "\(days) days to go")
        }
    }

    private var detail: String {
        if snapshot.isOverBudget {
            return String(localized: "Over by \(money(snapshot.overBy ?? 0))")
        }
        let left = String(localized: "\(money(snapshot.remaining ?? 0)) left of \(money(snapshot.budget ?? 0))")
        return "\(left) \u{00B7} \(daysToGo)"
    }

    var body: some View {
        let fraction = min(max(snapshot.fraction ?? 0, 0), 1)
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Capsule()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(tint)
                                .frame(width: geometry.size.width * fraction)
                        }
                    }
                    .accessibilityHidden(true)
                Text(verbatim: detail)
                    .font(.footnote.weight(snapshot.isOverBudget ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.isOverBudget ? DS.Palette.danger : Color(uiColor: .secondaryLabel))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the monthly budget settings")
    }
}
