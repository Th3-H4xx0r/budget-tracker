import Foundation

extension Endpoints {
    /// `GET /transactions/review/summary`.
    public static func reviewSummary() -> Endpoint<ReviewSummary> {
        Endpoint(.get, "/transactions/review/summary")
    }

    /// `GET /transactions/review`: rows include splits, tags, and `hasAttachments`.
    /// Unreviewed rows come never-deferred first (oldest first), then deferred rows by
    /// deferral time; reviewed and fraud rows come newest first. `limit` is 1...100.
    public static func reviewTransactions(status: ReviewListStatus, limit: Int = 50, offset: Int = 0) -> Endpoint<[Transaction]> {
        var query = QueryBuilder()
        query.add("status", status.rawValue)
        query.add("limit", min(max(limit, 1), 100))
        query.add("offset", max(offset, 0))
        return Endpoint(.get, "/transactions/review", query: query.items)
    }

    /// `PUT /transactions/review`: all-or-nothing; 404 if any id is missing or not the
    /// caller's. Returns the updated count.
    public static func updateReviewStatus(transactionIds: [String], action: ReviewAction) -> Endpoint<Int> {
        Endpoint<ReviewUpdateResponse>(
            .put,
            "/transactions/review",
            body: ReviewUpdateRequest(transactionIds: transactionIds, action: action)
        )
        .map(\.updatedCount)
    }
}
