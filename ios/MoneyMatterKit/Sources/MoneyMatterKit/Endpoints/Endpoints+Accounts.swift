import Foundation

extension Endpoints {
    /// `GET /accounts`: owned and shared, active and archived.
    public static func accounts() -> Endpoint<[Account]> {
        Endpoint(.get, "/accounts")
    }

    /// `GET /accounts/:id`: `nil` when missing.
    public static func account(id: String) -> Endpoint<Account?> {
        Endpoint(.get, "/accounts/\(id)")
    }

    /// `POST /accounts`.
    public static func createAccount(_ request: AccountCreateRequest) -> Endpoint<Account> {
        Endpoint<Account?>(.post, "/accounts", body: request).map(requireAccount)
    }

    /// `PUT /accounts/:id`.
    public static func updateAccount(id: String, _ request: AccountUpdateRequest) -> Endpoint<Account> {
        Endpoint<Account?>(.put, "/accounts/\(id)", body: request).map(requireAccount)
    }

    /// `DELETE /accounts/:id`: a hard delete, including the account's transactions.
    public static func deleteAccount(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/accounts/\(id)")
    }

    /// `GET /accounts/:id/transaction-count`, shown in the delete confirmation.
    public static func accountTransactionCount(id: String) -> Endpoint<Int> {
        Endpoint<TransactionCountResponse>(.get, "/accounts/\(id)/transaction-count").map(\.transactionCount)
    }

    /// `GET /account-group`. `includeArchived` is a `z.coerce` boolean, so it's omitted when false.
    public static func accountGroups(includeArchived: Bool = false) -> Endpoint<[AccountGroup]> {
        var query = QueryBuilder()
        query.addFlag("includeArchived", includeArchived)
        return Endpoint(.get, "/account-group", query: query.items)
    }

    @Sendable private static func requireAccount(_ account: Account?) throws -> Account {
        guard let account else { throw APIError.decoding("The server returned no account.") }
        return account
    }
}
