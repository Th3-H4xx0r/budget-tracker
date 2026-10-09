import MoneyMatterKit
import SwiftUI

/// The Planned segment: the default salary profile and the list of planned (future) budgets,
/// matching the web's Planned Budgets page.
struct PlannedBudgetsSegmentView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var plans: LoadState<[PlannedBudgetPlan]> = .idle
    @State private var salary: PlannedBudgetSalarySettings?
    @State private var isCreating = false
    @State private var isEditingSalary = false

    var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("New Planned Budget", systemImage: "plus")
                    }
                    .disabled(plans.value == nil)
                }
            }
            .task {
                if plans.value == nil { await load() }
            }
            .refreshable { await load() }
            .sheet(isPresented: $isCreating) {
                PlannedBudgetCreateSheet(defaults: salary, currencyCode: currencyCode) { plan in
                    plans = .loaded([plan] + (plans.value ?? []))
                    Task { await load() }
                }
            }
            .sheet(isPresented: $isEditingSalary) {
                PlannedSalaryProfileSheet(settings: salary, currencyCode: currencyCode) { settings in
                    salary = settings
                }
            }
    }

    private var currencyCode: String {
        session.baseCurrency?.currencyCode ?? "USD"
    }

    @ViewBuilder
    private var content: some View {
        switch plans {
        case .idle, .loading:
            List {
                Section("Salary Profile") {
                    Text("Placeholder salary profile")
                }
                Section {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Placeholder plan name")
                            Text("Placeholder date range")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            List {
                InlineRetryView(ErrorMessage.inline(for: error)) { await load() }
            }
        case .loaded(let plans):
            List {
                salarySection
                if plans.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No Planned Budgets", systemImage: "calendar.badge.clock")
                        } description: {
                            Text("Create a plan for a pay period, trip, or any future date range.")
                        } actions: {
                            Button("New Planned Budget") { isCreating = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(plans) { plan in
                            NavigationLink {
                                PlannedBudgetDetailScreen(planID: plan.id) {
                                    Task { await load() }
                                }
                            } label: {
                                PlannedPlanRow(plan: plan, currencyCode: currencyCode, digits: referenceData.digits(for: currencyCode))
                            }
                        }
                    } header: {
                        Text("Plans")
                    } footer: {
                        Text("Model future income and spending without changing your real finances.")
                    }
                }
            }
        }
    }

    private var salarySection: some View {
        Section {
            Button {
                isEditingSalary = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Salary Profile")
                            .foregroundStyle(.primary)
                        if let salary, salary.salaryAmount > 0 {
                            HStack(spacing: 4) {
                                AmountText(salary.salaryAmount, currencyCode: currencyCode, digits: referenceData.digits(for: currencyCode))
                                Text(verbatim: "·")
                                Text(salary.salaryFrequency.plannedLabel)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("Not set")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .accessibilityHint(Text("Edits the default salary for new plans"))
        } footer: {
            Text("Used as the default for new plans. Existing plans remain unchanged until you apply the update.")
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        if plans.value == nil { plans = .loading }
        do {
            async let list = client.send(Endpoints.plannedBudgets())
            async let settings = client.send(Endpoints.plannedBudgetSalarySettings())
            let (loadedPlans, loadedSettings) = try await (list, settings)
            plans = .loaded(loadedPlans)
            salary = loadedSettings
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if plans.value == nil { plans = .failed(apiError) }
        }
    }
}

/// A plan card: name, salary projection, date range, and timeline status.
private struct PlannedPlanRow: View {
    let plan: PlannedBudgetPlan
    let currencyCode: String
    let digits: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        AmountText(plan.salaryAmount, currencyCode: currencyCode, digits: digits)
                        Text(verbatim: "·")
                        Text(plan.salaryFrequency.plannedLabel)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Label(plan.plannedDateRange, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if plan.isArchived {
                    Label("Archived", systemImage: "archivebox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    PlannedPlanTimelineBadge(timeline: PlannedPlanTimeline(start: plan.startDate, end: plan.endDate))
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(plan.isArchived ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}
