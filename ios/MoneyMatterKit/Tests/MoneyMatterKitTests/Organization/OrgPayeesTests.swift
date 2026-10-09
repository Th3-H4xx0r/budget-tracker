import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Organization: payees")
struct OrgPayeesTests {
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

    @Test("Payee list rows decode with stats and lenient mode")
    func decodesPayeeList() throws {
        let json = """
        {"status":"success","response":[
          {"id":"p1","userId":1,"name":"Netflix","normalizedName":"netflix","defaultCategoryId":"c1",
           "categorizationMode":"hint","defaultTagIds":["t1","t2"],"logoDomain":"netflix.com","logoInitials":null,
           "logoColor":null,"logoSource":"auto","createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-02T00:00:00.000Z",
           "stats":{"payeeId":"p1","transactionCount":12,"netFlowRef":-155.5,"firstSeenAt":"2025-01-05T10:00:00.000Z",
                    "lastSeenAt":"2026-09-30T10:00:00.000Z","topCategoryId":"c2"}},
          {"id":"p2","name":"Corner Shop","defaultCategoryId":null,"categorizationMode":"someday","defaultTagIds":[],
           "logoDomain":null,"logoInitials":"CS","logoColor":"#ff8800","logoSource":"manual","stats":null}
        ]}
        """
        let payees = try decode(Endpoints.orgPayees(), json)
        #expect(payees.count == 2)
        let netflix = payees[0]
        #expect(netflix.name == "Netflix")
        #expect(netflix.categorizationMode == .hint)
        #expect(netflix.defaultTagIds == ["t1", "t2"])
        #expect(netflix.logoDomain == "netflix.com")
        #expect(netflix.stats?.transactionCount == 12)
        #expect(netflix.stats?.netFlowRef == Decimal(string: "-155.5"))
        #expect(netflix.stats?.lastSeenAt == Date.iso("2026-09-30T10:00:00.000Z"))
        #expect(netflix.displayCategoryId == "c1")
        let shop = payees[1]
        #expect(shop.categorizationMode == .unknown)
        #expect(shop.stats == nil)
        #expect(shop.logoInitials == "CS")
        #expect(shop.displayCategoryId == nil)
    }

    @Test("Payee detail decodes aliases, including the canonical one")
    func decodesPayeeDetail() throws {
        let json = """
        {"status":"success","response":{"id":"p1","name":"Amazon","categorizationMode":"enforce",
          "defaultTagIds":[],"aliases":[
            {"id":"a1","payeeId":"p1","rawName":"Amazon","normalizedName":"amazon","isCanonical":true,"createdAt":"2026-01-01T00:00:00.000Z"},
            {"id":"a2","payeeId":"p1","rawName":"AMZN Mktp US","normalizedName":"amzn mktp us","isCanonical":false,"createdAt":"2026-01-01T00:00:00.000Z"}
          ],
          "stats":{"payeeId":"p1","transactionCount":3,"netFlowRef":-42,"firstSeenAt":null,"lastSeenAt":null,"topCategoryId":"c9"}}}
        """
        let payee = try decode(Endpoints.orgPayee(id: "p1"), json)
        #expect(payee.aliases?.count == 2)
        #expect(payee.aliases?.first?.isCanonical == true)
        #expect(payee.aliases?.last?.rawName == "AMZN Mktp US")
        #expect(payee.displayCategoryId == "c9")
        #expect(payee.stats?.firstSeenAt == nil)
    }

