import SwiftUI

/// Root of the Planning tab: owns the tab's `NavigationStack`. Planning pushes its own route
/// types onto `router.planningPath`; `TransactionsRoute` is registered so
/// `AppRouter.openTransaction(id:)` and `openReviewPage(_:)` push in place.
struct PlanningTab: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.planningPath) {
            PlanningScreen()
                .navigationDestination(for: TransactionsRoute.self) { route in
                    TransactionsRouteDestination(route: route)
                }
        }
    }
}

/// The three planning surfaces, matching the web's Budgets page and the Planned page's tabs.
enum PlanningSegment: String, CaseIterable, Identifiable {
    case budgets
    case planned
    case recurring

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .budgets: "Budgets"
        case .planned: "Planned"
        case .recurring: "Recurring"
        }
    }
}

struct PlanningScreen: View {
    @SceneStorage("planning.segment") private var segment: PlanningSegment = .budgets

    var body: some View {
        Group {
            switch segment {
            case .budgets: BudgetsSegmentView()
            case .planned: PlannedBudgetsSegmentView()
            case .recurring: RecurringPaymentsSegmentView()
            }
        }
        .navigationTitle("Planning")
        .safeAreaBar(edge: .top) {
            Picker("Section", selection: $segment) {
                ForEach(PlanningSegment.allCases) { segment in
                    Text(segment.title).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}
