import Charts
import MoneyMatterKit
import SwiftUI

// MARK: - Shared

/// The "Include planned" toggle every period widget offers in its header menu.
private struct HomeIncludePlannedMenu: View {
    let includePlanned: Bool
    let setIncludePlanned: (Bool) -> Void

    var body: some View {
        Menu {
            Toggle("Include Planned Transactions", isOn: Binding(get: { includePlanned }, set: setIncludePlanned))
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 32, minHeight: 32)
        }
        .accessibilityLabel("Widget Options")
    }
}

private struct HomeWidgetEmptyText: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}

private func homeMonthLabel(_ period: MonthPeriod) -> String {
    period.firstDay.startDate().formatted(.dateTime.month(.abbreviated))
}

// MARK: - Cash flow

struct HomeCashFlowCard: View {
    let state: LoadState<HomeCashFlowSnapshot>
    let currencyCode: String
    let digits: Int?
    let includePlanned: Bool
    let setIncludePlanned: (Bool) -> Void
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Cash Flow") {
                HomeIncludePlannedMenu(includePlanned: includePlanned, setIncludePlanned: setIncludePlanned)
            }
            switch state {
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error), retry: retry)
            case .loaded(let snapshot) where snapshot.months.allSatisfy({ $0.totals.income == 0 && $0.totals.expenses == 0 }):
                HomeWidgetEmptyText("No income or expenses in the last six months.")
            case .loaded(let snapshot):
                content(snapshot)
            case .idle, .loading:
                content(.placeholder)
                    .redactedWhileLoading(true)
            }
        }
        .cardStyle()
    }

    private func content(_ snapshot: HomeCashFlowSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                metric("Income", amount: snapshot.current.income, style: .income)
                Spacer()
                metric("Expenses", amount: snapshot.current.expenses, style: .expense)
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Net Flow")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AmountText(snapshot.current.netFlow, currencyCode: currencyCode, digits: digits, showsPlusSign: true)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(snapshot.current.netFlow >= 0 ? Color.green : Color.primary)
                    if let previous = snapshot.previous {
                        let change = snapshot.current.netFlow - previous.netFlow
                        HStack(spacing: 4) {
                            AmountText(change, currencyCode: currencyCode, digits: digits, showsPlusSign: true)
                            Text("vs. last month")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Savings Rate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(NSDecimalNumber(decimal: snapshot.current.savingsRate).intValue)%")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
            }
            chart(snapshot.months)
        }
    }

    private func metric(_ title: LocalizedStringKey, amount: Decimal, style: AmountStyle) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            AmountText(amount, currencyCode: currencyCode, digits: digits)
                .font(.headline)
                .foregroundStyle(style == .income ? Color.green : Color.primary)
        }
    }

    private func chart(_ months: [HomeCashFlowMonth]) -> some View {
        Chart {
            ForEach(months) { month in
                BarMark(
                    x: .value("Month", homeMonthLabel(month.period)),
                    y: .value("Amount", month.totals.income.doubleValue)
                )
                .foregroundStyle(by: .value("Type", String(localized: "Income")))
                .position(by: .value("Type", String(localized: "Income")))
                BarMark(
                    x: .value("Month", homeMonthLabel(month.period)),
                    y: .value("Amount", month.totals.expenses.doubleValue)
                )
                .foregroundStyle(by: .value("Type", String(localized: "Expenses")))
                .position(by: .value("Type", String(localized: "Expenses")))
            }
        }
        .chartForegroundStyleScale([String(localized: "Income"): Color.green, String(localized: "Expenses"): Color.red.opacity(0.75)])
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(MoneyFormat.compactString(Decimal(amount), currencyCode: currencyCode))
                    }
                }
            }
        }
        .chartLegend(position: .bottom)
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Income and expenses for the last six months")
        .accessibilityValue(months.map { month in
            "\(homeMonthLabel(month.period)): \(MoneyFormat.spokenString(month.totals.income, currencyCode: currencyCode)), \(MoneyFormat.spokenString(month.totals.expenses, currencyCode: currencyCode))"
        }.joined(separator: "; "))
    }
}

