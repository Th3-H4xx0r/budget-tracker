import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Organization: transaction groups")
struct OrgTransactionGroupsTests {
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

    @Test("The list decodes counts, raw date ranges, and optional fields")
    func decodesList() throws {
        let json = """
        {"status":"success","response":[
          {"id":"g1","name":"Trip","note":"Paris","createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-02T00:00:00.000Z",
           "transactionCount":3,"dateFrom":"2026-08-01 10:00:00+00","dateTo":"2026-08-05T12:00:00.000Z"},
          {"id":"g2","name":"Split","note":null,"createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z","transactionCount":"2"}
        ]}
        """
        let groups = try decode([OrgTxGroup].self, json)
        #expect(groups.count == 2)
        #expect(groups[0].note == "Paris")
        #expect(groups[0].count == 3)
        #expect(groups[0].startDate == Date.iso("2026-08-01T10:00:00Z"))
        #expect(groups[0].endDate == Date.iso("2026-08-05T12:00:00.000Z"))
        #expect(groups[1].note == nil)
        #expect(groups[1].count == 2)
        #expect(groups[1].startDate == nil)
        #expect(groups[1].transactions == nil)
    }

    @Test("Detail decodes its transactions")
    func decodesDetail() throws {
        let json = """
        {"status":"success","response":{"id":"g1","name":"Trip","note":null,
          "transactions":[
            {"id":"t1","amount":10,"time":"2026-08-01T10:00:00.000Z","accountId":"a1","currencyCode":"EUR","transactionType":"expense"},
            {"id":"t2","amount":12,"time":"2026-08-02T10:00:00.000Z","accountId":"a1","currencyCode":"EUR","transactionType":"expense"}
          ]}}
        """
        let group = try decode(OrgTxGroup.self, json)
        #expect(group.transactions?.map(\.id) == ["t1", "t2"])
        #expect(group.count == 2)
    }

    @Test("Removal decodes a dissolved group")
    func decodesRemoval() throws {
        let dissolved = try decode(OrgTxGroupRemoval.self, #"{"status":"success","response":{"group":null,"dissolved":true}}"#)
        #expect(dissolved.dissolved)
        #expect(dissolved.group == nil)

        let kept = try decode(
            OrgTxGroupRemoval.self,
            #"{"status":"success","response":{"group":{"id":"g1","name":"Trip","note":null},"dissolved":false}}"#
        )
        #expect(!kept.dissolved)
        #expect(kept.group?.id == "g1")
    }

    @Test("Create sends name, a null note, and the ids")
    func encodesCreate() throws {
        let endpoint = Endpoints.orgCreateTxGroup(OrgTxGroupCreateRequest(name: "Trip", note: "", transactionIds: ["t1", "t2"]))
        #expect(try request(endpoint).httpMethod == "POST")
        #expect(try request(endpoint).url?.path == "/api/v1/transaction-groups")
        let json = try body(endpoint)
        #expect(json["name"] as? String == "Trip")
        #expect(json["note"] is NSNull)
        #expect(json["transactionIds"] as? [String] == ["t1", "t2"])
    }

    @Test("Update leaves an unchanged note out and sends null to clear it")
    func encodesUpdate() throws {
        let renamed = try body(Endpoints.orgUpdateTxGroup(id: "g1", OrgTxGroupUpdateRequest(name: "New")))
        #expect(renamed.keys.sorted() == ["name"])

        let cleared = try body(Endpoints.orgUpdateTxGroup(id: "g1", OrgTxGroupUpdateRequest(note: .clear)))
        #expect(cleared["note"] is NSNull)

        let set = try body(Endpoints.orgUpdateTxGroup(id: "g1", OrgTxGroupUpdateRequest(note: .set("Hi"))))
        #expect(set["note"] as? String == "Hi")
        #expect(try request(Endpoints.orgUpdateTxGroup(id: "g1", OrgTxGroupUpdateRequest())).httpMethod == "PUT")
    }

    @Test("Membership changes hit the transactions sub-route; force only when set")
    func encodesMembership() throws {
        let add = Endpoints.orgAddTransactionsToTxGroup(groupId: "g1", transactionIds: ["t3"])
        #expect(try request(add).httpMethod == "POST")
        #expect(try request(add).url?.path == "/api/v1/transaction-groups/g1/transactions")
        #expect(try body(add)["transactionIds"] as? [String] == ["t3"])

        let remove = Endpoints.orgRemoveTransactionsFromTxGroup(groupId: "g1", transactionIds: ["t1"])
        #expect(try request(remove).httpMethod == "DELETE")
        #expect(try body(remove)["force"] == nil)

        let forced = Endpoints.orgRemoveTransactionsFromTxGroup(groupId: "g1", transactionIds: ["t1"], force: true)
        #expect(try body(forced)["force"] as? Bool == true)
    }

    @Test("The list sends includeTransactions only when asked")
    func listQuery() throws {
        #expect(try request(Endpoints.orgTxGroups()).url?.query == nil)
        #expect(try request(Endpoints.orgTxGroups(includeTransactions: true)).url?.query == "includeTransactions=true")
    }
}
