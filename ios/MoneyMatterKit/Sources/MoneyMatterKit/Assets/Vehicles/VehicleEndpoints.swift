import Foundation

extension Endpoints {
    /// `GET /vehicles`.
    public static func vehicles() -> Endpoint<[Vehicle]> {
        Endpoint(.get, "/vehicles")
    }

    /// `GET /vehicles/:id`: `nil` when missing.
    public static func vehicle(id: String) -> Endpoint<Vehicle?> {
        Endpoint(.get, "/vehicles/\(id)")
    }

    /// `POST /vehicles`.
    public static func vehicleCreate(_ request: VehicleCreateRequest) -> Endpoint<Vehicle?> {
        Endpoint(.post, "/vehicles", body: request)
    }

    /// `PATCH /vehicles/:id`.
    public static func vehicleUpdate(id: String, _ request: VehicleUpdateRequest) -> Endpoint<Vehicle?> {
        Endpoint(.patch, "/vehicles/\(id)", body: request)
    }

    /// `DELETE /vehicles/:id`: removes the vehicle and its account.
    public static func vehicleDelete(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/vehicles/\(id)")
    }

    /// `POST /accounts/:id/balance-adjustment` on the vehicle's account: records a value
    /// override as an out-of-wallet adjustment transaction.
    public static func vehicleValueOverride(
        accountId: String,
        _ request: VehicleValueOverrideRequest
    ) -> Endpoint<VehicleValueOverrideResult> {
        Endpoint(.post, "/accounts/\(accountId)/balance-adjustment", body: request)
    }

    /// The vehicle account's value overrides: its out-of-wallet transfers, newest first.
    public static func vehicleValueOverrides(accountId: String, limit: Int = 100) -> Endpoint<[Transaction]> {
        var query = TransactionListQuery(limit: limit, offset: 0)
        query.accountIds = [accountId]
        query.transferFilter = .only
        return transactions(query).map { rows in
            rows.filter { $0.transferNature == .outOfWallet }
        }
    }
}
