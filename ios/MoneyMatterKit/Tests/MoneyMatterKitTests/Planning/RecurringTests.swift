import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Recurring payments")
struct RecurringTests {
    private let server = try! ServerEndpoint(validating: "https://budget.example.com")

    private func decode<Value>(_ endpoint: Endpoint<Value>, _ json: String) throws -> Value {
        try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
    }

    private func request<Response>(_ endpoint: Endpoint<Response>) throws -> URLRequest {
        try APIClient(server: server).makeRequest(for: endpoint).0
    }

    private func body<Response>(_ endpoint: Endpoint<Response>) throws -> [String: Any] {
        let data = try #require(try request(endpoint).httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Detail decodes periods, rules, reminders, and linked transactions")
    func detail() throws {
        let json = """
        {"status":"success","response":{
          "id":"s1","name":"Netflix","type":"subscription","transactionType":"expense",
          "expectedAmount":15.49,"expectedCurrencyCode":"USD","frequency":"monthly",
          "startDate":"2026-01-01","endDate":null,"accountId":"a1","categoryId":"c1","payeeId":null,
          "tagIds":["t1"],"isActive":true,"notes":null,"dueDate":"2026-10-15","anchorDay":15,
          "maxOccurrences":null,"completedAt":null,"autoRecord":false,"notifyEmail":true,
          "remindBefore":["1_day","9_days"],
          "matchingRules":{"rules":[
            {"field":"note","operator":"contains_any","value":["netflix"]},
            {"field":"amount","operator":"between","value":{"min":10,"max":20},"currencyCode":"USD"},
            {"field":"payee","operator":"equals","value":"x"}
          ]},
          "nextExpectedDate":"2026-10-15",
          "periods":[
            {"id":"p1","subscriptionId":"s1","dueDate":"2026-09-15","status":"paid","paidAt":"2026-09-15T10:00:00.000Z","transactionId":"tx1","transactionAutoCreated":true,"notes":null},
            {"id":"p2","subscriptionId":"s1","dueDate":"2026-10-15","status":"upcoming","paidAt":null,"transactionId":null,"transactionAutoCreated":false,"notes":null},
            {"id":"p3","subscriptionId":"s1","dueDate":"2026-11-15","status":"mystery"}
          ],
          "account":{"id":"a1","name":"Card","currencyCode":"USD"},
          "category":{"id":"c1","name":"Streaming","color":"#ff0000","icon":null},
          "transactions":[
            {"id":"tx1","amount":15.49,"time":"2026-09-15T10:00:00.000Z","transactionType":"expense","accountId":"a1","currencyCode":"USD","reviewStatus":"reviewed","SubscriptionTransactions":{"matchSource":"rule","matchedAt":"2026-09-15T10:01:00.000Z","status":"active"}},
            {"id":"tx2","amount":15.49,"time":"2026-08-15T10:00:00.000Z","transactionType":"expense","accountId":"a1","currencyCode":"USD","reviewStatus":"reviewed","SubscriptionTransactions":{"matchSource":"manual","matchedAt":"2026-08-15T10:01:00.000Z","status":"unlinked"}}
          ]
        }}
        """
        let detail = try decode(Endpoints.recurringSubscription(id: "s1"), json)
        #expect(detail.name == "Netflix")
        #expect(detail.expectedAmount == Decimal(string: "15.49"))
        #expect(detail.frequency == .monthly)
        #expect(detail.remindBefore == [.oneDay])
        #expect(detail.matchingRules.rules == [
            .note(keywords: ["netflix"]),
            .amount(min: 10, max: 20, currencyCode: "USD"),
        ])
        #expect(detail.automationMode == .match)
        #expect(detail.periods.map(\.status) == [.paid, .upcoming, .unknown])
        #expect(detail.periods[0].transactionAutoCreated)
        #expect(detail.currentPeriod?.id == "p2")
        #expect(detail.paidPeriodsCount == 1)
        #expect(detail.transactions.count == 2)
        #expect(detail.activeTransactions.map(\.id) == ["tx1"])
        #expect(detail.transactions[0].matchSource == "rule")
        #expect(detail.account?.name == "Card")
        #expect(detail.nextExpectedDate == CalendarDate(year: 2026, month: 10, day: 15))
    }

    @Test("Automation mode prefers auto-record, then rules, then manual")
    func automationMode() {
        #expect(RecurringAutomationMode(autoRecord: true, rules: [.note(keywords: ["a"])]) == .record)
        #expect(RecurringAutomationMode(autoRecord: false, rules: [.note(keywords: ["a"])]) == .match)
        #expect(RecurringAutomationMode(autoRecord: false, rules: []) == .manual)
    }

    @Test("Empty matching rules are dropped and keywords trimmed")
    func nonEmptyRules() {
        let rules = RecurringMatchingRule.nonEmpty([
            .note(keywords: [" spotify ", " "]),
            .note(keywords: [""]),
            .amount(min: 0, max: 0, currencyCode: nil),
            .accountId(""),
            .transactionType("expense"),
        ])
        #expect(rules == [.note(keywords: ["spotify"]), .transactionType("expense")])
    }

    @Test("Candidates decode with possible match and outdated flag")
    func candidates() throws {
        let json = """
        {"status":"success","response":{"lastRunAt":"2026-10-01T08:00:00.000Z","isFromCache":true,"candidates":[
          {"id":"k1","suggestedName":"Spotify","detectedFrequency":"monthly","averageAmount":9.99,"currencyCode":"EUR",
           "accountId":"a1","sampleTransactionIds":["t1","t2","t3"],"occurrenceCount":3,"confidenceScore":0.82,
           "medianIntervalDays":30,"status":"pending","detectedAt":"2026-10-01T08:00:00.000Z",
           "possibleMatch":{"id":"s9","name":"Spotify Family"},"isOutdated":false},
          {"id":"k2","suggestedName":"Gym","detectedFrequency":"fortnightly","averageAmount":40,"currencyCode":"EUR",
           "accountId":null,"sampleTransactionIds":[],"occurrenceCount":4,"confidenceScore":0.5,
           "medianIntervalDays":14,"status":"pending","detectedAt":"2026-10-01T08:00:00.000Z",
           "possibleMatch":null,"isOutdated":true}
        ]}}
        """
        let response = try decode(Endpoints.detectRecurringCandidates(), json)
        #expect(response.isFromCache)
        #expect(response.candidates.count == 2)
        #expect(response.candidates[0].averageAmount == Decimal(string: "9.99"))
        #expect(response.candidates[0].possibleMatch?.name == "Spotify Family")
        #expect(response.candidates[1].detectedFrequency == .unknown)
        #expect(response.candidates[1].isOutdated)
    }

    @Test("Pay preview and period responses decode")
    func payPreviewAndPeriod() throws {
        let preview = try decode(Endpoints.recurringPayPreview(id: "s1"), """
        {"status":"success","response":{"isCrossCurrency":true,"accountCurrencyCode":"EUR","subscriptionCurrencyCode":"USD","expectedAmount":10,"convertedAmount":9.2}}
        """)
        #expect(preview.isCrossCurrency)
        #expect(preview.suggestedAmount == Decimal(string: "9.2"))

        let period = try decode(Endpoints.skipRecurringPeriod(id: "s1", periodId: "p2"), """
        {"status":"success","response":{"id":"p2","subscriptionId":"s1","dueDate":"2026-10-15","status":"skipped","paidAt":null,"transactionId":null,"transactionAutoCreated":false,"notes":null}}
        """)
        #expect(period.status == .skipped)
        #expect(!period.isOpen)
    }

    @Test("List request sends sortBy and no isActive filter")
    func listQuery() throws {
        let url = try #require(try request(Endpoints.recurringSubscriptions(sortBy: .amount)).url)
        #expect(url.path().hasSuffix("/api/v1/subscriptions"))
        #expect(url.query() == "sortBy=amount")

        let summaryURL = try #require(try request(Endpoints.recurringSummary(lookbackMonths: 6)).url)
        #expect(summaryURL.query() == "lookbackMonths=6")
    }

    @Test("Quick-add encodes the web payload with a seeded note rule")
    func quickAddBody() throws {
        let today = CalendarDate(year: 2026, month: 10, day: 9)
        let request = RecurringSubscriptionRequest.quickAdd(
            name: "  Netflix ",
            type: .subscription,
            transactionType: .expense,
            amount: Decimal(string: "15.49"),
            currencyCode: "USD",
            frequency: .monthly,
            nextPaymentDate: CalendarDate(year: 2026, month: 10, day: 15),
            maxOccurrences: 12,
            today: today
        )
        let json = try body(Endpoints.createRecurringSubscription(request))
        #expect(json["name"] as? String == "Netflix")
        #expect(json["type"] as? String == "subscription")
        #expect(json["frequency"] as? String == "monthly")
        #expect(json["startDate"] as? String == "2026-10-09")
        #expect(json["dueDate"] as? String == "2026-10-15")
        #expect(json["expectedAmount"] as? Double == 15.49)
        #expect(json["expectedCurrencyCode"] as? String == "USD")
        #expect(json["maxOccurrences"] == nil)
        #expect(json["endDate"] == nil)
        let rules = try #require((json["matchingRules"] as? [String: Any])?["rules"] as? [[String: Any]])
        #expect(rules.first?["field"] as? String == "note")
        #expect(rules.first?["operator"] as? String == "contains_any")
        #expect(rules.first?["value"] as? [String] == ["Netflix"])
    }

    @Test("Quick-add without an amount omits the amount pair")
    func quickAddWithoutAmount() throws {
        let request = RecurringSubscriptionRequest.quickAdd(
            name: "Electricity",
            type: .installment,
            transactionType: .expense,
            amount: 0,
            currencyCode: "USD",
            frequency: .monthly,
            nextPaymentDate: nil,
            maxOccurrences: 6,
            today: CalendarDate(year: 2026, month: 10, day: 9)
        )
        let json = try body(Endpoints.createRecurringSubscription(request))
        #expect(json["expectedAmount"] == nil)
        #expect(json["expectedCurrencyCode"] == nil)
        #expect(json["maxOccurrences"] as? Int == 6)
    }

    @Test("Update sends null for cleared nullable fields")
    func updateBody() throws {
        let update = RecurringSubscriptionRequest(
            name: "Rent",
            type: .bill,
            frequency: .monthly,
            startDate: CalendarDate(year: 2026, month: 1, day: 1),
            accountId: "a1",
            autoRecord: true,
            matchingRules: RecurringMatchingRules(),
            sendsNulls: true
        )
        let endpoint = Endpoints.updateRecurringSubscription(id: "s1", update)
        #expect(try request(endpoint).httpMethod == "PUT")
        let json = try body(endpoint)
        #expect(json["endDate"] is NSNull)
        #expect(json["expectedAmount"] is NSNull)
        #expect(json["categoryId"] is NSNull)
        #expect(json["payeeId"] is NSNull)
        #expect(json["tagIds"] == nil)
        #expect(json["accountId"] as? String == "a1")
        #expect(json["autoRecord"] as? Bool == true)
        #expect((json["matchingRules"] as? [String: Any])?["rules"] as? [Any] != nil)
    }

    @Test("Mark paid omits unset fields; toggle, link, and accept bodies")
    func writeBodies() throws {
        let pay = Endpoints.markRecurringPeriodPaid(
            id: "s1",
            periodId: "p2",
            RecurringMarkPaidRequest(createTransaction: true, amount: Decimal(string: "9.2"), time: Date.iso("2026-10-09T12:00:00.000Z"))
        )
        let payJSON = try body(pay)
        #expect(try request(pay).url?.path().hasSuffix("/subscriptions/s1/periods/p2/pay") == true)
        #expect(payJSON["createTransaction"] as? Bool == true)
        #expect(payJSON["time"] as? String == "2026-10-09T12:00:00.000Z")
        #expect(payJSON["transactionId"] == nil)

        let toggle = try body(Endpoints.toggleRecurringSubscription(id: "s1", isActive: false))
        #expect(toggle["isActive"] as? Bool == false)

        let unlink = Endpoints.unlinkRecurringTransactions(id: "s1", transactionIds: ["t1"])
        #expect(try request(unlink).httpMethod == "DELETE")
        #expect(try body(unlink)["transactionIds"] as? [String] == ["t1"])

        let accept = try body(Endpoints.acceptRecurringCandidate(id: "k1", subscriptionId: "s1"))
        #expect(accept["subscriptionId"] as? String == "s1")
        #expect(try request(Endpoints.acceptRecurringCandidate(id: "k1", subscriptionId: nil)).httpBody == nil)
    }

    @Test("Grouping follows the web: due-date buckets, flat otherwise, paused last")
    func grouping() throws {
        let json = """
        {"status":"success","response":[
          {"id":"a","name":"Overdue","isActive":true,"frequency":"monthly","nextDueDate":"2026-10-01","currentPeriod":{"id":"p","dueDate":"2026-10-01","status":"overdue"}},
          {"id":"b","name":"Soon","isActive":true,"frequency":"monthly","nextDueDate":"2026-10-12"},
          {"id":"c","name":"Month","isActive":true,"frequency":"monthly","nextDueDate":"2026-10-28"},
          {"id":"d","name":"Later","isActive":true,"frequency":"monthly","nextDueDate":"2026-12-01"},
          {"id":"e","name":"None","isActive":true,"frequency":"monthly","nextDueDate":null},
          {"id":"f","name":"Paused","isActive":false,"frequency":"monthly","nextDueDate":"2026-10-10"}
        ]}
        """
        let items = try decode(Endpoints.recurringSubscriptions(sortBy: .dueDate), json)
        let today = CalendarDate(year: 2026, month: 10, day: 9)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let byDue = RecurringGrouping.group(items, sortBy: .dueDate, today: today, calendar: calendar)
        #expect(byDue.map(\.key) == [.overdue, .dueSoon, .thisMonth, .later, .noSchedule, .paused])
        #expect(byDue.map { $0.items.map(\.id) } == [["a"], ["b"], ["c"], ["d"], ["e"], ["f"]])

        let byName = RecurringGrouping.group(items, sortBy: .name, today: today, calendar: calendar)
        #expect(byName.map(\.key) == [.active, .paused])
        #expect(byName[0].items.count == 5)
    }
}
