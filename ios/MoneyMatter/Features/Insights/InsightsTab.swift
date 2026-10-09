import SwiftUI

/// Root of the Insights tab: owns the tab's `NavigationStack`. Insights pushes its own route
/// types onto `router.insightsPath`; `TransactionsRoute` is registered so
/// `AppRouter.openTransaction(id:)` and `openReviewPage(_:)` push in place.
struct InsightsTab: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.insightsPath) {
            InsightsScreen()
                .navigationDestination(for: TransactionsRoute.self) { route in
                    TransactionsRouteDestination(route: route)
                }
        }
    }
}

/// The analytics reports, each drilling into its own Swift Charts screen.
struct InsightsScreen: View {
    var body: some View {
        List {
            Section("Spending") {
                link("Trends", subtitle: "Compare months and years, cumulatively or by category.", symbol: "chart.bar.xaxis") {
                    InsightsTrendsScreen()
                }
                link("Cash Flow", subtitle: "Income versus expenses and where the money went.", symbol: "arrow.left.arrow.right") {
                    InsightsCashFlowScreen()
                }
                link("Pivot Report", subtitle: "Categories, payees, or tags across time periods.", symbol: "tablecells") {
                    InsightsPivotScreen()
                }
            }
            Section("Net Worth") {
                link("Net Worth History", subtitle: "How your net worth changed over time.", symbol: "chart.line.uptrend.xyaxis") {
                    InsightsNetWorthHistoryScreen()
                }
                link("Net Worth Drivers", subtitle: "Savings versus investment returns, and your target.", symbol: "chart.bar.doc.horizontal") {
                    InsightsNetWorthDriversScreen()
                }
            }
            Section("Investing") {
                link("Investment Contributions", subtitle: "Money you put into your portfolios.", symbol: "tray.and.arrow.down") {
                    InsightsContributionsScreen()
                }
                link("Investment Calculator", subtitle: "Project how your savings could grow.", symbol: "function") {
                    InsightsCalculatorScreen()
                }
            }
        }
        .navigationTitle("Insights")
    }

    private func link<Destination: View>(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        symbol: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
            }
        }
    }
}
