import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Planning budgets")
struct PlanningBudgetsTests {
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

    // MARK: Decoding

    @Test("Budget list decodes types, categories, share info, and unknown values leniently")
    func budgetList() throws {
        let json = """
        {"status":"success","response":[
          {"id":"b1","userId":1,"name":"Groceries","status":"active","type":"category",
           "startDate":"2026-10-01T00:00:00.000Z","endDate":"2026-10-31T23:59:59.000Z",
           "autoInclude":false,"limitAmount":450.5,
           "categories":[{"id":"c1","name":"Food","color":"#ff0000","parentId":null}]},
          {"id":"b2","userId":1,"name":"Trip","status":"frozen","type":"mystery",
           "startDate":null,"endDate":null,"autoInclude":true,"limitAmount":null,"categories":[],
           "share":{"isOwner":false,"permission":"write","owner":{"id":2,"username":"ana","avatar":null},
                    "policy":null,"accessSource":"direct"}}
        ]}
        """
        let budgets = try decode(Endpoints.planningBudgets(), json)
        #expect(budgets.count == 2)
        #expect(budgets[0].type == .category)
        #expect(budgets[0].limitAmount == Decimal(string: "450.5"))
        #expect(budgets[0].categories.first?.name == "Food")
        #expect(budgets[0].startDate == Date.iso("2026-10-01T00:00:00.000Z"))
        #expect(budgets[0].isOwner)
        #expect(budgets[0].canManage)
        #expect(budgets[1].status == .unknown)
        #expect(budgets[1].type == .unknown)
        #expect(budgets[1].limitAmount == nil)
        #expect(budgets[1].autoInclude)
        #expect(!budgets[1].isOwner)
        #expect(!budgets[1].canManage)
        #expect(budgets[1].canWrite)
        #expect(budgets[1].sharedByHandle == "ana")
    }

    @Test("Stats unwrap the summary and keep a nil utilization rate")
    func stats() throws {
        let json = """
        {"status":"success","response":{"summary":{"actualIncome":10,"actualExpense":250.75,"balance":-240.75,
         "utilizationRate":null,"transactionsCount":4,"firstTransactionDate":"2026-10-02T10:00:00.000Z",
         "lastTransactionDate":null}}}
        """
        let stats = try decode(Endpoints.planningBudgetStats(id: "b1"), json)
        #expect(stats.actualExpense == Decimal(string: "250.75"))
        #expect(stats.balance == Decimal(string: "-240.75"))
        #expect(stats.utilizationRate == nil)
        #expect(stats.transactionsCount == 4)
        #expect(stats.firstTransactionDate == Date.iso("2026-10-02T10:00:00.000Z"))
        #expect(stats.lastTransactionDate == nil)
    }

    @Test("Spending stats decode nested categories and day-precision periods")
    func spendingStats() throws {
        let json = """
        {"status":"success","response":{
          "spendingsByCategory":[{"categoryId":"c1","name":"Food","color":"#f00","amount":120.5,
            "children":[{"categoryId":"c2","name":"Cafe","color":"#0f0","amount":20}]}],
          "spendingOverTime":{"granularity":"weekly","periods":[
            {"periodStart":"2026-10-01","periodEnd":"2026-10-07","expense":80,"income":5}]}}}
        """
        let stats = try decode(Endpoints.planningBudgetSpendingStats(id: "b1"), json)
        #expect(stats.spendingsByCategory.first?.amount == Decimal(string: "120.5"))
        #expect(stats.spendingsByCategory.first?.children.first?.name == "Cafe")
        #expect(stats.granularity == .weekly)
        #expect(stats.periods.first?.periodStart == CalendarDate(year: 2026, month: 10, day: 1))
        #expect(stats.periods.first?.expense == 80)
        #expect(!stats.isEmpty)
    }

    @Test("Category transactions page decodes split rows with their effective amount")
    func categoryTransactions() throws {
        let json = """
        {"status":"success","response":{"transactions":[
          {"id":"t1","time":"2026-10-05T12:00:00.000Z","transactionType":"expense","refAmount":30,"amount":33,
           "note":null,"categoryId":"c1","accountId":"a1","reviewStatus":"reviewed",
           "effectiveCategory":{"id":"c1","name":"Food","color":"#f00"},"effectiveRefAmount":12.5}],
         "total":7}}
        """
        let page = try decode(Endpoints.planningBudgetCategoryTransactions(id: "b1"), json)
        #expect(page.total == 7)
        #expect(page.transactions.first?.budgetAmount == Decimal(string: "12.5"))
        #expect(page.transactions.first?.effectiveCategory?.name == "Food")
        #expect(page.transactions.first?.reviewStatus == .reviewed)
    }

