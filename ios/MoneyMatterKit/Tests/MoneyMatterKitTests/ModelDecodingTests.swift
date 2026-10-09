import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Model decoding")
struct ModelDecodingTests {
    @Test("User decodes with entitlements and derived names")
    func user() throws {
        let user = try Fixture.decode(Endpoints.currentUser(), from: "user")
        #expect(user.id == 42)
        #expect(user.email == "pranav@example.com")
        #expect(user.role == .common)
        #expect(user.displayName == "Pranav Krishna")
        #expect(user.initials == "PK")
        #expect(user.entitlements?.features == ["bank_providers"])
        #expect(user.createdAt == Date.iso("2026-01-02T10:15:30.123Z"))
    }

    @Test("Currencies keep digits and the disabled flag")
    func currencies() throws {
        let currencies = try Fixture.decode(Endpoints.currencies(), from: "currencies")
        #expect(currencies.map(\.code) == ["USD", "JPY", "VEF"])
        #expect(currencies[1].digits == 0)
        #expect(currencies[2].isDisabled)
    }

    @Test("Base currency decodes, and a null response decodes to nil")
    func baseCurrency() throws {
        let base = try Fixture.decode(Endpoints.baseCurrency(), from: "base-currency")
        #expect(base?.currencyCode == "EUR")
        #expect(base?.isDefaultCurrency == true)
        #expect(base?.digits == 2)

        let missing = try Fixture.decode(Endpoints.baseCurrency(), from: "base-currency-null")
        #expect(missing == nil)
    }

    @Test("User currencies decode exchange rates as Decimal")
    func userCurrencies() throws {
        let currencies = try Fixture.decode(Endpoints.userCurrencies(), from: "user-currencies")
        #expect(currencies.count == 2)
        #expect(currencies[1].exchangeRate == Decimal(string: "0.9123"))
        #expect(currencies[0].exchangeRate == nil)
    }

    @Test("Accounts decode balances exactly, sharing info, and unknown enum values")
    func accounts() throws {
        let accounts = try Fixture.decode(Endpoints.accounts(), from: "accounts")
        #expect(accounts.count == 3)

        let checking = accounts[0]
        #expect(checking.currentBalance == Decimal(string: "1234.56"))
        #expect(checking.initialBalance == Decimal(string: "100.5"))
        #expect(checking.accountCategory == .currentAccount)
        #expect(checking.isSystem)
        #expect(checking.countsTowardNetWorth)

        let card = accounts[1]
        #expect(card.type == .monobank)
        #expect(card.accountCategory == .creditCard)
        #expect(card.isArchived)
        #expect(card.bankProviderType == .monobank)
        #expect(card.needsRelink == true)
        #expect(card.isSharedWithMe)
        #expect(card.share?.owner?.username == "partner")
        #expect(card.currentBalance == Decimal(string: "-250.1"))

        let future = accounts[2]
        #expect(future.type == .unknown)
        #expect(future.accountCategory == .unknown)
        #expect(future.status == .unknown)
        #expect(future.bankProviderType == .unknown)
    }

    @Test("Account groups nest child groups and flatten their accounts")
    func accountGroups() throws {
        let groups = try Fixture.decode(Endpoints.accountGroups(), from: "account-groups")
        #expect(groups.count == 2)
        let roots = AccountGroup.roots(of: groups)
        #expect(roots.map(\.id) == ["g-root"])
        #expect(roots[0].childGroups.first?.name == "Cards")
        #expect(roots[0].allAccounts.map(\.name) == ["Checking", "Visa"])
    }

    @Test("Transactions decode review fields, includes, and timestamps")
    func transactions() throws {
        let rows = try Fixture.decode(Endpoints.transactions(TransactionListQuery()), from: "transactions")
        #expect(rows.count == 2)

        let groceries = rows[0]
        #expect(groceries.amount == Decimal(string: "84.21"))
        #expect(groceries.signedAmount == Decimal(string: "-84.21"))
        #expect(groceries.transactionType == .expense)
        #expect(groceries.paymentType == .debitCard)
        #expect(groceries.reviewStatus == .fraud)
        #expect(groceries.isFraud)
        #expect(groceries.reviewDeferredAt == Date.iso("2026-10-09T08:00:00.500Z"))
        #expect(groceries.time == Date.iso("2026-10-08T17:42:10.000Z"))
        #expect(groceries.plannedMergedAt == Date.iso("2026-10-08T18:00:00.000Z"))
        #expect(groceries.categorizationSource == "ai")
        #expect(groceries.location == TransactionLocation(latitude: 50.45, longitude: 30.52))
        #expect(groceries.splits?.first?.amount == 50)
        #expect(groceries.tags?.map(\.name) == ["Trip"])
        #expect(groceries.hasAttachments == true)
        #expect(groceries.payeeLocked)
    }

