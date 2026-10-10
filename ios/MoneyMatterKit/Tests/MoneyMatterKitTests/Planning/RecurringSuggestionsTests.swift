import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Recurring match suggestions")
struct RecurringSuggestionsTests {
    private let server = try! ServerEndpoint(validating: "https://budget.example.com")

    private func decode<Value>(_ endpoint: Endpoint<Value>, _ json: String) throws -> Value {
        try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
    }

    private func request<Response>(_ endpoint: Endpoint<Response>) throws -> URLRequest {
        try APIClient(server: server).makeRequest(for: endpoint).0
    }

    private func transactionJSON(_ id: String) -> String {
        """
        {"id":"\(id)","amount":15.49,"time":"2026-09-15T10:00:00.000Z","transactionType":"expense","accountId":"a1","currencyCode":"USD","reviewStatus":"reviewed"}
        """
    }

    @Test("Suggestions decode scores, confidence, reasons with detail, and tolerate unknowns")
    func suggestions() throws {
        let json = """
        {"status":"success","response":{"suggestions":[
          {"transaction":\(transactionJSON("tx1")),"score":0.912,"confidence":"high",
           "reasons":[{"code":"payee_match","weight":0.35,"value":1},
                      {"code":"near_due_date","weight":0.2,"value":0.8,"detail":{"dueDate":"2026-09-14","days":1}},
                      {"code":"amount_differs","weight":0.25,"value":0.4,"detail":{"deviationPct":16.2}},
                      {"code":"brand_new_signal","weight":0.1,"value":1}],
           "nearestDueDate":"2026-09-14","daysFromDue":1,"amountDeviationPct":16.2},
          {"transaction":\(transactionJSON("tx2")),"score":0.55,"confidence":"low","reasons":null,
           "nearestDueDate":null,"daysFromDue":null,"amountDeviationPct":null},
          {"transaction":null,"score":0.6}
        ],"dismissedCount":2}}
        """
        let response = try decode(Endpoints.recurringSuggestions(id: "s1"), json)
        #expect(response.dismissedCount == 2)
        #expect(response.suggestions.map(\.id) == ["tx1", "tx2"])
        let first = response.suggestions[0]
        #expect(first.confidence == .high)
        #expect(first.score == 0.912)
        #expect(first.nearestDueDate == CalendarDate(year: 2026, month: 9, day: 14))
        #expect(first.daysFromDue == 1)
        #expect(first.reasons.map(\.code) == [.payeeMatch, .nearDueDate, .amountDiffers, .unknown])
        #expect(first.reasons[1].days == 1)
        #expect(first.reasons[1].dueDate == CalendarDate(year: 2026, month: 9, day: 14))
        #expect(first.reasons[2].deviationPct == 16.2)
        #expect(first.reasons.filter(\.isDisplayable).count == 3)
        let second = response.suggestions[1]
        #expect(second.confidence == .unknown)
        #expect(second.reasons.isEmpty)
        #expect(second.nearestDueDate == nil)
        #expect(second.amountDeviationPct == nil)
    }

    @Test("Suggestions request carries the limit")
    func suggestionsRequest() throws {
        let url = try #require(try request(Endpoints.recurringSuggestions(id: "s1", limit: 20)).url)
        #expect(url.path == "/api/v1/subscriptions/s1/suggestions" || url.path.hasSuffix("/subscriptions/s1/suggestions"))
        #expect(url.query == "limit=20")
    }

    @Test("Linkable transactions decode linked-elsewhere rows and paging")
    func linkable() throws {
        let json = """
        {"status":"success","response":{"items":[
          {"transaction":\(transactionJSON("tx1")),"score":0.3,"reasons":[],"linkedSubscription":{"id":"s2","name":"Gym"},"isDismissed":false},
          {"transaction":\(transactionJSON("tx2")),"score":0.7,"reasons":[{"code":"same_account","weight":0.1,"value":1}],"linkedSubscription":null,"isDismissed":true}
        ],"hasMore":true}}
        """
        let page = try decode(Endpoints.recurringLinkableTransactions(id: "s1", query: RecurringLinkableQuery()), json)
        #expect(page.hasMore)
        #expect(page.items.count == 2)
        #expect(page.items[0].linkedSubscription?.name == "Gym")
        #expect(page.items[1].linkedSubscription == nil)
        #expect(page.items[1].isDismissed)
        #expect(page.items[1].reasons.first?.code == .sameAccount)
    }

