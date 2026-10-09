import MoneyMatterKit
import SwiftUI

/// The Budgets segment of Planning: budget cards with income, expenses, net, and limit
/// utilization, matching the web Budgets page. Archived budgets show behind a toggle.
struct BudgetsSegmentView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session

    @State private var state: LoadState<[PlanningBudget]> = .idle
    @State private var stats: [String: PlanningBudgetStats] = [:]
    @State private var showsArchived = false
    @State private var isCreating = false
    @State private var editing: PlanningBudget?
    @State private var pendingDelete: PlanningBudget?
    @State private var alert: ErrorAlert?

    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }

    var body: some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Toggle(isOn: $showsArchived) {
                            Label("Show Archived", systemImage: "archivebox")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                    .accessibilityLabel(Text("Budget filters"))
                    Button {
                        isCreating = true
                    } label: {
                        Label("New Budget", systemImage: "plus")
                    }
                    .accessibilityLabel(Text("New Budget"))
                }
            }
            .task { if case .idle = state { await load() } }
            .onChange(of: showsArchived) { Task { await load() } }
            .sheet(isPresented: $isCreating) {
                BudgetFormSheet(budget: nil) { _ in Task { await load() } }
            }
            .sheet(item: $editing) { budget in
                BudgetFormSheet(budget: budget) { _ in Task { await load() } }
            }
            .confirmationDialog(
                "Delete Budget?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { budget in
                Button("Delete", role: .destructive) { Task { await delete(budget) } }
            } message: { budget in
                Text("“\(budget.name)” will be deleted. Its transactions stay in your accounts.")
            }
            .errorAlert($alert)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            list(Self.placeholders).redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let budgets):
            if budgets.isEmpty {
                ContentUnavailableView {
                    if showsArchived {
                        Label("No Budgets", systemImage: "chart.pie")
                    } else {
                        Label("No Active Budgets", systemImage: "chart.pie")
                    }
                } description: {
                    Text("Create a budget to track spending against a limit, by category or by hand-picked transactions.")
                } actions: {
                    Button("New Budget") { isCreating = true }
                        .dsProminentButton()
                }
            } else {
                list(budgets)
            }
        }
    }

    private func list(_ budgets: [PlanningBudget]) -> some View {
        List {
            Section {
                ForEach(budgets) { budget in
                    NavigationLink {
                        BudgetDetailScreen(budgetID: budget.id, initial: budget) {
                            await load()
                        }
                    } label: {
                        BudgetCardRow(budget: budget, stats: stats[budget.id], currencyCode: currencyCode)
                    }
                    .swipeActions(edge: .trailing) {
                        if budget.isOwner {
                            Button(role: .destructive) {
                                pendingDelete = budget
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        if budget.canManage {
                            Button {
                                Task { await setArchived(budget, !budget.isArchived) }
                            } label: {
                                if budget.isArchived {
                                    Label("Unarchive", systemImage: "archivebox.fill")
                                } else {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                            .tint(.indigo)
                        }
                    }
                    .contextMenu { menu(for: budget) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    @ViewBuilder private func menu(for budget: PlanningBudget) -> some View {
        if budget.canManage {
            Button {
                editing = budget
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                Task { await setArchived(budget, !budget.isArchived) }
            } label: {
                if budget.isArchived {
                    Label("Unarchive", systemImage: "archivebox.fill")
                } else {
                    Label("Archive", systemImage: "archivebox")
                }
            }
        }
        if budget.isOwner {
            Button(role: .destructive) {
                pendingDelete = budget
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Loading

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            let statuses: [PlanningBudgetStatus] = showsArchived ? [.active, .archived] : [.active]
            let budgets = try await client.send(Endpoints.planningBudgets(statuses: statuses))
            state = .loaded(budgets)
            await loadStats(for: budgets, client: client)
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(error) }
        }
    }

    private func loadStats(for budgets: [PlanningBudget], client: APIClient) async {
        await withTaskGroup(of: (String, PlanningBudgetStats?).self) { group in
            for budget in budgets {
                group.addTask {
                    (budget.id, try? await client.send(Endpoints.planningBudgetStats(id: budget.id)))
                }
            }
            for await (id, value) in group {
                if let value { stats[id] = value }
            }
        }
    }

    private func setArchived(_ budget: PlanningBudget, _ isArchived: Bool) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.setPlanningBudgetArchived(id: budget.id, isArchived: isArchived))
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func delete(_ budget: PlanningBudget) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.deletePlanningBudget(id: budget.id))
            stats[budget.id] = nil
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private static let placeholders: [PlanningBudget] = (0..<3).map { index in
        PlanningBudget(id: "placeholder-\(index)", name: "Budget name", limitAmount: 1000)
    }
}

/// One budget: an `EntityRow` with what was spent over what is left, and a thin
/// utilization bar under it when the budget has a limit.
private struct BudgetCardRow: View {
    let budget: PlanningBudget
    let stats: PlanningBudgetStats?
    let currencyCode: String

    private var timeStatus: BudgetTimeStatus? { BudgetTimeStatus(budget: budget) }
    private var spent: Decimal { BudgetFormatting.spent(stats) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            EntityRow(budget.name, subtitle: subtitle) {
                IconTile(systemImage: budget.type == .category ? "tag.fill" : "tray.full.fill")
            } trailing: {
                trailing.redactedWhileLoading(stats == nil)
            }
            if budget.limitAmount != nil {
                BudgetUtilizationBar(rate: stats?.utilizationRate ?? 0, showsLabel: false)
                    .padding(.leading, IconTileMetrics.size + DS.Space.m)
                    .redactedWhileLoading(stats == nil)
            }
        }
        .padding(.vertical, DS.Space.xxs)
        .opacity(budget.isArchived ? 0.6 : 1)
    }

    @ViewBuilder private var trailing: some View {
        let spentText = MoneyFormat.string(spent, currencyCode: currencyCode)
        if let limit = budget.limitAmount {
            let remaining = BudgetFormatting.remaining(spent: spent, limit: limit, currencyCode: currencyCode)
            EntityRowValue(spentText, detail: remaining.text, detailColor: remaining.color)
        } else {
            EntityRowValue(spentText, detail: String(localized: "No limit"))
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if budget.isArchived {
            parts.append(String(localized: "Archived"))
        } else if let timeStatus {
            parts.append(timeStatus.label)
        }
        let count = budget.categories.count
        if budget.type == .category, count > 0 {
            parts.append(String(localized: "\(count) categories"))
        } else if budget.type == .category {
            parts.append(String(localized: "Category budget"))
        } else {
            parts.append(String(localized: "Manual budget"))
        }
        return parts.joined(separator: " · ")
    }
}
