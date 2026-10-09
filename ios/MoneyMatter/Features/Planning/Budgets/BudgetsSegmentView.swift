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
                        Label("Filter", systemImage: "line.3.horizontal.decrease")
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
                        .buttonStyle(.borderedProminent)
                }
            } else {
                list(budgets)
            }
        }
    }

    private func list(_ budgets: [PlanningBudget]) -> some View {
        List {
            ForEach(budgets) { budget in
                Section {
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
        .listSectionSpacing(.compact)
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

/// One budget card: status, name, limit, categories, dates, totals, and utilization.
private struct BudgetCardRow: View {
    let budget: PlanningBudget
    let stats: PlanningBudgetStats?
    let currencyCode: String

    private var timeStatus: BudgetTimeStatus? { BudgetTimeStatus(budget: budget) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusLabel
            HStack(spacing: 12) {
                Image(systemName: budget.type == .category ? "tag" : "tray.full")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: .rect(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(budget.name)
                        .font(.headline)
                        .lineLimit(2)
                    subtitle
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if budget.type == .category, !budget.categories.isEmpty {
                categoryChips
            }
            if let range = BudgetFormatting.dateRange(start: budget.startDate, end: budget.endDate) {
                Label { range } icon: { Image(systemName: "calendar") }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if budget.type == .category {
                Text("Auto-tracked from categories")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
            Divider()
            BudgetStatTriplet(stats: stats, currencyCode: currencyCode)
            if budget.limitAmount != nil {
                BudgetUtilizationBar(rate: stats?.utilizationRate ?? 0)
                    .redactedWhileLoading(stats == nil)
            }
        }
        .padding(.vertical, 4)
        .opacity(budget.isArchived ? 0.6 : 1)
    }

    @ViewBuilder private var statusLabel: some View {
        if budget.isArchived {
            Label("Archived", systemImage: "archivebox")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        } else if let timeStatus {
            timeStatus.text
                .font(.caption.weight(.medium))
                .foregroundStyle(timeStatus.tint)
        } else {
            Text("No time period")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var subtitle: some View {
        let count = budget.categories.count
        if let limit = budget.limitAmount {
            if budget.type == .category, count > 0 {
                Text("Limit \(MoneyFormat.string(limit, currencyCode: currencyCode)) · \(count) categories")
                    .monospacedDigit()
            } else {
                Text("Limit \(MoneyFormat.string(limit, currencyCode: currencyCode))")
                    .monospacedDigit()
            }
        } else if budget.type == .category, count > 0 {
            Text("\(count) categories")
        } else {
            BudgetFormatting.typeLabel(budget.type)
        }
    }

    private var categoryChips: some View {
        HStack(spacing: 6) {
            ForEach(budget.categories.prefix(3)) { category in
                let color = Color(hex: category.color) ?? .secondary
                Text(category.name)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(color)
                    .background(color.opacity(0.15), in: .capsule)
            }
            if budget.categories.count > 3 {
                Text("+\(budget.categories.count - 3)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: .capsule)
            }
        }
    }
}
