import Foundation

/// Params for `GET /transactions`. Nil and empty values are not sent. ID lists are strict
/// on the server: one malformed UUID fails the whole request with 422.
public struct TransactionListQuery: Sendable, Hashable {
    public enum SortField: String, Sendable, Hashable {
        case time, refAmount, accountName, categoryName, payeeName, categorizationSource
    }

    public var limit: Int?
    public var offset: Int?
    public var order: SortOrder?
    public var sortBy: SortField?
    /// Sent as ISO UTC timestamps.
    public var from: Date?
    public var to: Date?
    /// Only `income` and `expense` are meaningful.
    public var transactionType: TransactionType?
    public var accountIds: [String] = []
    public var excludeAccountIds: [String] = []
    public var categoryIds: [String] = []
    /// May include the literal `blank` for untagged rows.
    public var tagIds: [String] = []
    public var excludedTagIds: [String] = []
    /// May include the literal `blank` for rows without a payee.
    public var payeeIds: [String] = []
    public var budgetIds: [String] = []
    public var excludedBudgetIds: [String] = []
    /// An include-list; overrides `transferFilter`.
    public var transferNatures: [TransferNature] = []
    public var transferFilter: InclusionFilter?
    public var refundFilter: InclusionFilter?
    public var excludeTransfer: Bool?
    public var excludeRefunds: Bool?
    public var excludeBalanceAdjustments: Bool?
    /// Nil: real and own planned rows. `true`: planned only. `false`: real only.
    public var isPlanned: Bool?
    public var hasAttachment: Bool?
    public var amountGte: Decimal?
    public var amountLte: Decimal?
    /// Terms are ORed, case-insensitive substring matches.
    public var noteSearch: [String] = []
    public var includeSplits = false
    public var includeTags = false
    public var includeGroups = false
    public var includeHasAttachments = false

    public init(limit: Int? = nil, offset: Int? = nil) {
        self.limit = limit
        self.offset = offset
    }

    /// The Home "latest records" request: 40 rows up to now, excluding out-of-wallet
    /// transfers. The caller still drops rows dated in the future.
    public static func latestRecords(now: Date = .now) -> TransactionListQuery {
        var query = TransactionListQuery(limit: 40)
        query.to = now
        query.transferNatures = TransferNature.latestRecordsNatures
        query.includeSplits = true
        query.includeTags = true
        return query
    }

    public var queryItems: [URLQueryItem] {
        var builder = QueryBuilder()
        builder.add("limit", limit)
        builder.add("offset", offset)
        builder.add("order", order?.rawValue)
        builder.add("sortBy", sortBy?.rawValue)
        builder.add("from", timestamp: from)
        builder.add("to", timestamp: to)
        if let transactionType, transactionType != .unknown {
            builder.add("transactionType", transactionType.rawValue)
        }
        builder.add("accountIds", list: accountIds)
        builder.add("excludeAccountIds", list: excludeAccountIds)
        builder.add("categoryIds", list: categoryIds)
        builder.add("tagIds", list: tagIds)
        builder.add("excludedTagIds", list: excludedTagIds)
        builder.add("payeeIds", list: payeeIds)
        builder.add("budgetIds", list: budgetIds)
        builder.add("excludedBudgetIds", list: excludedBudgetIds)
        builder.add("transferNatures", list: transferNatures.filter { $0 != .unknown }.map(\.rawValue))
        builder.add("transferFilter", transferFilter?.rawValue)
        builder.add("refundFilter", refundFilter?.rawValue)
        builder.add("excludeTransfer", excludeTransfer)
        builder.add("excludeRefunds", excludeRefunds)
        builder.add("excludeBalanceAdjustments", excludeBalanceAdjustments)
        builder.add("isPlanned", isPlanned)
        builder.add("hasAttachment", hasAttachment)
        builder.add("amountGte", amountGte)
        builder.add("amountLte", amountLte)
        builder.add("noteSearch", list: noteSearch.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        builder.addFlag("includeSplits", includeSplits)
        builder.addFlag("includeTags", includeTags)
        builder.addFlag("includeGroups", includeGroups)
        builder.addFlag("includeHasAttachments", includeHasAttachments)
        return builder.items
    }
}
