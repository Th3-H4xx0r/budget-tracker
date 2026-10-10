import MoneyMatterKit
import SwiftUI

/// The top of Home for the monthly budget: a big red banner when over budget, then a
/// compact spent-of-budget row with a thin progress bar. Without a budget, a subtle
/// "Set a monthly budget" row. Every part opens the budget settings.
struct HomeBudgetSection: View {
    let model: MonthlyBudgetModel
    let openSettings: () -> Void

    var body: some View {
        if let snapshot = model.snapshot, snapshot.hasBudget {
            if snapshot.isOverBudget {
                OverBudgetBanner(snapshot: snapshot, action: openSettings)
            }
            BudgetProgressRow(snapshot: snapshot, action: openSettings)
        } else if model.hasLoaded {
            InlineActionRow(String(localized: "Set a monthly budget"), systemImage: "gauge.with.dots.needle.67percent", action: openSettings)
                .padding(.vertical, DS.Space.m)
                .padding(.horizontal, DS.Space.l)
                .background(DS.Surface.panel, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
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

/// "Monthly budget · $320 of $400" over a thin bar in the accent, red once over budget.
struct BudgetProgressRow: View {
    let snapshot: MonthlySpendingSnapshot
    let action: () -> Void

    private func money(_ amount: Decimal) -> String {
        MonthlyBudgetFormat.money(amount, currencyCode: snapshot.currencyCode)
    }

    private var tint: Color {
        snapshot.isOverBudget ? DS.Palette.danger : DS.Palette.accent
    }

    private var detail: String {
        if snapshot.isOverBudget {
            String(localized: "\(money(snapshot.overBy ?? 0)) over")
        } else {
            String(localized: "\(money(snapshot.remaining ?? 0)) left")
        }
    }

    var body: some View {
        let spent = money(snapshot.spent)
        let budget = money(snapshot.budget ?? 0)
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    Text("Monthly budget")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("\(spent) of \(budget)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                ProgressView(value: min(max(snapshot.fraction ?? 0, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .accessibilityHidden(true)
                Text(verbatim: detail)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.isOverBudget ? AnyShapeStyle(DS.Palette.danger) : AnyShapeStyle(.secondary))
            }
            .padding(.vertical, DS.Space.m)
            .padding(.horizontal, DS.Space.l)
            .background(DS.Surface.panel, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the monthly budget settings")
    }
}
