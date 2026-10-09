import MoneyMatterKit
import SwiftUI

/// The signed-in shell: five tabs (symbols drawn filled), the review and quick-add
/// accessory above the tab bar, the Settings sheet, the new-transaction sheet, and the
/// review stack cover. Each tab's root view lives in `Features/<Tab>/` and owns its
/// `NavigationStack`.
struct MainTabView: View {
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(AppServices.self) private var services
    @State private var router = AppRouter()
    @State private var unreviewedCount = 0
    @State private var isAddingTransaction = false

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeTab()
            }
            Tab("Accounts", systemImage: "wallet.bifold.fill", value: AppTab.accounts) {
                AccountsTab()
            }
            Tab("Transactions", systemImage: "list.bullet.rectangle.portrait.fill", value: AppTab.transactions) {
                TransactionsTab()
            }
            Tab("Planning", systemImage: "calendar.badge.clock", value: AppTab.planning) {
                PlanningTab()
            }
            Tab("Insights", systemImage: "chart.xyaxis.line", value: AppTab.insights) {
                InsightsTab()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            ReviewAccessoryView(
                unreviewedCount: unreviewedCount,
                onReview: { router.presentReviewStack(expectedTotal: unreviewedCount) },
                onAdd: { isAddingTransaction = true }
            )
        }
        .sheet(isPresented: $isAddingTransaction) {
            TransactionEditorSheet(mode: .create(accountId: nil))
        }
        .sheet(isPresented: $router.isSettingsPresented) {
            SettingsView()
        }
        .fullScreenCover(item: $router.reviewStack) { request in
            ReviewStackScreen(request: request)
        }
        .shareInvitationLinks()
        .task {
            #if DEBUG
            DebugLaunch.applyInitialScreen(to: router)
            #endif
            await referenceData.loadIfNeeded()
        }
        .task { await loadUnreviewedCount() }
        .onReceive(NotificationCenter.default.publisher(for: .reviewStatusesDidChange)) { _ in
            Task { await loadUnreviewedCount() }
        }
        .onChange(of: router.reviewStack == nil) { _, isClosed in
            if isClosed { Task { await loadUnreviewedCount() } }
        }
        // Last, so the sheet and cover content can read the router too.
        .environment(router)
    }

    private func loadUnreviewedCount() async {
        if let summary = try? await services.review.reviewSummary() {
            unreviewedCount = summary.unreviewedCount
        }
    }
}

/// The tab bar's bottom accessory, a glass capsule the system draws above the tabs.
///
/// - With transactions to review: a shield, "N to review" with the count in the accent
///   (opens the review stack), and a `+` that opens the new-transaction editor.
/// - With an empty queue: only "Add transaction" with a `+`, opening the editor.
struct ReviewAccessoryView: View {
    let unreviewedCount: Int
    let onReview: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s) {
            if unreviewedCount > 0 {
                Button(action: onReview) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(reviewTitle)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(unreviewedCount) to review"))
                .accessibilityHint("Opens the review stack")
            } else {
                Button(action: onAdd) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Add transaction")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            if unreviewedCount > 0 {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 36, height: 36)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add transaction")
            }
        }
        .padding(.leading, DS.Space.l)
        .padding(.trailing, DS.Space.s)
    }

    /// "8 to review", with the count drawn in the accent.
    private var reviewTitle: AttributedString {
        var title = AttributedString(localized: "\(unreviewedCount) to review")
        let count = unreviewedCount.formatted()
        if let range = title.range(of: count) {
            title[range].foregroundColor = DS.Palette.accent
        }
        return title
    }
}

#Preview("Accessory") {
    TabView {
        Tab("Home", systemImage: "house.fill") {
            NavigationStack {
                List { Text(verbatim: "Content scrolls under the tab bar.") }
                    .navigationTitle("Home")
            }
        }
        Tab("Accounts", systemImage: "wallet.bifold.fill") { Text(verbatim: "Accounts") }
    }
    .tabViewBottomAccessory {
        ReviewAccessoryView(unreviewedCount: 8, onReview: {}, onAdd: {})
    }
}
