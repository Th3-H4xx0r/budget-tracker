import Foundation
import MoneyMatterKit
import SwiftUI

extension Notification.Name {
    /// Posted after review statuses change (a review page action, or the stack's writes
    /// settling), so Home and the review page can reload their counts.
    static let reviewStatusesDidChange = Notification.Name("MoneyMatter.reviewStatusesDidChange")
}

/// Entry points into the review feature, usable from any tab.
extension AppRouter {
    /// Pushes the review page on the selected tab's stack. Accounts has no review route, so
    /// it switches to Transactions first.
    func openReviewPage(_ status: ReviewListStatus = .unreviewed) {
        switch selectedTab {
        case .home:
            homePath.append(.reviewPage(status))
        case .transactions:
            transactionsPath.append(.reviewPage(status))
        case .accounts:
            selectedTab = .transactions
            transactionsPath.append(.reviewPage(status))
        }
    }

    /// Pushes a transaction's detail on the selected tab's stack.
    func openTransaction(id: String) {
        switch selectedTab {
        case .home: homePath.append(.transaction(id: id))
        case .accounts: accountsPath.append(.transaction(id: id))
        case .transactions: transactionsPath.append(.transaction(id: id))
        }
    }
}

/// A toolbar button that opens the review page, badged with the unreviewed count. Drop it
/// into a tab's toolbar, e.g. Transactions.
struct ReviewToolbarButton: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @State private var unreviewedCount = 0

    var body: some View {
        Button {
            router.openReviewPage(.unreviewed)
        } label: {
            Image(systemName: "checkmark.shield")
                .overlay(alignment: .topTrailing) {
                    if unreviewedCount > 0 {
                        Text(verbatim: unreviewedCount > 99 ? "99+" : "\(unreviewedCount)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(.red, in: .capsule)
                            .offset(x: 10, y: -8)
                    }
                }
        }
        .accessibilityLabel("Review")
        .accessibilityValue(unreviewedCount > 0 ? Text("\(unreviewedCount) to review") : Text(verbatim: ""))
        .task { await loadCount() }
        .onReceive(NotificationCenter.default.publisher(for: .reviewStatusesDidChange)) { _ in
            Task { await loadCount() }
        }
    }

    private func loadCount() async {
        if let summary = try? await services.review.reviewSummary() {
            unreviewedCount = summary.unreviewedCount
        }
    }
}
