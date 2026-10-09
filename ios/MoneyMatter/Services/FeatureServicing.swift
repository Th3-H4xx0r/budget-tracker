import Foundation
import MoneyMatterKit

// Seams for the feature screens. View models take these protocols, so tests and previews
// can pass stubs. Every method throws `APIError`.

protocol AccountsServicing: Sendable {
    func accounts() async throws -> [Account]
    /// `nil` when the account no longer exists.
    func account(id: String) async throws -> Account?
    func accountGroups(includeArchived: Bool) async throws -> [AccountGroup]
    func createAccount(_ request: AccountCreateRequest) async throws -> Account
    func updateAccount(id: String, _ request: AccountUpdateRequest) async throws -> Account
    func deleteAccount(id: String) async throws
    /// Shown in the delete confirmation.
    func transactionCount(accountID: String) async throws -> Int
}

protocol TransactionsServicing: Sendable {
    func transactions(_ query: TransactionListQuery) async throws -> [Transaction]
    /// `nil` when the transaction no longer exists.
    func transaction(id: String) async throws -> Transaction?
    func transferLegs(transferId: String) async throws -> [Transaction]
    /// Returns one row, or both legs of a transfer.
    func createTransaction(_ request: TransactionCreateRequest) async throws -> [Transaction]
    func updateTransaction(id: String, _ request: TransactionUpdateRequest) async throws -> [Transaction]
    /// Deleting either leg of a transfer deletes both.
    func deleteTransaction(id: String) async throws
}

protocol TaxonomyServicing: Sendable {
    func categories() async throws -> [Category]
    func tags() async throws -> [Tag]
    func payeesLookup() async throws -> [PayeeLookup]
    func searchPayees(query: String) async throws -> [Payee]
}

protocol StatsServicing: Sendable {
    func balanceHistory(from: CalendarDate, to: CalendarDate) async throws -> [BalancePoint]
    /// Expense categories, largest first, in the base currency.
    func spendingByCategory(from: CalendarDate, to: CalendarDate) async throws -> [CategorySpending]
    func expensesTotal(from: CalendarDate, to: CalendarDate) async throws -> Decimal
}

protocol SubscriptionsServicing: Sendable {
    func subscriptionsSummary() async throws -> SubscriptionsSummary
    func upcomingPayments(limit: Int) async throws -> [UpcomingPayment]
    func activeSubscriptions() async throws -> [SubscriptionListItem]
}

protocol ReviewServicing: Sendable {
    func reviewSummary() async throws -> ReviewSummary
    func reviewTransactions(status: ReviewListStatus, limit: Int, offset: Int) async throws -> [Transaction]
    /// All-or-nothing; returns the updated count.
    func updateReviewStatus(transactionIds: [String], action: ReviewAction) async throws -> Int
}

extension ReviewServicing {
    /// A review stack session over the unreviewed queue, wired to this service.
    func makeReviewSession(
        pageSize: Int = ReviewSession.defaultPageSize,
        prefetchThreshold: Int = ReviewSession.defaultPrefetchThreshold
    ) -> ReviewSession {
        ReviewSession(
            pageSize: pageSize,
            prefetchThreshold: prefetchThreshold,
            fetchPage: { [self] offset, limit in
                try await reviewTransactions(status: .unreviewed, limit: limit, offset: offset)
            },
            submitAction: { [self] ids, action in
                _ = try await updateReviewStatus(transactionIds: ids, action: action)
            }
        )
    }
}

/// What `ReferenceDataStore` loads for the session.
protocol ReferenceDataServicing: Sendable {
    func accounts() async throws -> [Account]
    func categories() async throws -> [Category]
    func tags() async throws -> [Tag]
    func payeesLookup() async throws -> [PayeeLookup]
    func userCurrencies() async throws -> [UserCurrency]
}
