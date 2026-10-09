import Foundation
import MoneyMatterKit
import Observation

/// Every API seam for the connected server, injected into the signed-in UI with
/// `.environment(services)`. Read it in a feature with `@Environment(AppServices.self)`.
@Observable
final class AppServices {
    let identity: any SessionAPI
    let accounts: any AccountsServicing
    let transactions: any TransactionsServicing
    let taxonomy: any TaxonomyServicing
    let stats: any StatsServicing
    let subscriptions: any SubscriptionsServicing
    let review: any ReviewServicing
    let referenceData: any ReferenceDataServicing
    /// The underlying client, for calls that don't have a seam yet. `nil` with stubbed services.
    let client: APIClient?

    init(
        identity: any SessionAPI,
        accounts: any AccountsServicing,
        transactions: any TransactionsServicing,
        taxonomy: any TaxonomyServicing,
        stats: any StatsServicing,
        subscriptions: any SubscriptionsServicing,
        review: any ReviewServicing,
        referenceData: any ReferenceDataServicing,
        client: APIClient? = nil
    ) {
        self.identity = identity
        self.accounts = accounts
        self.transactions = transactions
        self.taxonomy = taxonomy
        self.stats = stats
        self.subscriptions = subscriptions
        self.review = review
        self.referenceData = referenceData
        self.client = client
    }

    /// Every seam backed by one live client.
    convenience init(client: APIClient) {
        let api = LiveAPI(client: client)
        self.init(
            identity: api,
            accounts: api,
            transactions: api,
            taxonomy: api,
            stats: api,
            subscriptions: api,
            review: api,
            referenceData: api,
            client: client
        )
    }
}