    @Test("Ignored names, settings, and write results decode")
    func decodesSmallResponses() throws {
        let ignored = try decode(
            Endpoints.orgPayeeIgnoredNames(),
            #"{"status":"success","response":[{"id":"i1","normalizedName":"atm withdrawal","rawSample":"ATM Withdrawal","createdAt":"2026-02-01T00:00:00.000Z"},{"id":"i2","normalizedName":"pos","rawSample":null,"createdAt":"2026-02-01T00:00:00.000Z"}]}"#
        )
        #expect(ignored.map(\.displayName) == ["ATM Withdrawal", "pos"])

        let settings = try decode(
            Endpoints.orgPayeeUserSettings(),
            #"{"status":"success","response":{"locale":"en","payeeExtractionUsesDescription":true,"payeePromotionThreshold":3,"ai":{"features":[]}}}"#
        )
        #expect(settings.payeeExtractionUsesDescription)
        #expect(settings.payeePromotionThreshold == 3)

        let defaults = try decode(Endpoints.orgPayeeUserSettings(), #"{"status":"success","response":{"locale":"en"}}"#)
        #expect(!defaults.payeeExtractionUsesDescription)
        #expect(defaults.payeePromotionThreshold == 2)

        let applied = try decode(Endpoints.orgApplyPayeeTags(id: "p1"), #"{"status":"success","response":{"updatedTransactionsCount":7}}"#)
        #expect(applied.updatedTransactionsCount == 7)
        let bulk = try decode(Endpoints.orgBulkPayeeCategorizationMode(.off), #"{"status":"success","response":{"updatedCount":40}}"#)
        #expect(bulk.updatedCount == 40)
        let ignoredDelete = try decode(Endpoints.orgDeletePayeeAndIgnore(id: "p1"), #"{"status":"success","response":{"ignoredAddedCount":2}}"#)
        #expect(ignoredDelete.ignoredAddedCount == 2)
        _ = try decode(Endpoints.orgDeletePayee(id: "p1"), "")
    }

    // MARK: Requests

    @Test("List query sends sort, search, and paging")
    func listQuery() throws {
        let url = try #require(try request(Endpoints.orgPayees(query: " net ", sortBy: .netFlow, sortDir: .asc, limit: 50, offset: 100)).url)
        #expect(url.path() == "/api/v1/payees")
        let query = try #require(url.query())
        #expect(query.contains("q=net"))
        #expect(query.contains("sortBy=netFlow"))
        #expect(query.contains("sortDir=asc"))
        #expect(query.contains("limit=50"))
        #expect(query.contains("offset=100"))
        #expect(OrgPayeeSortField.name.defaultDirection == .asc)
        #expect(OrgPayeeSortField.transactionCount.defaultDirection == .desc)
    }

    @Test("Update body sends set and cleared fields, omits unchanged ones")
    func updateBody() throws {
        let endpoint = Endpoints.orgUpdatePayee(
            id: "p1",
            OrgPayeeWriteRequest(
                name: "Netflix",
                defaultCategoryId: .clear,
                categorizationMode: .hint,
                defaultTagIds: ["t1"],
                logoDomain: .clear,
                logoInitials: .set("NF"),
                logoColor: .set("#e50914")
            )
        )
        let req = try request(endpoint)
        #expect(req.httpMethod == "PATCH")
        #expect(req.url?.path() == "/api/v1/payees/p1")
        let json = try body(endpoint)
        #expect(json["name"] as? String == "Netflix")
        #expect(json["defaultCategoryId"] is NSNull)
        #expect(json["categorizationMode"] as? String == "hint")
        #expect(json["defaultTagIds"] as? [String] == ["t1"])
        #expect(json["logoDomain"] is NSNull)
        #expect(json["logoInitials"] as? String == "NF")
        #expect(json["logoColor"] as? String == "#e50914")

        let minimal = try body(Endpoints.orgUpdatePayee(id: "p1", OrgPayeeWriteRequest(defaultTagIds: [])))
        #expect(minimal.keys.sorted() == ["defaultTagIds"])
    }

    @Test("Create, merge, alias, ignored-name, and settings bodies")
    func otherBodies() throws {
        let create = try body(Endpoints.orgCreatePayee(OrgPayeeWriteRequest(name: "Gym", defaultCategoryId: .set("c1"))))
        #expect(create["name"] as? String == "Gym")
        #expect(create["defaultCategoryId"] as? String == "c1")
        #expect(create["logoDomain"] == nil)

        let merge = Endpoints.orgMergePayee(sourceId: "p1", targetPayeeId: "p2")
        #expect(try request(merge).url?.path() == "/api/v1/payees/p1/merge")
        #expect(try body(merge)["targetPayeeId"] as? String == "p2")

        let alias = Endpoints.orgCreatePayeeAlias(payeeId: "p1", rawName: "AMZN")
        #expect(try request(alias).url?.path() == "/api/v1/payees/p1/aliases")
        #expect(try body(alias)["rawName"] as? String == "AMZN")

        let deleteAlias = try request(Endpoints.orgDeletePayeeAlias(payeeId: "p1", aliasId: "a2"))
        #expect(deleteAlias.httpMethod == "DELETE")
        #expect(deleteAlias.url?.path() == "/api/v1/payees/p1/aliases/a2")

        let ignore = try body(Endpoints.orgAddPayeeIgnoredName(rawName: "POS"))
        #expect(ignore["rawName"] as? String == "POS")
        #expect(ignore["force"] == nil)
        let forced = try body(Endpoints.orgAddPayeeIgnoredName(rawName: "POS", force: true))
        #expect(forced["force"] as? Bool == true)

        let deleteIgnore = try request(Endpoints.orgDeletePayeeAndIgnore(id: "p1"))
        #expect(deleteIgnore.url?.query()?.contains("ignoreFuture=true") == true)

        let bulk = try body(Endpoints.orgBulkPayeeCategorizationMode(.off))
        #expect(bulk["mode"] as? String == "off")

        let patch = try body(Endpoints.orgPatchPayeeSettings(OrgPayeeSettingsPatch(payeePromotionThreshold: 1)))
        #expect(patch.keys.sorted() == ["payeePromotionThreshold"])
        #expect(patch["payeePromotionThreshold"] as? Int == 1)
    }
}
