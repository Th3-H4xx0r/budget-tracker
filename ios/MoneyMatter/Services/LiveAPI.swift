import Foundation
import MoneyMatterKit

/// Implements every service seam over one `APIClient`.
struct LiveAPI {
    let client: APIClient
}

extension LiveAPI: AuthServicing {
    func signupsOpen() async throws -> Bool {
        try await client.send(Endpoints.signupsOpen())
    }

    func checkAppSupport() async throws {
        try await client.checkAppSupport()
    }

    func currentSession() async throws -> AuthSession? {
        try await client.send(Endpoints.session())
    }

    func signIn(email: String, password: String) async throws -> String {
        try await client.signIn(email: email, password: password)
    }

    func signUp(name: String, email: String, password: String) async throws -> SignUpResult {
        try await client.signUp(name: name, email: email, password: password)
    }

    func oauthStartURL(provider: OAuthProvider, codeChallenge: String) -> URL {
        Endpoints.nativeOAuthStartURL(server: client.server, provider: provider, codeChallenge: codeChallenge)
    }

    func exchangeOAuthCode(_ code: String, codeVerifier: String) async throws -> String {
        try await client.exchangeOAuthCode(code, codeVerifier: codeVerifier)
    }

    func signInWithPasskey(
        assert: @Sendable (PasskeyRequestOptions) async throws -> PasskeyAssertion
    ) async throws -> String {
        try await client.signInWithPasskey(assert: assert)
    }

    func signOut() async throws {
        _ = try await client.send(Endpoints.signOut())
    }
}

extension LiveAPI: UserServicing {
    func currentUser() async throws -> User {
        try await client.send(Endpoints.currentUser())
    }

    func baseCurrency() async throws -> UserCurrency? {
        try await client.send(Endpoints.baseCurrency())
    }

    func setBaseCurrency(code: String) async throws -> UserCurrency {
        try await client.send(Endpoints.setBaseCurrency(code: code))
    }

    func userCurrencies() async throws -> [UserCurrency] {
        try await client.send(Endpoints.userCurrencies())
    }

    func allCurrencies() async throws -> [Currency] {
        try await client.send(Endpoints.currencies())
    }

    func addUserCurrencies(codes: [String]) async throws -> AddedUserCurrencies {
        try await client.send(Endpoints.addUserCurrencies(codes: codes))
    }
}

extension LiveAPI: AccountsServicing {
    func accounts() async throws -> [Account] {
        try await client.send(Endpoints.accounts())
    }

    func account(id: String) async throws -> Account? {
        try await client.send(Endpoints.account(id: id))
    }

    func accountGroups(includeArchived: Bool) async throws -> [AccountGroup] {
        try await client.send(Endpoints.accountGroups(includeArchived: includeArchived))
    }

    func createAccount(_ request: AccountCreateRequest) async throws -> Account {
        try await client.send(Endpoints.createAccount(request))
    }

    func updateAccount(id: String, _ request: AccountUpdateRequest) async throws -> Account {
        try await client.send(Endpoints.updateAccount(id: id, request))
    }

    func deleteAccount(id: String) async throws {
        _ = try await client.send(Endpoints.deleteAccount(id: id))
    }

    func transactionCount(accountID: String) async throws -> Int {
        try await client.send(Endpoints.accountTransactionCount(id: accountID))
    }
}

extension LiveAPI: TransactionsServicing {
    func transactions(_ query: TransactionListQuery) async throws -> [Transaction] {
        try await client.send(Endpoints.transactions(query))
    }

    func transaction(id: String) async throws -> Transaction? {
        try await client.send(Endpoints.transaction(id: id))
    }

    func transferLegs(transferId: String) async throws -> [Transaction] {
        try await client.send(Endpoints.transferLegs(transferId: transferId))
    }

    func createTransaction(_ request: TransactionCreateRequest) async throws -> [Transaction] {
        try await client.send(Endpoints.createTransaction(request))
    }

    func updateTransaction(id: String, _ request: TransactionUpdateRequest) async throws -> [Transaction] {
        try await client.send(Endpoints.updateTransaction(id: id, request))
    }

    func deleteTransaction(id: String) async throws {
        _ = try await client.send(Endpoints.deleteTransaction(id: id))
    }
}

extension LiveAPI: TaxonomyServicing, ReferenceDataServicing {
    func categories() async throws -> [Category] {
        try await client.send(Endpoints.categories())
    }

    func tags() async throws -> [Tag] {
        try await client.send(Endpoints.tags())
    }

    func payeesLookup() async throws -> [PayeeLookup] {
        try await client.send(Endpoints.payeesLookup())
    }

    func searchPayees(query: String) async throws -> [Payee] {
        try await client.send(Endpoints.searchPayees(query: query))
    }
}

extension LiveAPI: StatsServicing {
    func balanceHistory(from: CalendarDate, to: CalendarDate) async throws -> [BalancePoint] {
        try await client.send(Endpoints.combinedBalanceHistory(from: from, to: to))
    }

    func spendingByCategory(from: CalendarDate, to: CalendarDate) async throws -> [CategorySpending] {
        try await client.send(Endpoints.spendingsByCategories(from: from, to: to))
    }

    func expensesTotal(from: CalendarDate, to: CalendarDate) async throws -> Decimal {
        try await client.send(Endpoints.expensesAmountForPeriod(from: from, to: to)).amount
    }
}

extension LiveAPI: SubscriptionsServicing {
    func subscriptionsSummary() async throws -> SubscriptionsSummary {
        try await client.send(Endpoints.subscriptionsSummary())
    }

    func upcomingPayments(limit: Int) async throws -> [UpcomingPayment] {
        try await client.send(Endpoints.upcomingPayments(limit: limit))
    }

    func activeSubscriptions() async throws -> [SubscriptionListItem] {
        try await client.send(Endpoints.subscriptions(isActive: true))
    }
}

extension LiveAPI: ReviewServicing {
    func reviewSummary() async throws -> ReviewSummary {
        try await client.send(Endpoints.reviewSummary())
    }

    func reviewTransactions(status: ReviewListStatus, limit: Int, offset: Int) async throws -> [Transaction] {
        try await client.send(Endpoints.reviewTransactions(status: status, limit: limit, offset: offset))
    }

    func updateReviewStatus(transactionIds: [String], action: ReviewAction) async throws -> Int {
        try await client.send(Endpoints.updateReviewStatus(transactionIds: transactionIds, action: action))
    }
}
