import Foundation
import MoneyMatterKit
import Observation
import SwiftUI

/// One loaded segment of the review page.
struct ReviewListPage: Equatable {
    var rows: [Transaction]
    var hasMore: Bool
    /// Where the next page starts on the server. Rows removed optimistically still count
    /// until their write lands, so this is not `rows.count`.
    var nextOffset: Int
}

/// A row action on the review page, following the web review table.
struct ReviewRowAction: Identifiable {
    let title: LocalizedStringKey
    let systemImage: String
    let action: ReviewAction
    let tint: Color

    var id: ReviewAction { action }
}

extension ReviewListStatus {
    var title: LocalizedStringKey {
        switch self {
        case .unreviewed: "Unreviewed"
        case .reviewed: "Reviewed"
        case .fraud: "Fraud"
        }
    }

    /// The first action is the leading swipe, the second the trailing swipe.
    var rowActions: [ReviewRowAction] {
        switch self {
        case .unreviewed:
            [
                ReviewRowAction(title: "Looks Good", systemImage: "checkmark", action: .reviewed, tint: .green),
                ReviewRowAction(title: "Fraud", systemImage: "exclamationmark.shield", action: .fraud, tint: .red),
            ]
        case .reviewed:
            [
                ReviewRowAction(title: "Move to Unreviewed", systemImage: "arrow.uturn.backward", action: .unreviewed, tint: .orange),
                ReviewRowAction(title: "Mark as Fraud", systemImage: "exclamationmark.shield", action: .fraud, tint: .red),
            ]
        case .fraud:
            [
                ReviewRowAction(title: "Not Fraud", systemImage: "checkmark.shield", action: .reviewed, tint: .green),
                ReviewRowAction(title: "Move to Unreviewed", systemImage: "arrow.uturn.backward", action: .unreviewed, tint: .orange),
            ]
        }
    }
}

/// The review page: three segments of transactions, their counts, and row actions.
@Observable
final class ReviewPageViewModel {
    static let pageSize = 50

    var status: ReviewListStatus
    private(set) var summary: ReviewSummary?
    private(set) var lists: [ReviewListStatus: LoadState<ReviewListPage>] = [:]
    private(set) var isLoadingMore = false
    var alert: ErrorAlert?

    @ObservationIgnored private let service: any ReviewServicing
    /// Rows acted on from each segment. Loads that were in flight during the action may
    /// still return them, so they are filtered out.
    @ObservationIgnored private var removedIDs: [ReviewListStatus: Set<String>] = [:]

    init(service: any ReviewServicing, status: ReviewListStatus) {
        self.service = service
        self.status = status
    }

    var currentList: LoadState<ReviewListPage> { lists[status] ?? .idle }

    func count(for status: ReviewListStatus) -> Int? {
        switch status {
        case .unreviewed: summary?.unreviewedCount
        case .fraud: summary?.fraudCount
        case .reviewed:
            // The summary has no reviewed count; show it once the whole list is loaded.
            if case .loaded(let page) = lists[.reviewed], !page.hasMore { page.rows.count } else { nil }
        }
    }

    // MARK: Loading

    func loadIfNeeded() async {
        if summary == nil { await loadSummary() }
        if case .loaded = currentList { return }
        if currentList.isLoading { return }
        await load(status)
    }

    /// Reloads the summary and the visible segment; other segments reload when shown.
    func refresh() async {
        let visible = status
        lists = lists.filter { $0.key == visible }
        async let summaryLoad: Void = loadSummary()
        async let listLoad: Void = load(visible)
        _ = await (summaryLoad, listLoad)
    }

    func loadSummary() async {
        do {
            summary = try await service.reviewSummary()
        } catch {
            // The counts are decoration; the segments still work without them.
        }
    }

    func load(_ status: ReviewListStatus) async {
        if lists[status]?.value == nil { lists[status] = .loading }
        do {
            let rows = try await service.reviewTransactions(status: status, limit: Self.pageSize, offset: 0)
            let removed = removedIDs[status] ?? []
            lists[status] = .loaded(ReviewListPage(
                rows: rows.filter { !removed.contains($0.id) },
                hasMore: rows.count == Self.pageSize,
                nextOffset: rows.count
            ))
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if lists[status]?.value == nil {
                lists[status] = .failed(apiError)
            } else {
                alert = ErrorAlert(apiError)
            }
        }
    }

    func loadMoreIfNeeded(after transaction: Transaction) async {
        let status = status
        guard case .loaded(let page) = lists[status], page.hasMore, !isLoadingMore,
              page.rows.last?.id == transaction.id
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await service.reviewTransactions(status: status, limit: Self.pageSize, offset: page.nextOffset)
            guard case .loaded(var current) = lists[status] else { return }
            let skipped = Set(current.rows.map(\.id)).union(removedIDs[status] ?? [])
            current.rows.append(contentsOf: next.filter { !skipped.contains($0.id) })
            current.hasMore = next.count == Self.pageSize
            current.nextOffset += next.count
            lists[status] = .loaded(current)
        } catch {
            alert = ErrorAlert(error)
        }
    }

    // MARK: Actions

    /// Removes the row optimistically and writes the action; a failed write puts it back.
    func perform(_ action: ReviewAction, on transaction: Transaction) async {
        let status = status
        guard case .loaded(var page) = lists[status],
              let index = page.rows.firstIndex(where: { $0.id == transaction.id })
        else { return }
        removedIDs[status, default: []].insert(transaction.id)
        // The row may land in another segment, where an earlier removal no longer applies.
        for other in ReviewListStatus.allCases where other != status {
            removedIDs[other]?.remove(transaction.id)
        }
        withAnimation {
            page.rows.remove(at: index)
            lists[status] = .loaded(page)
        }

        do {
            _ = try await service.updateReviewStatus(transactionIds: [transaction.id], action: action)
            // The row left this segment on the server, so later pages start one earlier.
            if case .loaded(var current) = lists[status] {
                current.nextOffset = max(0, current.nextOffset - 1)
                lists[status] = .loaded(current)
            }
            // The row moved to another segment, so those lists are stale.
            lists = lists.filter { $0.key == status }
            await loadSummary()
            NotificationCenter.default.post(name: .reviewStatusesDidChange, object: self)
        } catch {
            removedIDs[status]?.remove(transaction.id)
            if case .loaded(var current) = lists[status], !current.rows.contains(where: { $0.id == transaction.id }) {
                withAnimation {
                    current.rows.insert(transaction, at: min(index, current.rows.count))
                    lists[status] = .loaded(current)
                }
            }
            alert = ErrorAlert(error)
        }
    }
}
