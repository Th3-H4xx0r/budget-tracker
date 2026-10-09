import Foundation

extension Endpoints {
    /// `GET /transactions`.
    public static func transactions(_ query: TransactionListQuery) -> Endpoint<[Transaction]> {
        Endpoint(.get, "/transactions", query: query.queryItems)
    }

    /// `GET /transactions/:id`: `nil` when missing. The row includes `canEdit`.
    public static func transaction(id: String, includeSplits: Bool = false) -> Endpoint<Transaction?> {
        var query = QueryBuilder()
        query.addFlag("includeSplits", includeSplits)
        return Endpoint(.get, "/transactions/\(id)", query: query.items)
    }

    /// `GET /transactions/by-ids`.
    public static func transactions(ids: [String]) -> Endpoint<[Transaction]> {
        var query = QueryBuilder()
        query.add("ids", list: ids)
        return Endpoint(.get, "/transactions/by-ids", query: query.items)
    }

    /// `GET /transactions/transfer/:transferId`: both legs of a transfer.
    public static func transferLegs(transferId: String) -> Endpoint<[Transaction]> {
        Endpoint(.get, "/transactions/transfer/\(transferId)")
    }

    /// `POST /transactions`: `[tx]`, or `[baseLeg, oppositeLeg]` for a transfer.
    public static func createTransaction(_ request: TransactionCreateRequest) -> Endpoint<[Transaction]> {
        Endpoint(.post, "/transactions", body: request)
    }

    /// `PUT /transactions/:id`: returns every leg that changed.
    public static func updateTransaction(id: String, _ request: TransactionUpdateRequest) -> Endpoint<[Transaction]> {
        Endpoint(.put, "/transactions/\(id)", body: request)
    }

    /// `DELETE /transactions/:id`. Deleting either leg of a transfer deletes both.
    public static func deleteTransaction(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/transactions/\(id)")
    }
}
