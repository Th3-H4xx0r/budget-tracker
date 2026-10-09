import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Planned budgets")
struct PlannedBudgetsTests {
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

    private let planJSON = """
    {"id":"p1","name":"October","type":"category","status":"archived","startDate":"2026-10-01",
     "endDate":"2026-10-31","salaryAmount":2500.5,"salaryFrequency":"biweekly","salaryIntervalDays":null,
     "salaryAnchorDate":"2026-10-03","salaryCategoryId":"c-salary","salaryProfileRevision":2,
     "dismissedSalaryProfileRevision":null,"autoAddSyncedTransactions":true,"userId":7}
    """

    @Test("Plan list decodes dates, money, and lenient enums")
    func planList() throws {
        let json = """
        {"status":"success","response":[\(planJSON),
         {"id":"p2","name":"Trip","type":"vacation","status":"active","startDate":"2026-11-01",
          "endDate":"2026-11-10","salaryAmount":0,"salaryFrequency":"fortnightly"}]}
        """
        let plans = try decode(Endpoints.plannedBudgets(), json)
        #expect(plans.count == 2)
        let first = plans[0]
        #expect(first.type == .category)
        #expect(first.isArchived)
        #expect(first.startDate == CalendarDate(year: 2026, month: 10, day: 1))
        #expect(first.salaryAmount == Decimal(string: "2500.5"))
        #expect(first.salaryFrequency == .biweekly)
        #expect(first.salaryAnchorDate == CalendarDate(year: 2026, month: 10, day: 3))
        #expect(first.autoAddSyncedTransactions)
        #expect(plans[1].type == .unknown)
        #expect(plans[1].salaryFrequency == .unknown)
        #expect(plans[1].autoAddSyncedTransactions == false)
    }

    @Test("Plan details decode entries, overrides, occurrences, and summary")
    func details() throws {
        let json = """
        {"status":"success","response":{
          "plan":\(planJSON),
          "categoryIds":["c1"],
          "entries":[{"id":"e1","planId":"p1","transactionType":"expense","amount":40,"date":"2026-10-05",
                      "categoryId":"c1","note":"Gift","frequency":"weekly","intervalDays":null}],
          "overrides":[{"id":"o1","planId":"p1","subscriptionId":"s1","isIncluded":false,"amount":12.99,
                        "categoryId":null,"nextOccurrenceDate":"2026-10-15"}],
          "occurrences":[
            {"source":"salary","transactionType":"income","amount":2500.5,"date":"2026-10-03","categoryId":"c-salary","note":"Salary"},
            {"source":"recurring","subscriptionId":"s2","name":"Netflix","transactionType":"expense","amount":15.49,"date":"2026-10-04","categoryId":"c1"},
            {"source":"manual","id":"e1","transactionType":"expense","amount":40,"date":"2026-10-05","categoryId":"c1","note":"Gift","frequency":"weekly"}
          ],
          "summary":{"income":2500.5,"expense":55.49,"net":2445.01},
          "salaryProfileChanged":true,
          "salarySettings":{"salaryAmount":3000,"salaryFrequency":"monthly","salaryIntervalDays":null,
                            "salaryAnchorDate":null,"salaryCategoryId":null,"revision":3}
        }}
        """
        let details = try decode(Endpoints.plannedBudgetDetails(id: "p1"), json)
        #expect(details.plan.id == "p1")
        #expect(details.categoryIds == ["c1"])
        #expect(details.entries.first?.frequency == .weekly)
        #expect(details.entry(id: "e1")?.note == "Gift")
        #expect(details.overrides.first?.isIncluded == false)
        #expect(details.overrides.first?.amount == Decimal(string: "12.99"))
        #expect(details.occurrences.map(\.source) == [.salary, .recurring, .manual])
        #expect(details.occurrences[0].id == nil)
        #expect(details.occurrences[1].subscriptionId == "s2")
        #expect(details.occurrences[1].signedAmount == Decimal(string: "-15.49"))
        #expect(details.summary.net == Decimal(string: "2445.01"))
        #expect(details.salaryProfileChanged)
        #expect(details.salarySettings?.revision == 3)
        #expect(details.salarySettings?.salaryAnchorDate == nil)
    }

    @Test("Salary settings decode with defaults for missing fields")
    func salarySettings() throws {
        let json = #"{"status":"success","response":{"salaryAmount":1800,"salaryFrequency":"custom","salaryIntervalDays":10,"revision":4}}"#
        let settings = try decode(Endpoints.plannedBudgetSalarySettings(), json)
        #expect(settings.salaryAmount == 1800)
        #expect(settings.salaryFrequency == .custom)
        #expect(settings.salaryIntervalDays == 10)
        #expect(settings.salaryCategoryId == nil)
        #expect(settings.revision == 4)
    }

