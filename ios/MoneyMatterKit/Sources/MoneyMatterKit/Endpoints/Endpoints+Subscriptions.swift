import Foundation

extension Endpoints {
    /// `GET /subscriptions/summary`. Fails with 422 `CURRENCY_NOT_CONNECTED` when a
    /// subscription uses a currency the user hasn't connected.
    public static func subscriptionsSummary() -> Endpoint<SubscriptionsSummary> {
        Endpoint(.get, "/subscriptions/summary")
    }

    /// `GET /subscriptions/upcoming`. The server caps `limit` at 20.
    public static func upcomingPayments(limit: Int = 5) -> Endpoint<[UpcomingPayment]> {
        var query = QueryBuilder()
        query.add("limit", limit)
        return Endpoint(.get, "/subscriptions/upcoming", query: query.items)
    }

    /// `GET /subscriptions`. Nil `isActive` returns every subscription.
    public static func subscriptions(isActive: Bool? = true) -> Endpoint<[SubscriptionListItem]> {
        var query = QueryBuilder()
        query.add("isActive", isActive)
        return Endpoint(.get, "/subscriptions", query: query.items)
    }
}