    @Test("Unknown transaction enum values decode to .unknown instead of failing")
    func transactionUnknownEnums() throws {
        let rows = try Fixture.decode(Endpoints.transactions(TransactionListQuery()), from: "transactions")
        let salary = rows[1]
        #expect(salary.paymentType == .unknown)
        #expect(salary.transferNature == .unknown)
        #expect(salary.reviewStatus == .unknown)
        #expect(salary.accountType == .walutomat)
        #expect(salary.signedAmount == 1500)
        #expect(salary.splits == nil)
        #expect(salary.time == Date.iso("2026-10-01T09:00:00Z"))
    }

    @Test("A malformed split or tag is dropped instead of failing the row")
    func lossyIncludes() throws {
        let json = #"""
        {"status":"success","response":[{"id":"t-9","amount":5,"time":"2026-10-08T10:00:00.000Z","transactionType":"expense","accountId":"a","currencyCode":"EUR","transferNature":"not_transfer","splits":[{"id":"s-ok","categoryId":"c","amount":2,"refAmount":2,"note":null},{"id":"s-bad","amount":"oops"}],"tags":[{"id":"tag-ok","name":"Trip"},{"id":"tag-bad"}]}]}
        """#
        let rows = try Endpoints.transactions(TransactionListQuery()).decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
        #expect(rows.first?.splits?.map(\.id) == ["s-ok"])
        #expect(rows.first?.tags?.map(\.id) == ["tag-ok"])
    }

    @Test("A transfer create returns both legs with a shared transferId")
    func transferArray() throws {
        let legs = try Fixture.decode(Endpoints.createTransaction(.transfer(amount: 100, fromAccountId: "acc-eur", toAccountId: "acc-usd", destinationAmount: 108.5)), from: "transfer-create")
        #expect(legs.count == 2)
        #expect(legs.map(\.transactionType) == [.expense, .income])
        #expect(Set(legs.compactMap(\.transferId)) == ["tr-1"])
        #expect(legs.allSatisfy { $0.transferNature.isTwoLegTransfer && $0.categoryId == nil })
        #expect(legs[1].amount == Decimal(string: "108.5"))
    }

    @Test("A missing transaction decodes to nil")
    func missingTransaction() throws {
        let row = try Fixture.decode(Endpoints.transaction(id: "t-404"), from: "transaction-null")
        #expect(row == nil)
    }

    @Test("Categories decode leniently, ignoring extra columns")
    func categories() throws {
        let categories = try Fixture.decode(Endpoints.categories(), from: "categories")
        #expect(categories.count == 5)
        #expect(categories[0].type == .internal)
        #expect(categories[0].key == "other")
        #expect(categories[2].parentId == "c-food")
        #expect(categories[4].type == .unknown)
    }

    @Test("Tags and payees decode")
    func tagsAndPayees() throws {
        let tags = try Fixture.decode(Endpoints.tags(), from: "tags")
        #expect(tags.map(\.name) == ["Trip", "Work"])
        #expect(tags[1].remindersCount == 2)

        let lookup = try Fixture.decode(Endpoints.payeesLookup(), from: "payees-lookup")
        #expect(lookup.map(\.id) == ["p-1", "p-2"])
        #expect(lookup[1].logoInitials == "LL")

        let search = try Fixture.decode(Endpoints.searchPayees(query: "li"), from: "payees-search")
        #expect(search[0].defaultCategoryId == "c-food")
        #expect(search[0].defaultTagIds == ["tag-1"])
        #expect(search[0].stats?.transactionCount == 12)
        #expect(search[1].stats == nil)
        #expect(search[1].lookup.name == "New payee")
    }

    @Test("Balance history decodes day dates and totals")
    func balanceHistory() throws {
        let points = try Fixture.decode(
            Endpoints.combinedBalanceHistory(from: CalendarDate(year: 2026, month: 10, day: 1), to: CalendarDate(year: 2026, month: 10, day: 2)),
            from: "balance-history"
        )
        #expect(points.map(\.date) == [CalendarDate(year: 2026, month: 10, day: 1), CalendarDate(year: 2026, month: 10, day: 2)])
        #expect(points[0].totalBalance == Decimal(string: "1150.25"))
        #expect(points[1].loansBalance == -100)
    }

    @Test("Spending by category becomes an array sorted by amount")
    func spendings() throws {
        let day = CalendarDate(year: 2026, month: 10, day: 1)
        let spending = try Fixture.decode(Endpoints.spendingsByCategories(from: day, to: day), from: "spendings-by-categories")
        #expect(spending.map(\.id) == ["c-rent", "c-food", "c-fun"])
        #expect(spending[1].amount == Decimal(string: "320.4"))
        #expect(spending[0].color == "#e67e22")
    }

    @Test("Expenses total decodes a bare number response")
    func expensesTotal() throws {
        let day = CalendarDate(year: 2026, month: 10, day: 1)
        let total = try Fixture.decode(Endpoints.expensesAmountForPeriod(from: day, to: day), from: "expenses-amount")
        #expect(total.amount == Decimal(string: "1566.39"))
    }

    @Test("Upcoming payments decode, with unknown frequencies tolerated")
    func upcomingPayments() throws {
        let payments = try Fixture.decode(Endpoints.upcomingPayments(), from: "upcoming-payments")
        #expect(payments[0].nextPaymentDate == CalendarDate(year: 2026, month: 10, day: 11))
        #expect(payments[0].expectedAmount == Decimal(string: "15.99"))
        #expect(payments[1].frequency == .unknown)
        #expect(payments[1].transactionType == .income)
        #expect(payments[1].nextPaymentDate == nil)
    }

    @Test("Subscription items decode periods and the upcoming-payments rule")
    func subscriptions() throws {
        let items = try Fixture.decode(Endpoints.subscriptions(), from: "subscriptions")
        #expect(items.count == 3)
        let today = CalendarDate(year: 2026, month: 10, day: 9)
        #expect(items[0].currentPeriod?.status == .upcoming)
        #expect(items[0].needsAttention(today: today))
        #expect(items[1].isOverdue)
        #expect(items[1].needsAttention(today: today))
        #expect(items[2].needsAttention(today: today) == false)
        #expect(items[0].account?.name == "Checking")
    }

    @Test("Subscriptions summary and review summary decode")
    func summaries() throws {
        let summary = try Fixture.decode(Endpoints.subscriptionsSummary(), from: "subscriptions-summary")
        #expect(summary.activeCount.expense == 2)
        #expect(summary.estimatedMonthlyCost == Decimal(string: "45.99"))

        let review = try Fixture.decode(Endpoints.reviewSummary(), from: "review-summary")
        #expect(review == ReviewSummary(unreviewedCount: 12, fraudCount: 2))
    }

    @Test("Bare better-auth bodies decode, including a null session")
    func authBodies() throws {
        let session = try Fixture.decode(Endpoints.session(), from: "auth-session")
        #expect(session?.user.email == "pranav@example.com")
        #expect(session?.session.expiresAt == Date.iso("2026-10-16T08:00:00.000Z"))

        let missing = try Fixture.decode(Endpoints.session(), from: "auth-session-null")
        #expect(missing == nil)

        let token = try Fixture.decode(
            Endpoints.signUpEmail(name: "New", email: "new@example.com", password: "secret123", callbackURL: URL(string: "https://example.com/auth/callback")!),
            from: "sign-up-verification"
        )
        #expect(token == nil)

        let open = try Fixture.decode(Endpoints.signupsOpen(), from: "signups-open")
        #expect(open)
    }

    @Test("A success envelope without a response decodes to EmptyResponse")
    func emptySuccess() throws {
        let empty = try Fixture.decode(Endpoints.deleteTransaction(id: "t-1"), from: "empty-success")
        #expect(empty == EmptyResponse())
    }

    @Test("Passkey options decode base64url challenge and credentials")
    func passkeyOptions() throws {
        let options = try Fixture.decode(Endpoints.passkeyAuthenticationOptions(), from: "passkey-options")
        #expect(options.challenge == Data("test-challenge-bytes".utf8))
        #expect(options.rpId == "budget.pkrishna.dev")
        #expect(options.allowedCredentialIDs == [Data("cred-1".utf8)])
    }

    @Test("The OAuth exchange accepts both an envelope and a bare body")
    func exchangeEitherShape() throws {
        let endpoint = Endpoints.exchangeOAuthCode("c", codeVerifier: "v")
        let decoder = JSONCoding.makeDecoder()
        #expect(try endpoint.decodeBody(Data(#"{"status":"success","response":{"token":"signed.tok"}}"#.utf8), decoder) == "signed.tok")
        #expect(try endpoint.decodeBody(Data(#"{"token":"bare.tok"}"#.utf8), decoder) == "bare.tok")
    }
}
