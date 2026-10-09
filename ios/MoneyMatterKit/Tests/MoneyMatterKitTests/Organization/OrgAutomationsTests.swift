import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Organization: automations")
struct OrgAutomationsTests {
    private let server = try! ServerEndpoint(validating: "https://budget.example.com")

    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try ResponseDecoding.decode(type, from: Data(json.utf8), format: .envelope, decoder: JSONCoding.makeDecoder())
    }

    private func request<Response>(_ endpoint: Endpoint<Response>) throws -> URLRequest {
        try APIClient(server: server).makeRequest(for: endpoint).0
    }

    private func body<Response>(_ endpoint: Endpoint<Response>) throws -> [String: Any] {
        let data = try #require(try request(endpoint).httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let ruleJSON = """
    {"status":"success","response":[{
      "id":"r1","userId":1,"name":"Coffee","isEnabled":true,"position":0,
      "conditions":{"match":"any","items":[
        {"field":"note","operator":"contains_any","value":["coffee","latte"]},
        {"field":"account","operator":"not_in","value":["a1"]},
        {"field":"amount","operator":"between","value":{"min":1.5,"max":20},"currency":{"mode":"specific","code":"EUR"}},
        {"field":"transactionType","operator":"equals","value":"expense"},
        {"field":"dayOfMonth","operator":"between","value":{"min":1,"max":15}},
        {"field":"weather","operator":"is","value":"sunny"}
      ]},
      "actions":[
        {"type":"set_category","categoryId":"c1"},
        {"type":"add_tags","tagIds":["t1","t2"]},
        {"type":"set_note","mode":"append","value":"auto"},
        {"type":"teleport"}
      ],
      "matchCount":12,"lastMatchedAt":"2026-10-01T10:00:00.000Z",
      "pausedReason":{"kind":"missing_reference","refType":"category","refId":"c9","label":"Food","at":"2026-10-02T00:00:00Z"},
      "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"
    }]}
    """

    @Test("A rule decodes every condition and action shape, keeping unknown ones")
    func decodesRule() throws {
        let rules = try decode([OrgAutomation].self, ruleJSON)
        let rule = try #require(rules.first)
        #expect(rule.name == "Coffee")
        #expect(rule.isEnabled)
        #expect(rule.matchCount == 12)
        #expect(rule.lastMatchedAt == Date.iso("2026-10-01T10:00:00.000Z"))
        #expect(rule.pausedReason?.label == "Food")
        #expect(rule.conditions.match == .any)
        #expect(rule.conditions.items.count == 6)
        #expect(rule.conditions.items[0] == .text(field: .note, operator: .containsAny, keywords: ["coffee", "latte"]))
        #expect(rule.conditions.items[1] == .list(field: .account, operator: .notIn, ids: ["a1"]))
        #expect(rule.conditions.items[2] == .amount(operator: .between, min: Decimal(string: "1.5"), max: 20, currency: .specific(code: "EUR")))
        #expect(rule.conditions.items[3] == .transactionType(.expense))
        #expect(rule.conditions.items[4] == .dayOfMonth(min: 1, max: 15))
        #expect(rule.conditions.items[5] == .unknown(field: "weather"))
        #expect(rule.actions == [
            .setCategory(categoryId: "c1"),
            .addTags(tagIds: ["t1", "t2"]),
            .setNote(mode: .append, value: "auto"),
            .unknown(type: "teleport"),
        ])
        #expect(!rule.isFullyEditable)
    }

    @Test("Unknown operators and a missing match decode leniently")
    func decodesLeniently() throws {
        let json = """
        {"status":"success","response":{"id":"r2","name":"X",
          "conditions":{"items":[{"field":"merchant","operator":"sounds_like","value":["a"]}]},
          "actions":[{"type":"set_payee","payeeId":"p1"}]}}
        """
        let rule = try decode(OrgAutomation.self, json)
        #expect(rule.conditions.match == .all)
        #expect(rule.conditions.items == [.text(field: .merchant, operator: .unknown, keywords: ["a"])])
        #expect(rule.actions == [.setPayee(payeeId: "p1")])
        #expect(rule.isEnabled == false)
        #expect(rule.pausedReason == nil)
    }

    @Test("Create sends the union shapes the server's zod schema expects")
    func encodesCreate() throws {
        let payload = OrgAutomationPayload(
            name: "Rent",
            isEnabled: true,
            conditions: OrgAutomationConditions(match: .all, items: [
                .text(field: .merchant, operator: .isEmpty, keywords: []),
                .list(field: .bankConnection, operator: .isIn, ids: ["b1"]),
                .amount(operator: .gte, min: 100, max: nil, currency: .base),
                .transactionType(.income),
                .dayOfMonth(min: 28, max: 31),
            ]),
            actions: [.setPayee(payeeId: "p1"), .setNote(mode: .replace, value: "Rent")]
        )
        let endpoint = Endpoints.orgCreateAutomation(payload)
        #expect(try request(endpoint).httpMethod == "POST")
        #expect(try request(endpoint).url?.path == "/api/v1/automations")

        let json = try body(endpoint)
        #expect(json["name"] as? String == "Rent")
        #expect(json["isEnabled"] as? Bool == true)
        let conditions = try #require(json["conditions"] as? [String: Any])
        #expect(conditions["match"] as? String == "all")
        let items = try #require(conditions["items"] as? [[String: Any]])
        #expect(items[0]["field"] as? String == "merchant")
        #expect(items[0]["operator"] as? String == "is_empty")
        #expect(items[1]["operator"] as? String == "in")
        #expect(items[1]["value"] as? [String] == ["b1"])
        let amountValue = try #require(items[2]["value"] as? [String: Any])
        #expect(amountValue["min"] as? Double == 100)
        #expect(amountValue["max"] == nil)
        #expect((items[2]["currency"] as? [String: Any])?["mode"] as? String == "base")
        #expect(items[3]["operator"] as? String == "equals")
        #expect(items[3]["value"] as? String == "income")
        #expect((items[4]["value"] as? [String: Any])?["min"] as? Int == 28)
        let actions = try #require(json["actions"] as? [[String: Any]])
        #expect(actions[0]["type"] as? String == "set_payee")
        #expect(actions[0]["payeeId"] as? String == "p1")
        #expect(actions[1]["mode"] as? String == "replace")
    }

    @Test("A toggle-only update sends just isEnabled with PATCH")
    func encodesToggle() throws {
        let endpoint = Endpoints.orgUpdateAutomation(id: "r1", OrgAutomationPayload(isEnabled: false))
        let urlRequest = try request(endpoint)
        #expect(urlRequest.httpMethod == "PATCH")
        #expect(urlRequest.url?.path == "/api/v1/automations/r1")
        let json = try body(endpoint)
        #expect(json.keys.sorted() == ["isEnabled"])
        #expect(json["isEnabled"] as? Bool == false)
    }

    @Test("Specific currency encodes its code")
    func encodesSpecificCurrency() throws {
        let data = try JSONCoding.makeEncoder().encode(OrgAutomationAmountCurrency.specific(code: "USD"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(json == ["mode": "specific", "code": "USD"])
    }

    @Test("Unknown conditions refuse to encode")
    func unknownConditionThrows() {
        #expect(throws: EncodingError.self) {
            try JSONCoding.makeEncoder().encode(OrgAutomationCondition.unknown(field: "weather"))
        }
    }

    @Test("Reorder and preview bodies")
    func encodesReorderAndPreview() throws {
        let reorder = try body(Endpoints.orgReorderAutomations(ids: ["b", "a"]))
        #expect(reorder["ids"] as? [String] == ["b", "a"])

        let preview = try body(Endpoints.orgPreviewAutomation(
            conditions: OrgAutomationConditions(items: [.text(field: .note, operator: .containsAny, keywords: ["x"])]),
            limit: 5
        ))
        #expect(preview["limit"] as? Int == 5)
        #expect((preview["conditions"] as? [String: Any])?["match"] as? String == "all")
    }

    @Test("Preview by rule id omits conditions; apply posts the chosen ids")
    func encodesSavedPreviewAndApply() throws {
        let preview = try body(Endpoints.orgPreviewAutomation(automationId: "r1", limit: 500))
        #expect(preview["automationId"] as? String == "r1")
        #expect(preview["conditions"] == nil)
        #expect(preview["limit"] as? Int == 500)

        let apply = Endpoints.orgApplyAutomation(id: "r1", transactionIds: ["t1", "t2"])
        #expect(try request(apply).url?.path == "/api/v1/automations/r1/apply")
        #expect(try body(apply)["transactionIds"] as? [String] == ["t1", "t2"])

        let json = #"{"status":"success","response":{"appliedCount":1,"skippedIds":["t2"],"categorizedAt":"2026-10-01T00:00:00Z"}}"#
        let result = try decode(OrgAutomationApplyResult.self, json)
        #expect(result.appliedCount == 1)
        #expect(result.skippedIds == ["t2"])
    }

    @Test("Preview result decodes counts and matches")
    func decodesPreview() throws {
        let json = """
        {"status":"success","response":{"matchedCount":3,"settledCount":1,"scannedCount":1000,
          "matches":[{"id":"t1","amount":4.5,"time":"2026-10-01T10:00:00.000Z","accountId":"a1","currencyCode":"EUR","transactionType":"expense"}]}}
        """
        let preview = try decode(OrgAutomationPreview.self, json)
        #expect(preview.matchedCount == 3)
        #expect(preview.settledCount == 1)
        #expect(preview.scannedCount == 1000)
        #expect(preview.matches.map(\.id) == ["t1"])
    }

    @Test("Bank connections unwrap the connections key")
    func decodesBankConnections() throws {
        let json = """
        {"status":"success","response":{"connections":[
          {"id":"b1","providerType":"monobank","providerName":"Monobank","isActive":true,"bankName":null},
          {"id":"b2","providerName":"Enable Banking","bankName":"Revolut"}
        ]}}
        """
        let endpoint = Endpoints.orgAutomationBankConnections()
        let connections = try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
        #expect(connections.map(\.displayName) == ["Monobank", "Revolut"])
    }
}
