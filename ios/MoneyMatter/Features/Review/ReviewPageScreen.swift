import MoneyMatterKit
import SwiftUI

/// The review page (Unreviewed, Reviewed, Fraud), pushed from Home or Transactions with
/// `AppRouter.openReviewPage(_:)` or a `.reviewPage` route.
struct ReviewPageScreen: View {
    let initialStatus: ReviewListStatus

    @Environment(AppServices.self) private var services

    var body: some View {
        ReviewPageContent(model: ReviewPageViewModel(service: services.review, status: initialStatus))
    }
}

private struct ReviewPageContent: View {
    @State private var model: ReviewPageViewModel
    @Environment(AppRouter.self) private var router

    init(model: ReviewPageViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            switch model.currentList {
            case .idle, .loading:
                TransactionRowsPlaceholder(count: 6)
            case .failed(let error):
                ErrorRow(ErrorMessage.message(for: error)) {
                    await model.load(model.status)
                }
                .listRowInsets(EdgeInsets())
            case .loaded(let page):
                if page.rows.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(page.rows) { transaction in
                        row(transaction)
                    }
                    if page.hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            segmentPicker
        }
        .safeAreaInset(edge: .bottom) {
            if model.status == .unreviewed, (model.summary?.unreviewedCount ?? 0) > 0 {
                Button {
                    router.presentReviewStack(expectedTotal: model.summary?.unreviewedCount)
                } label: {
                    Label("Start Review", systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .dsProminentButton()
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.refresh()
        }
        .task {
            await model.loadIfNeeded()
        }
        .onChange(of: model.status) {
            Task { await model.loadIfNeeded() }
        }
        .onChange(of: router.reviewStack == nil) { _, isClosed in
            if isClosed { Task { await model.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewStatusesDidChange)) { notification in
            guard (notification.object as AnyObject?) !== model else { return }
            Task { await model.refresh() }
        }
        .errorAlert($model.alert)
    }

    private var segmentPicker: some View {
        Picker("Status", selection: $model.status) {
            ForEach(ReviewListStatus.allCases) { status in
                if let count = model.count(for: status) {
                    Text("\(Text(status.title)) (\(count))").tag(status)
                } else {
                    Text(status.title).tag(status)
                }
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func row(_ transaction: Transaction) -> some View {
        let actions = model.status.rowActions
        return Button {
            router.openTransaction(id: transaction.id)
        } label: {
            ResolvedTransactionRow(transaction: transaction, showsDate: true)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let action = actions.first {
                actionButton(action, for: transaction)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let action = actions.last {
                actionButton(action, for: transaction)
            }
        }
        .contextMenu {
            ForEach(actions) { action in
                actionButton(action, for: transaction)
            }
        }
        .accessibilityActions {
            ForEach(actions) { action in
                Button(action.title) {
                    Task { await model.perform(action.action, on: transaction) }
                }
            }
        }
        .task {
            await model.loadMoreIfNeeded(after: transaction)
        }
    }

    private func actionButton(_ action: ReviewRowAction, for transaction: Transaction) -> some View {
        Button {
            Task { await model.perform(action.action, on: transaction) }
        } label: {
            Label(action.title, systemImage: action.systemImage)
        }
        .tint(action.tint)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.status {
        case .unreviewed:
            ContentUnavailableView(
                "All Caught Up",
                systemImage: "checkmark.shield",
                description: Text("No transactions are waiting for review.")
            )
        case .reviewed:
            ContentUnavailableView(
                "No Reviewed Transactions",
                systemImage: "checkmark.circle",
                description: Text("Transactions you mark as looking good appear here.")
            )
        case .fraud:
            ContentUnavailableView(
                "No Fraud",
                systemImage: "exclamationmark.shield",
                description: Text("Transactions you mark as fraud appear here.")
            )
        }
    }
}
