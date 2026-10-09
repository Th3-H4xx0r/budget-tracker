import MoneyMatterKit
import SwiftUI

extension DashboardWidgetKind {
    var homeTitle: LocalizedStringKey {
        switch self {
        case .balanceTrend: "Balance"
        case .spendingCategories: "Spending by Category"
        case .latestRecords: "Latest Transactions"
        case .categorySpendingTracker: "Category Tracker"
        case .cashFlow: "Cash Flow"
        case .netWorth: "Net Worth"
        case .creditUtilization: "Credit Utilization"
        case .plannedOverview: "Planned Overview"
        case .subscriptionsOverview: "Upcoming Payments"
        }
    }

    var homeSubtitle: LocalizedStringKey {
        switch self {
        case .balanceTrend: "Your total balance over the month."
        case .spendingCategories: "Where your money went this month."
        case .latestRecords: "Your most recent transactions."
        case .categorySpendingTracker: "Spending in the categories you pick."
        case .cashFlow: "Income versus expenses and your savings rate."
        case .netWorth: "Net worth and how it changed each month."
        case .creditUtilization: "How much of your credit lines you use."
        case .plannedOverview: "Your balance after pending planned transactions."
        case .subscriptionsOverview: "Payments that are overdue or due soon."
        }
    }

    var homeSymbol: String {
        switch self {
        case .balanceTrend: "chart.xyaxis.line"
        case .spendingCategories: "chart.pie"
        case .latestRecords: "list.bullet.rectangle"
        case .categorySpendingTracker: "square.grid.3x2"
        case .cashFlow: "arrow.left.arrow.right"
        case .netWorth: "building.columns"
        case .creditUtilization: "creditcard"
        case .plannedOverview: "calendar.badge.clock"
        case .subscriptionsOverview: "repeat"
        }
    }
}

/// Reorders, shows, and hides Home's widgets. Saving replaces `dashboard.widgets`; hidden
/// widgets lose their config, as on the web dashboard.
struct HomeEditSheet: View {
    let initialWidgets: [DashboardWidgetConfig]
    let save: ([DashboardWidgetConfig]) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var widgets: [DashboardWidgetConfig]
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    init(initialWidgets: [DashboardWidgetConfig], save: @escaping ([DashboardWidgetConfig]) async throws -> Void) {
        self.initialWidgets = initialWidgets
        self.save = save
        _widgets = State(initialValue: initialWidgets)
    }

    private var hidden: [DashboardWidgetKind] { DashboardLayout.hiddenKinds(in: widgets) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if widgets.isEmpty {
                        Text("Add a widget below to fill your Home.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(widgets) { widget in
                        if let kind = widget.kind {
                            row(kind)
                        }
                    }
                    .onMove { widgets.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { widgets.remove(atOffsets: $0) }
                } header: {
                    Text("Shown")
                } footer: {
                    Text("Drag to reorder. Remove a widget to hide it.")
                }

                if !hidden.isEmpty {
                    Section("More Widgets") {
                        ForEach(hidden) { kind in
                            Button {
                                withAnimation { widgets.append(DashboardWidgetConfig(kind: kind)) }
                            } label: {
                                HStack {
                                    row(kind)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                        .imageScale(.large)
                                        .accessibilityHidden(true)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Adds the widget to Home")
                        }
                    }
                }

                Section {
                    Button("Restore Default Layout") {
                        withAnimation { widgets = DashboardLayout.defaultWidgets }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Done") { Task { await commit() } }
                            .disabled(widgets == initialWidgets)
                    }
                }
            }
            .interactiveDismissDisabled(widgets != initialWidgets)
            .errorAlert($alert)
        }
    }

    private func row(_ kind: DashboardWidgetKind) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.homeTitle)
                Text(kind.homeSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: kind.homeSymbol)
                .foregroundStyle(.tint)
        }
    }

    private func commit() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await save(widgets)
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