extension HomeCashFlowSnapshot {
    static let placeholder = HomeCashFlowSnapshot(
        report: CashFlowReport(periods: [], totals: .zero),
        period: MonthPeriod(containing: .now),
        monthCount: HomeDashboardModel.trendMonthCount
    )
}

// MARK: - Net worth

struct HomeNetWorthCard: View {
    let state: LoadState<[BalancePoint]>
    let period: MonthPeriod
    let includes: DashboardNetWorthIncludes
    let currencyCode: String
    let digits: Int?
    let setIncludes: (DashboardNetWorthIncludes) -> Void
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Net Worth") {
                Menu {
                    Toggle("Include Ventures", isOn: binding(\.ventures))
                    Toggle("Include Vehicles", isOn: binding(\.vehicles))
                    Toggle("Include Loans", isOn: binding(\.loans))
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: 32, minHeight: 32)
                }
                .accessibilityLabel("Net Worth Options")
            }
            switch state {
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error), retry: retry)
            case .loaded(let points) where points.isEmpty:
                HomeWidgetEmptyText("No balance history yet.")
            case .loaded(let points):
                content(DashboardNetWorthSummary(series: points, period: period, includes: includes))
            case .idle, .loading:
                content(DashboardNetWorthSummary(series: [], period: period, includes: includes))
                    .redactedWhileLoading(true)
            }
        }
        .cardStyle()
    }

    private func binding(_ keyPath: WritableKeyPath<DashboardNetWorthIncludes, Bool>) -> Binding<Bool> {
        Binding(
            get: { includes[keyPath: keyPath] },
            set: { newValue in
                var updated = includes
                updated[keyPath: keyPath] = newValue
                setIncludes(updated)
            }
        )
    }

    private func content(_ summary: DashboardNetWorthSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                AmountText(summary.endNetWorth ?? 0, currencyCode: currencyCode, digits: digits)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let delta = summary.currentDelta {
                    HStack(spacing: 4) {
                        AmountText(delta, currencyCode: currencyCode, digits: digits, showsPlusSign: true)
                        if let growth = summary.growthPercent {
                            Text(growth / 100, format: .percent.precision(.fractionLength(1)).sign(strategy: .always()))
                                .monospacedDigit()
                        }
                        Text("this month")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .foregroundStyle(delta >= 0 ? Color.green : Color.red)
                }
                if let previous = summary.previousDelta {
                    HStack(spacing: 4) {
                        Text("Last month")
                        AmountText(previous, currencyCode: currencyCode, digits: digits, showsPlusSign: true)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            chart(summary.bars)
        }
    }

    private func chart(_ bars: [DashboardNetWorthBar]) -> some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Month", homeMonthLabel(bar.period)),
                y: .value("Change", (bar.delta ?? 0).doubleValue)
            )
            .foregroundStyle((bar.delta ?? 0) >= 0 ? Color.green.opacity(bar.isCurrent ? 1 : 0.5) : Color.red.opacity(bar.isCurrent ? 1 : 0.5))
            .cornerRadius(3)
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(MoneyFormat.compactString(Decimal(amount), currencyCode: currencyCode))
                    }
                }
            }
        }
        .frame(height: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monthly net worth change")
        .accessibilityValue(bars.map { bar in
            "\(homeMonthLabel(bar.period)): \(bar.delta.map { MoneyFormat.spokenString($0, currencyCode: currencyCode) } ?? String(localized: "No data"))"
        }.joined(separator: "; "))
    }
}

// MARK: - Credit utilization

struct HomeCreditUtilizationCard: View {
    let accounts: [Account]
    let hasLoaded: Bool
    let includeCreditLimitInStats: Bool
    let currencyCode: String
    let digits: Int?