    @Test("Linkable query sends filters, skips short searches, and clamps the limit")
    func linkableQuery() throws {
        let query = RecurringLinkableQuery(
            search: " netflix ",
            from: CalendarDate(year: 2026, month: 1, day: 1),
            to: CalendarDate(year: 2026, month: 3, day: 31),
            accountIds: ["a1", "a2"],
            sort: .relevance,
            limit: 500,
            offset: 30
        )
        let url = try #require(try request(Endpoints.recurringLinkableTransactions(id: "s1", query: query)).url)
        #expect(url.path.hasSuffix("/subscriptions/s1/linkable-transactions"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(values["search"] == "netflix")
        #expect(values["from"] == "2026-01-01")
        #expect(values["to"] == "2026-03-31")
        #expect(values["accountIds"] == "a1,a2")
        #expect(values["sort"] == "relevance")
        #expect(values["limit"] == "100")
        #expect(values["offset"] == "30")

        let short = try #require(try request(Endpoints.recurringLinkableTransactions(
            id: "s1",
            query: RecurringLinkableQuery(search: "n")
        )).url)
        #expect(short.query == "sort=date&limit=30")
    }

    @Test("Dismiss posts the transaction ids")
    func dismiss() throws {
        let urlRequest = try request(Endpoints.dismissRecurringSuggestions(id: "s1", transactionIds: ["tx1", "tx2"]))
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.url?.path.hasSuffix("/subscriptions/s1/suggestions/dismiss") == true)
        let data = try #require(urlRequest.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["transactionIds"] as? [String] == ["tx1", "tx2"])
        let result = try decode(
            Endpoints.dismissRecurringSuggestions(id: "s1", transactionIds: []),
            #"{"status":"success","response":{"dismissed":2}}"#
        )
        #expect(result.dismissed == 2)
    }

    @Test("List entries carry the pending suggestions count, defaulting to zero")
    func listEntries() throws {
        let json = """
        {"status":"success","response":[
          {"id":"s1","name":"Netflix","type":"subscription","frequency":"monthly","isActive":true,"pendingSuggestionsCount":3},
          {"id":"s2","name":"Gym","type":"subscription","frequency":"monthly","isActive":true}
        ]}
        """
        let entries = try decode(Endpoints.recurringSubscriptionEntries(sortBy: .dueDate), json)
        #expect(entries.map(\.id) == ["s1", "s2"])
        #expect(entries.map(\.pendingSuggestionsCount) == [3, 0])
        #expect(entries[0].item.name == "Netflix")
    }

    @Test("Planned details mark recurring actuals and count each entry once")
    func plannedActuals() throws {
        let json = """
        {"status":"success","response":{
          "plan":{"id":"p1","name":"October","type":"manual","status":"active","startDate":"2026-10-01","endDate":"2026-10-31"},
          "occurrences":[
            {"source":"recurring","subscriptionId":"s1","name":"Netflix","transactionType":"expense","amount":15.49,"date":"2026-11-15"},
            {"source":"recurring_actual","id":"e9","transactionId":"tx9","subscriptionId":"s1","name":"Netflix","transactionType":"expense","amount":15.99,"date":"2026-10-15"},
            {"source":"manual","id":"e9","transactionType":"expense","amount":15.99,"date":"2026-10-15"},
            {"source":"manual","id":"e1","transactionType":"expense","amount":5,"date":"2026-10-03","frequency":"weekly"},
            {"source":"manual","id":"e1","transactionType":"expense","amount":5,"date":"2026-10-10","frequency":"weekly"}
          ],
          "summary":{"income":0,"expense":51.48,"net":-51.48}}}
        """
        let details = try decode(Endpoints.plannedBudgetDetailsWithActuals(id: "p1"), json)
        #expect(details.plan.name == "October")
        #expect(details.occurrences.count == 4)
        let actual = try #require(details.occurrences.first { $0.isRecurringActual })
        #expect(actual.transactionId == "tx9")
        #expect(actual.occurrence.subscriptionId == "s1")
        #expect(actual.occurrence.name == "Netflix")
        #expect(actual.occurrence.source == .unknown)
        #expect(details.occurrences.filter { $0.occurrence.id == "e9" }.count == 1)
        #expect(details.occurrences.filter { $0.occurrence.id == "e1" }.count == 2)
    }
}
