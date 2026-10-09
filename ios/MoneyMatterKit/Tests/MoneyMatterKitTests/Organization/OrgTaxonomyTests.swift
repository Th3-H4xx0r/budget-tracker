import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Organization: categories and tags")
struct OrgTaxonomyTests {
    private let server = try! ServerEndpoint(validating: "https://budget.example.com")

    private func request<Response>(_ endpoint: Endpoint<Response>) throws -> URLRequest {
        try APIClient(server: server).makeRequest(for: endpoint).0
    }

    private func body<Response>(_ endpoint: Endpoint<Response>) throws -> [String: Any] {
        let data = try #require(try request(endpoint).httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode<Response>(_ endpoint: Endpoint<Response>, json: String) throws -> Response {
        try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
    }

    // MARK: Categories

    @Test("Create category sends name, colour, icon, and parent")
    func createCategory() throws {
        let endpoint = Endpoints.orgCreateCategory(
            OrgCategoryCreateRequest(name: "Coffee", color: "#aa5500", icon: "drink-coffee-20-filled", parentId: "p1")
        )
        let request = try request(endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v1/categories")
        let json = try body(endpoint)
        #expect(json["name"] as? String == "Coffee")
        #expect(json["color"] as? String == "#aa5500")
        #expect(json["icon"] as? String == "drink-coffee-20-filled")
        #expect(json["parentId"] as? String == "p1")
    }

    @Test("Root category leaves parentId out")
    func createRootCategory() throws {
        let json = try body(Endpoints.orgCreateCategory(
            OrgCategoryCreateRequest(name: "Food", color: "#112233", icon: nil, parentId: nil)
        ))
        #expect(json["parentId"] == nil)
        #expect(json["icon"] == nil)
    }

    @Test("Update category sends null to clear parent and icon, omits unchanged fields")
    func updateCategory() throws {
        let endpoint = Endpoints.orgUpdateCategory(
            id: "c1",
            OrgCategoryUpdateRequest(name: "Dining", icon: .clear, parentId: .clear)
        )
        let request = try request(endpoint)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/v1/categories/c1")
        let json = try body(endpoint)
        #expect(json["name"] as? String == "Dining")
        #expect(json["color"] == nil)
        #expect(json["icon"] is NSNull)
        #expect(json["parentId"] is NSNull)

        let moved = try body(Endpoints.orgUpdateCategory(id: "c1", OrgCategoryUpdateRequest(parentId: .set("p2"))))
        #expect(moved["parentId"] as? String == "p2")
        #expect(moved["name"] == nil)
    }

    @Test("Delete category carries the replacement only when given")
    func deleteCategory() throws {
        let plain = try request(Endpoints.orgDeleteCategory(id: "c1"))
        #expect(plain.httpMethod == "DELETE")
        #expect(plain.httpBody == nil)

        let json = try body(Endpoints.orgDeleteCategory(id: "c1", replaceWithCategoryId: "c2"))
        #expect(json["replaceWithCategoryId"] as? String == "c2")
    }

    @Test("Transaction count unwraps to an Int")
    func transactionCount() throws {
        let endpoint = Endpoints.orgCategoryTransactionCount(id: "c1")
        #expect(try request(endpoint).url?.path == "/api/v1/categories/c1/transaction-count")
        let count = try decode(endpoint, json: #"{"status":"success","response":{"transactionCount":12}}"#)
        #expect(count == 12)
    }

    // MARK: Tags

    @Test("Tag request sends null for an empty icon and description")
    func tagRequest() throws {
        let json = try body(Endpoints.orgCreateTag(
            OrgTagRequest(name: "Trip", color: "#ff0000", icon: nil, description: nil)
        ))
        #expect(json["name"] as? String == "Trip")
        #expect(json["color"] as? String == "#ff0000")
        #expect(json["icon"] is NSNull)
        #expect(json["description"] is NSNull)

        let update = Endpoints.orgUpdateTag(
            id: "t1",
            OrgTagRequest(name: "Trip", color: "#ff0000", icon: "airplane-20-filled", description: "Italy")
        )
        #expect(try request(update).httpMethod == "PUT")
        #expect(try request(update).url?.path == "/api/v1/tags/t1")
        #expect(try body(update)["description"] as? String == "Italy")
    }

    // MARK: Tag reminders

    @Test("Reminders decode settings, frequency, and unknown values")
    func decodeReminders() throws {
        let json = """
        {"status":"success","response":[
          {"id":"r1","userId":1,"tagId":"t1","type":"amount_threshold","frequency":"monthly","dayOfMonth":15,
           "settings":{"amountThreshold":250.5},"isEnabled":true,"lastCheckedAt":null,
           "lastTriggeredAt":"2026-10-01T08:00:00.000Z","createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"},
          {"id":"r2","tagId":"t1","type":"existence_check","frequency":null,"dayOfMonth":null,"settings":{},"isEnabled":false},
          {"id":"r3","tagId":"t1","type":"brand_new","frequency":"hourly","settings":null}
        ]}
        """
        let reminders = try decode(Endpoints.orgTagReminders(tagId: "t1"), json: json)
        #expect(reminders.count == 3)
        #expect(reminders[0].type == .amountThreshold)
        #expect(reminders[0].frequency == .monthly)
        #expect(reminders[0].dayOfMonth == 15)
        #expect(reminders[0].amountThreshold == Decimal(string: "250.5"))
        #expect(reminders[0].lastTriggeredAt != nil)
        #expect(reminders[1].type == .existenceCheck)
        #expect(reminders[1].frequency == nil)
        #expect(reminders[1].amountThreshold == nil)
        #expect(reminders[1].isEnabled == false)
        #expect(reminders[2].type == .unknown)
        #expect(reminders[2].frequency == .unknown)
        #expect(reminders[2].isEnabled == true)
    }

    @Test("Real-time threshold reminder sends null frequency and day, threshold in settings")
    func encodeRealTimeReminder() throws {
        let endpoint = Endpoints.orgCreateTagReminder(
            tagId: "t1",
            OrgTagReminderRequest(type: .amountThreshold, frequency: nil, dayOfMonth: 10, amountThreshold: Decimal(string: "99.99"), isEnabled: true)
        )
        let request = try request(endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v1/tags/t1/reminders")
        let json = try body(endpoint)
        #expect(json["type"] as? String == "amount_threshold")
        #expect(json["frequency"] is NSNull)
        #expect(json["dayOfMonth"] is NSNull)
        let settings = try #require(json["settings"] as? [String: Any])
        #expect((settings["amountThreshold"] as? NSNumber)?.doubleValue == 99.99)
        #expect(json["isEnabled"] as? Bool == true)
    }

    @Test("Monthly existence check sends the day and empty settings")
    func encodeMonthlyExistenceCheck() throws {
        let endpoint = Endpoints.orgUpdateTagReminder(
            tagId: "t1",
            id: "r1",
            OrgTagReminderRequest(type: .existenceCheck, frequency: .monthly, dayOfMonth: 31, amountThreshold: 5, isEnabled: false)
        )
        #expect(try request(endpoint).httpMethod == "PUT")
        #expect(try request(endpoint).url?.path == "/api/v1/tags/t1/reminders/r1")
        let json = try body(endpoint)
        #expect(json["frequency"] as? String == "monthly")
        #expect(json["dayOfMonth"] as? Int == 31)
        let settings = try #require(json["settings"] as? [String: Any])
        #expect(settings.isEmpty)
        #expect(json["isEnabled"] as? Bool == false)
    }

    @Test("Weekly reminder drops the day of month")
    func weeklyDropsDay() throws {
        let json = try body(Endpoints.orgCreateTagReminder(
            tagId: "t1",
            OrgTagReminderRequest(type: .existenceCheck, frequency: .weekly, dayOfMonth: 3, amountThreshold: nil, isEnabled: true)
        ))
        #expect(json["dayOfMonth"] is NSNull)
    }

    @Test("Delete reminder path")
    func deleteReminder() throws {
        let request = try request(Endpoints.orgDeleteTagReminder(tagId: "t1", id: "r9"))
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/v1/tags/t1/reminders/r9")
    }
}