    private var lines: [DashboardCreditLine] {
        DashboardCreditLine.lines(accounts: accounts, includeCreditLimitInStats: includeCreditLimitInStats)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Credit Utilization")
            if !hasLoaded {
                content([DashboardCreditLine.placeholder])
                    .redactedWhileLoading(true)
            } else if lines.isEmpty {
                HomeWidgetEmptyText("No credit accounts with a limit.")
            } else {
                content(lines)
            }
        }
        .cardStyle()
    }

    private func content(_ lines: [DashboardCreditLine]) -> some View {
        let used = lines.reduce(Decimal.zero) { $0 + $1.refUsed }
        let limit = lines.reduce(Decimal.zero) { $0 + $1.refLimit }
        let total = DashboardCreditMath.utilization(used: used, limit: limit)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Double(total) / 100, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Self.color(for: total))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    AmountText(used, currencyCode: currencyCode, digits: digits)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 4) {
                        Text("of")
                        AmountText(limit, currencyCode: currencyCode, digits: digits)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(line.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(Double(line.utilization) / 100, format: .percent.precision(.fractionLength(0)))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Self.color(for: line.utilization))
                    }
                    ProgressView(value: Double(line.utilization), total: 100)
                        .tint(Self.color(for: line.utilization))
                    HStack(spacing: 4) {
                        AmountText(line.used, currencyCode: line.currencyCode)
                        Text("of")
                        AmountText(line.limit, currencyCode: line.currencyCode)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func color(for utilization: Int) -> Color {
        if utilization >= DashboardCreditMath.highThreshold { return .red }
        if utilization >= DashboardCreditMath.mediumThreshold { return .orange }
        return .green
    }
}

extension DashboardCreditLine {
    static let placeholder = DashboardCreditLine(
        id: "placeholder", name: "Credit Card", currencyCode: "USD",
        used: 500, limit: 2000, utilization: 25, refUsed: 500, refLimit: 2000
    )
}

// MARK: - Planned overview

