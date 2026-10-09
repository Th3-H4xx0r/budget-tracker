import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Endpoints")
struct EndpointsTests {
    private let server = try! ServerEndpoint(validating: "https://budget.example.com")

    private func url<Response>(_ endpoint: Endpoint<Response>) throws -> URL {
        let client = APIClient(server: server)
        return try client.makeRequest(for: endpoint).0.url!
    }

    private func bodyString<Response>(_ endpoint: Endpoint<Response>) throws -> String {
        let client = APIClient(server: server)
        let data = try #require(try client.makeRequest(for: endpoint).0.httpBody)
        return String(decoding: data, as: UTF8.self)
    }

    private func body<Response>(_ endpoint: Endpoint<Response>) throws -> [String: Any] {
        let client = APIClient(server: server)
        let data = try #require(try client.makeRequest(for: endpoint).0.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Transaction list params are comma-joined and omit empty values")
    func transactionListQuery() throws {
        var query = TransactionListQuery(limit: 50, offset: 100)
        query.order = .descending
        query.accountIds = ["a1", "a2"]
        query.categoryIds = []
        query.transactionType = .expense
        query.noteSearch = ["coffee", " ", "tea"]
        query.from = Date.iso("2026-10-01T00:00:00.000Z")
        query.includeTags = true
        query.includeSplits = false
        query.isPlanned = false

        let url = try url(Endpoints.transactions(query))

        #expect(url.path() == "/api/v1/transactions")
        let query1 = try #require(url.query())
        #expect(query1.contains("limit=50"))
        #expect(query1.contains("offset=100"))
        #expect(query1.contains("order=DESC"))
        #expect(query1.contains("accountIds=a1,a2"))
        #expect(!query1.contains("categoryIds"))
        #expect(query1.contains("transactionType=expense"))
        #expect(query1.contains("noteSearch=coffee,tea"))
        #expect(query1.contains("from=2026-10-01T00:00:00.000Z"))
        #expect(query1.contains("includeTags=true"))
        #expect(!query1.contains("includeSplits"))
        #expect(query1.contains("isPlanned=false"))
    }

    @Test("The latest-records query excludes out-of-wallet transfers")
    func latestRecords() {
        let now = Date.iso("2026-10-09T12:00:00.000Z")
        let items = TransactionListQuery.latestRecords(now: now).queryItems
        let natures = items.first { $0.name == "transferNatures" }?.value?.split(separator: ",").map(String.init)
        #expect(natures?.contains("transfer_out_wallet") == false)
        #expect(natures?.contains("not_transfer") == true)
        #expect(items.first { $0.name == "limit" }?.value == "40")
        #expect(items.first { $0.name == "to" }?.value == "2026-10-09T12:00:00.000Z")
    }

    @Test("Coerced booleans are omitted rather than sent as false")
    func coercedBooleans() throws {
        #expect(try url(Endpoints.accountGroups()).query() == nil)
        #expect(try url(Endpoints.accountGroups(includeArchived: true)).query() == "includeArchived=true")
    }

    @Test("Stats ranges use YYYY-MM-DD days")
    func statsDays() throws {
        let from = CalendarDate(year: 2026, month: 9, day: 1)
        let to = CalendarDate(year: 2026, month: 9, day: 30)
        let url = try url(Endpoints.spendingsByCategories(from: from, to: to))
        #expect(url.path() == "/api/v1/stats/spendings-by-categories")
        #expect(url.query() == "from=2026-09-01&to=2026-09-30&type=expense&excludePlanned=true")
    }

    @Test("Review list clamps limit and sends the status")
    func reviewList() throws {
        let url = try url(Endpoints.reviewTransactions(status: .fraud, limit: 500, offset: -5))
        #expect(url.path() == "/api/v1/transactions/review")
        #expect(url.query() == "status=fraud&limit=100&offset=0")
    }

    @Test("Review update sends ids and the action raw value")
    func reviewUpdate() throws {
        let body = try body(Endpoints.updateReviewStatus(transactionIds: ["t1", "t2"], action: .checkLater))
        #expect(body["transactionIds"] as? [String] == ["t1", "t2"])
        #expect(body["action"] as? String == "check_later")
    }

    @Test("A normal create sends a positive amount, not_transfer, and the category")
    func createExpense() throws {
        let request = TransactionCreateRequest(
            amount: Decimal(string: "84.21")!,
            transactionType: .expense,
            accountId: "acc",
            categoryId: "cat",
            time: Date.iso("2026-10-09T08:15:00.000Z"),
            note: "Lunch",
            tagIds: []
        )
        let body = try body(Endpoints.createTransaction(request))
        // Decimals are encoded with their exact digits, never as a binary float.
        #expect(try bodyString(Endpoints.createTransaction(request)).contains(#""amount":84.21"#))
        #expect(body["transferNature"] as? String == "not_transfer")
        #expect(body["categoryId"] as? String == "cat")
        #expect(body["time"] as? String == "2026-10-09T08:15:00.000Z")
        #expect(body["tagIds"] as? [String] == [])
        #expect(body["destinationAccountId"] == nil)
    }

    @Test("A transfer create sends the source leg as an expense with destination fields")
    func createTransfer() throws {
        let body = try body(Endpoints.createTransaction(.transfer(amount: 100, fromAccountId: "eur", toAccountId: "usd", destinationAmount: 108.5)))
        #expect(body["transactionType"] as? String == "expense")
        #expect(body["transferNature"] as? String == "transfer_between_user_accounts")
        #expect(body["destinationAccountId"] as? String == "usd")
        #expect((body["destinationAmount"] as? NSNumber)?.doubleValue == 108.5)
        #expect(body["categoryId"] == nil)
    }

    @Test("An update omits unchanged fields and sends null to clear")
    func updateClears() throws {
        let request = TransactionUpdateRequest(amount: 12, note: .clear, payeeId: .set("p-1"))
        let body = try body(Endpoints.updateTransaction(id: "t-1", request))
        #expect(body.keys.sorted() == ["amount", "note", "payeeId"])
        #expect(body["note"] is NSNull)
        #expect(body["payeeId"] as? String == "p-1")
    }

    @Test("Account create and update bodies use raw enum values")
    func accountBodies() throws {
        let create = try body(Endpoints.createAccount(AccountCreateRequest(name: "Card", currencyCode: "EUR", accountCategory: .creditCard, creditLimit: 500)))
        #expect(create["accountCategory"] as? String == "credit-card")
        #expect(create["initialBalance"] == nil)

        let update = try body(Endpoints.updateAccount(id: "a1", AccountUpdateRequest(status: .archived)))
        #expect(update.keys.sorted() == ["status"])
        #expect(update["status"] as? String == "archived")
    }

    @Test("Path parameters land in the URL")
    func paths() throws {
        #expect(try url(Endpoints.accountTransactionCount(id: "a1")).path() == "/api/v1/accounts/a1/transaction-count")
        #expect(try url(Endpoints.transferLegs(transferId: "tr")).path() == "/api/v1/transactions/transfer/tr")
        #expect(try url(Endpoints.transactions(ids: ["x", "y"])).query() == "ids=x,y")
        #expect(try url(Endpoints.searchPayees(query: " lidl ")).query() == "q=lidl")
        #expect(try url(Endpoints.upcomingPayments()).query() == "limit=5")
    }

    @Test("Query values with reserved characters are percent-encoded")
    func percentEncoding() throws {
        var query = TransactionListQuery()
        query.noteSearch = ["a&b=c d+é"]
        let url = try url(Endpoints.transactions(query))
        #expect(url.query(percentEncoded: true) == "noteSearch=a%26b%3Dc%20d%2B%C3%A9")
        #expect(url.query(percentEncoded: false) == "noteSearch=a&b=c d+é")
    }

    @Test("The native OAuth start URL carries the provider and challenge")
    func oauthStartURL() {
        let url = Endpoints.nativeOAuthStartURL(server: server, provider: .github, codeChallenge: "abc-_123")
        #expect(url.absoluteString == "https://budget.example.com/api/v1/auth/native/oauth/start?provider=github&code_challenge=abc-_123")
    }

    @Test("OAuth callbacks parse a code or an error")
    func oauthCallback() {
        #expect(OAuthCallback(url: URL(string: "moneymatter://auth-callback?code=xyz")!) == .code("xyz"))
        #expect(OAuthCallback(url: URL(string: "moneymatter://auth-callback?error=access_denied")!) == .error("access_denied"))
        #expect(OAuthCallback(url: URL(string: "moneymatter://auth-callback")!) == nil)
    }
}