    @Test("Edit tolerates a null response")
    func updateNull() throws {
        let budget = try decode(
            Endpoints.updatePlanningBudget(id: "b1", PlanningBudgetUpdateRequest(name: "X")),
            #"{"status":"success","response":null}"#
        )
        #expect(budget == nil)
    }

    // MARK: Requests

    @Test("List sends comma-joined statuses")
    func listQuery() throws {
        let url = try #require(try request(Endpoints.planningBudgets(statuses: [.active, .archived])).url)
        #expect(url.absoluteString == "https://budget.example.com/api/v1/budgets?status=active,archived")
    }

    @Test("Category transactions clamp the page size")
    func categoryTransactionsQuery() throws {
        let url = try #require(try request(Endpoints.planningBudgetCategoryTransactions(id: "b1", from: 50, limit: 500)).url)
        #expect(url.absoluteString == "https://budget.example.com/api/v1/budgets/b1/category-transactions?from=50&limit=100")
    }

    @Test("Create encodes dates as timestamps and a missing limit as null")
    func createBody() throws {
        let request = PlanningBudgetCreateRequest(
            name: "Groceries",
            type: .category,
            categoryIds: ["c1", "c2"],
            startDate: Date.iso("2026-10-01T00:00:00.000Z"),
            autoInclude: false,
            limitAmount: 0
        )
        let endpoint = Endpoints.createPlanningBudget(request)
        #expect(try self.request(endpoint).httpMethod == "POST")
        let body = try body(endpoint)
        #expect(body["name"] as? String == "Groceries")
        #expect(body["type"] as? String == "category")
        #expect(body["categoryIds"] as? [String] == ["c1", "c2"])
        #expect(body["startDate"] as? String == "2026-10-01T00:00:00.000Z")
        #expect(body["endDate"] == nil)
        #expect(body["autoInclude"] as? Bool == false)
        #expect(body["limitAmount"] is NSNull)
    }

    @Test("Edit omits unchanged fields and a non-positive limit")
    func updateBody() throws {
        let endpoint = Endpoints.updatePlanningBudget(
            id: "b1",
            PlanningBudgetUpdateRequest(name: "Food", autoInclude: true, limitAmount: 0)
        )
        #expect(try request(endpoint).httpMethod == "PUT")
        let body = try body(endpoint)
        #expect(body["name"] as? String == "Food")
        #expect(body["autoInclude"] as? Bool == true)
        #expect(body["limitAmount"] == nil)
        #expect(body["categoryIds"] == nil)

        let withLimit = try self.body(Endpoints.updatePlanningBudget(id: "b1", PlanningBudgetUpdateRequest(limitAmount: 99.9)))
        #expect((withLimit["limitAmount"] as? NSNumber)?.decimalValue == Decimal(string: "99.9"))
    }

    @Test("Archive, add, and remove send the right method and body")
    func mutations() throws {
        let archive = Endpoints.setPlanningBudgetArchived(id: "b1", isArchived: true)
        #expect(try request(archive).httpMethod == "PATCH")
        #expect(try body(archive)["isArchived"] as? Bool == true)

        let add = Endpoints.addTransactionsToPlanningBudget(id: "b1", transactionIds: ["t1", "t2", "t1"])
        #expect(try request(add).httpMethod == "POST")
        #expect(try body(add)["transactionIds"] as? [String] == ["t1", "t2"])

        let remove = Endpoints.removeTransactionsFromPlanningBudget(id: "b1", transactionIds: ["t3"])
        #expect(try request(remove).httpMethod == "DELETE")
        #expect(try request(remove).url?.path == "/api/v1/budgets/b1/transactions")
        #expect(try body(remove)["transactionIds"] as? [String] == ["t3"])

        #expect(try request(Endpoints.deletePlanningBudget(id: "b1")).httpMethod == "DELETE")
    }
}