struct HomePlannedOverviewCard: View {
    let state: LoadState<HomePlannedOverview>
    let accounts: [Account]
    let includeCreditLimitInStats: Bool
    let currencyCode: String
    let digits: Int?
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Planned Overview")
            switch state {
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error), retry: retry)
            case .loaded(let overview):
                let scoped = DashboardPlannedAggregate.projectedAccounts(accounts)
                let aggregate = DashboardPlannedAggregate(entries: overview.entries, accountIDs: scoped.map(\.id))
                if aggregate.count == 0 {
                    HomeWidgetEmptyText("No planned transactions.")
                } else {
                    content(aggregate: aggregate, realTotal: realTotal(scoped), plans: overview.plans)
                }
            case .idle, .loading:
                content(
                    aggregate: DashboardPlannedAggregate(entries: [], accountIDs: []),
                    realTotal: 1000,
                    plans: []
                )
                .redactedWhileLoading(true)
            }
        }
        .cardStyle()
    }

    /// The base-currency balance of the scoped accounts; with the credit-limit setting on, a
    /// card's limit isn't counted as the user's money.
    private func realTotal(_ accounts: [Account]) -> Decimal {
        accounts.reduce(Decimal.zero) { total, account in
            let adjustment = includeCreditLimitInStats && account.creditLimit > 0 ? account.refCreditLimit : 0
            return total + account.refCurrentBalance - adjustment
        }
    }

    private func content(aggregate: DashboardPlannedAggregate, realTotal: Decimal, plans: [Transaction]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Projected Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AmountText(realTotal + aggregate.refPlannedDelta, currencyCode: currencyCode, digits: digits)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    AmountText(aggregate.refPlannedDelta, currencyCode: currencyCode, digits: digits, showsPlusSign: true)
                        .foregroundStyle(aggregate.refPlannedDelta < 0 ? Color.primary : Color.green)
                    Text("from \(aggregate.count) planned")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                if let latest = aggregate.latestTime {
                    Text("Through \(latest.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(Array(plans.enumerated()), id: \.element.id) { index, transaction in
                if index > 0 {
                    Divider()
                        .padding(.leading, 48)
                }
                NavigationLink(value: HomeRoute.transaction(id: transaction.id)) {
                    ResolvedTransactionRow(transaction: transaction, showsDate: true)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Category spending tracker

struct HomeCategoryTrackerCard: View {
    static let maxCategories = 16

    let state: LoadState<[CategorySpendingByType]>
    let selectedIDs: [String]
    let currencyCode: String
    let digits: Int?
    let includePlanned: Bool
    let setIncludePlanned: (Bool) -> Void
    let saveSelection: ([String]) async -> Void
    let retry: () async -> Void

    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Category Tracker") {
                HStack(spacing: 4) {
                    Button(selectedIDs.isEmpty ? "Add" : "Edit") { isEditing = true }
                        .font(.subheadline)
                    HomeIncludePlannedMenu(includePlanned: includePlanned, setIncludePlanned: setIncludePlanned)
                }
            }
            if selectedIDs.isEmpty {
                VStack(spacing: 8) {
                    HomeWidgetEmptyText("Pick categories to track their spending this month.")
                    Button("Add Categories", systemImage: "plus") { isEditing = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
            } else {
                switch state {
                case .failed(let error):
                    InlineRetryView(ErrorMessage.message(for: error), retry: retry)
                case .loaded(let items):
                    rows(items)
                case .idle, .loading:
                    rows([])
                        .redactedWhileLoading(true)
                }
            }
        }
        .cardStyle()
        .sheet(isPresented: $isEditing) {
            HomeCategoryTrackerEditor(initialIDs: selectedIDs, save: saveSelection)
        }
    }

    private func rows(_ items: [CategorySpendingByType]) -> some View {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return VStack(spacing: 8) {
            ForEach(selectedIDs, id: \.self) { id in
                let category = referenceData.category(id: id)
                let bucket = byID[id]
                let net = (bucket?.income ?? 0) - (bucket?.expense ?? 0)
                HStack(spacing: 10) {
                    CategoryIcon(category: category, size: 28)
                    Text(category?.name ?? bucket?.name ?? String(localized: "Unknown"))
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    AmountText(abs(net), currencyCode: currencyCode, digits: digits, style: net > 0 ? .income : (net < 0 ? .expense : .neutral))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(net > 0 ? Color.green : (net < 0 ? Color.primary : Color.secondary))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Picks and orders the tracked categories.
private struct HomeCategoryTrackerEditor: View {
    let save: ([String]) async -> Void

    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String]
    @State private var search = ""
    @State private var isSaving = false

    init(initialIDs: [String], save: @escaping ([String]) async -> Void) {
        self.save = save
        _selected = State(initialValue: initialIDs)
    }

    private var available: [MoneyMatterKit.Category] {
        referenceData.categories
            .filter { !selected.contains($0.id) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if selected.isEmpty {
                        Text("No categories yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(selected, id: \.self) { id in
                        Label {
                            Text(referenceData.category(id: id)?.name ?? String(localized: "Unknown"))
                        } icon: {
                            CategoryIcon(category: referenceData.category(id: id), size: 28)
                        }
                    }
                    .onMove { selected.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { selected.remove(atOffsets: $0) }
                } header: {
                    Text("Tracked")
                } footer: {
                    Text("Up to \(HomeCategoryTrackerCard.maxCategories) categories.")
                }

                Section("Add") {
                    ForEach(available) { category in
                        Button {
                            selected.append(category.id)
                        } label: {
                            Label {
                                Text(category.name)
                                    .foregroundStyle(.primary)
                            } icon: {
                                CategoryIcon(category: category, size: 28)
                            }
                        }
                        .disabled(selected.count >= HomeCategoryTrackerCard.maxCategories)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .searchable(text: $search, prompt: Text("Search Categories"))
            .navigationTitle("Tracked Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            await save(selected)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}