    @Test("Delete endpoints accept a body without a response")
    func deleteDecodes() throws {
        _ = try decode(Endpoints.deletePlannedBudget(id: "p1"), #"{"status":"success"}"#)
        let request = try request(Endpoints.deletePlannedBudgetEntry(planId: "p1", entryId: "e1"))
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/v1/future-budgets/p1/entries/e1")
    }

    @Test("Create request sends categories only for category plans and nulls unset salary fields")
    func createRequest() throws {
        let salary = PlannedBudgetSalaryProfile(
            salaryAmount: Decimal(string: "1200.75")!,
            salaryFrequency: .monthly,
            salaryIntervalDays: 14,
            salaryAnchorDate: CalendarDate(year: 2026, month: 10, day: 25)
        )
        let manual = PlannedBudgetCreateRequest(
            name: "  October  ",
            type: .manual,
            categoryIds: ["c1"],
            startDate: CalendarDate(year: 2026, month: 10, day: 1),
            endDate: CalendarDate(year: 2026, month: 10, day: 31),
            salary: salary
        )
        let endpoint = Endpoints.createPlannedBudget(manual)
        #expect(try request(endpoint).httpMethod == "POST")
        let json = try body(endpoint)
        #expect(json["name"] as? String == "October")
        #expect(json["type"] as? String == "manual")
        #expect((json["categoryIds"] as? [String])?.isEmpty == true)
        #expect(json["startDate"] as? String == "2026-10-01")
        #expect(json["salaryAmount"] as? Double == 1200.75)
        #expect(json["salaryFrequency"] as? String == "monthly")
        #expect(json["salaryIntervalDays"] is NSNull)
        #expect(json["salaryAnchorDate"] as? String == "2026-10-25")
        #expect(json["salaryCategoryId"] is NSNull)

        var category = manual
        category.type = .category
        category.salary.salaryFrequency = .custom
        let categoryJSON = try body(Endpoints.createPlannedBudget(category))
        #expect(categoryJSON["categoryIds"] as? [String] == ["c1"])
        #expect(categoryJSON["salaryIntervalDays"] as? Int == 14)
    }

    @Test("Salary settings request sends the full profile")
    func salarySettingsRequest() throws {
        let profile = PlannedBudgetSalaryProfile(salaryAmount: 900, salaryFrequency: .semiAnnual, salaryCategoryId: "c9")
        let endpoint = Endpoints.updatePlannedBudgetSalarySettings(PlannedBudgetSalarySettingsRequest(profile: profile))
        #expect(try request(endpoint).httpMethod == "PUT")
        let json = try body(endpoint)
        #expect(json["salaryAmount"] as? Int == 900)
        #expect(json["salaryFrequency"] as? String == "semi_annual")
        #expect(json["salaryCategoryId"] as? String == "c9")
        #expect(json["salaryAnchorDate"] is NSNull)
    }

    @Test("Update request leaves out nil fields")
    func updateRequest() throws {
        let json = try body(Endpoints.updatePlannedBudget(id: "p1", PlannedBudgetUpdateRequest(status: .archived)))
        #expect(json.count == 1)
        #expect(json["status"] as? String == "archived")
        let toggle = try body(Endpoints.updatePlannedBudget(id: "p1", PlannedBudgetUpdateRequest(autoAddSyncedTransactions: false)))
        #expect(toggle["autoAddSyncedTransactions"] as? Bool == false)
    }

    @Test("Entry request sends nulls for one-time entries and trims notes")
    func entryRequest() throws {
        let once = PlannedBudgetEntryRequest(
            transactionType: .expense,
            amount: Decimal(string: "45.5")!,
            date: CalendarDate(year: 2026, month: 10, day: 12),
            note: "   ",
            intervalDays: 3
        )
        let json = try body(Endpoints.createPlannedBudgetEntry(planId: "p1", once))
        #expect(json["transactionType"] as? String == "expense")
        #expect(json["amount"] as? Double == 45.5)
        #expect(json["date"] as? String == "2026-10-12")
        #expect(json["categoryId"] is NSNull)
        #expect(json["note"] is NSNull)
        #expect(json["frequency"] is NSNull)
        #expect(json["intervalDays"] is NSNull)

        var custom = once
        custom.frequency = .custom
        custom.note = " Rent "
        let update = Endpoints.updatePlannedBudgetEntry(planId: "p1", entryId: "e1", custom)
        #expect(try request(update).url?.path == "/api/v1/future-budgets/p1/entries/e1")
        let customJSON = try body(update)
        #expect(customJSON["frequency"] as? String == "custom")
        #expect(customJSON["intervalDays"] as? Int == 3)
        #expect(customJSON["note"] as? String == "Rent")
    }

    @Test("Recurring override request sends only the changed field")
    func recurringOverride() throws {
        let exclude = Endpoints.updatePlannedBudgetRecurring(
            planId: "p1", subscriptionId: "s1", PlannedBudgetRecurringOverrideRequest(isIncluded: false)
        )
        #expect(try request(exclude).url?.path == "/api/v1/future-budgets/p1/recurring/s1")
        let excludeJSON = try body(exclude)
        #expect(excludeJSON.count == 1)
        #expect(excludeJSON["isIncluded"] as? Bool == false)

        let clear = try body(Endpoints.updatePlannedBudgetRecurring(
            planId: "p1", subscriptionId: "s1",
            PlannedBudgetRecurringOverrideRequest(
                categoryId: .clear,
                nextOccurrenceDate: .set(CalendarDate(year: 2026, month: 10, day: 20))
            )
        ))
        #expect(clear["categoryId"] is NSNull)
        #expect(clear["nextOccurrenceDate"] as? String == "2026-10-20")
        #expect(clear["amount"] == nil)
    }

    @Test("Salary change resolution posts the choice")
    func salaryChoice() throws {
        let endpoint = Endpoints.resolvePlannedBudgetSalaryChange(id: "p1", apply: true)
        #expect(try request(endpoint).url?.path == "/api/v1/future-budgets/p1/salary-profile")
        #expect(try body(endpoint)["apply"] as? Bool == true)
    }
}
