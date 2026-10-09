import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Transactions advanced")
struct TransactionsAdvancedTests {
    private let server = try! ServerEndpoint(validating: "https://budget.example.com")

    private func urlRequest<Response>(_ endpoint: Endpoint<Response>) throws -> URLRequest {
        try APIClient(server: server).makeRequest(for: endpoint).0
    }

    private func bodyString<Response>(_ endpoint: Endpoint<Response>) throws -> String {
        let data = try #require(try urlRequest(endpoint).httpBody)
        return String(decoding: data, as: UTF8.self)
    }

    private func body<Response>(_ endpoint: Endpoint<Response>) throws -> [String: Any] {
        let data = try #require(try urlRequest(endpoint).httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONCoding.makeDecoder().decode(Value.self, from: Data(json.utf8))
    }

    private let transactionJSON = """
    {"id":"t1","amount":12.5,"refAmount":12.5,"time":"2026-10-01T10:00:00.000Z","userId":1,
     "transactionType":"expense","paymentType":"creditCard","accountId":"a1","categoryId":"c1",
     "currencyCode":"USD","accountType":"system","transferNature":"not_transfer"}
    """

    // MARK: Splits

    @Test("A create with splits sends one flat object with the base fields and the splits")
    func createWithSplits() throws {
        let base = TransactionCreateRequest(
            amount: 100,
            transactionType: .expense,
            accountId: "acc",
            paymentType: .debitCard,
            categoryId: "main",
            isPlanned: true
        )
        let request = TransactionAdvancedCreateRequest(
            base: base,
            splits: [
                TransactionSplitInput(categoryId: "food", amount: 30.25, note: "Lunch"),
                TransactionSplitInput(categoryId: "fun", amount: 10),
            ],
            originalAmount: 92.1,
            originalCurrencyCode: "EUR",
            location: TransactionLocation(latitude: 50.45, longitude: 30.52)
        )
        let endpoint = Endpoints.createTransactionAdvanced(request)
        let json = try body(endpoint)
        #expect(try urlRequest(endpoint).httpMethod == "POST")
        #expect(json["categoryId"] as? String == "main")
        #expect(json["paymentType"] as? String == "debitCard")
        #expect(json["isPlanned"] as? Bool == true)
        #expect(json["originalCurrencyCode"] as? String == "EUR")
        let splits = try #require(json["splits"] as? [[String: Any]])
        #expect(splits.count == 2)
        #expect(splits[0]["categoryId"] as? String == "food")
        #expect(splits[0]["note"] as? String == "Lunch")
        #expect(splits[1]["note"] == nil)
        let location = try #require(json["location"] as? [String: Any])
        #expect((location["latitude"] as? NSNumber)?.doubleValue == 50.45)
        #expect(try bodyString(endpoint).contains(#""amount":30.25"#))
        #expect(json["refundForTxId"] == nil)
    }

    @Test("Empty splits are left out of a create")
    func createWithoutSplits() throws {
        let base = TransactionCreateRequest(amount: 5, transactionType: .income, accountId: "acc", categoryId: "c")
        let json = try body(Endpoints.createTransactionAdvanced(TransactionAdvancedCreateRequest(base: base, splits: [])))
        #expect(json["splits"] == nil)
        #expect(json["location"] == nil)
    }

    @Test("An update can set or clear splits and the advanced fields")
    func updateSplits() throws {
        var update = TransactionAdvancedUpdateRequest(
            base: TransactionUpdateRequest(amount: 40, paymentType: .cash),
            splits: .set([TransactionSplitInput(categoryId: "c2", amount: 15)]),
            isPlanned: false,
            originalAmount: .clear,
            location: .set(TransactionLocation(latitude: 1, longitude: 2))
        )
        var json = try body(Endpoints.updateTransactionAdvanced(id: "t1", update))
        #expect(try urlRequest(Endpoints.updateTransactionAdvanced(id: "t1", update)).url?.path == "/api/v1/transactions/t1")
        #expect(json["paymentType"] as? String == "cash")
        #expect((json["splits"] as? [[String: Any]])?.first?["categoryId"] as? String == "c2")
        #expect(json["isPlanned"] as? Bool == false)
        #expect(json["originalAmount"] is NSNull)
        #expect(json.keys.contains("originalCurrencyCode") == false)
        #expect(json.keys.contains("refundsTxId") == false)

        update.splits = .clear
        json = try body(Endpoints.updateTransactionAdvanced(id: "t1", update))
        #expect(json["splits"] is NSNull)
    }

    // MARK: Refunds and links

    @Test("Marking as a refund sends both ids; unlinking uses DELETE with the same body")
    func refundLink() throws {
        let link = TransactionRefundLinkRequest(originalTxId: "orig", refundTxId: "ref")
        let create = Endpoints.linkRefund(link)
        #expect(try urlRequest(create).httpMethod == "POST")
        #expect(try urlRequest(create).url?.path == "/api/v1/transactions/refund")
        #expect(try body(create)["originalTxId"] as? String == "orig")
        #expect(try body(create)["refundTxId"] as? String == "ref")

        let remove = Endpoints.unlinkRefund(link)
        #expect(try urlRequest(remove).httpMethod == "DELETE")
        #expect(try body(remove)["refundTxId"] as? String == "ref")
    }

    @Test("A create can carry the refund target, and an update can clear it")
    func refundFields() throws {
        let base = TransactionCreateRequest(amount: 5, transactionType: .income, accountId: "acc", categoryId: "c")
        let json = try body(Endpoints.createTransactionAdvanced(TransactionAdvancedCreateRequest(base: base, refundForTxId: "orig")))
        #expect(json["refundForTxId"] as? String == "orig")

        let update = TransactionAdvancedUpdateRequest(refundsTxId: .clear)
        #expect(try body(Endpoints.updateTransactionAdvanced(id: "t", update))["refundsTxId"] is NSNull)
    }

    @Test("Refund lookups send the id in the path and the query")
    func refundsQuery() throws {
        let url = try #require(try urlRequest(Endpoints.transactionRefunds(transactionId: "t9")).url)
        #expect(url.path == "/api/v1/transactions/t9/refunds")
        #expect(url.query == "transactionId=t9")
    }

    @Test("Linking a transfer sends one id pair; unlinking sends transfer ids")
    func transferLink() throws {
        let link = Endpoints.linkTransfer(TransactionLinkRequest(baseTransactionId: "a", oppositeTransactionId: "b"))
        #expect(try urlRequest(link).httpMethod == "PUT")
        #expect(try body(link)["ids"] as? [[String]] == [["a", "b"]])
        let unlink = Endpoints.unlinkTransfer(TransactionUnlinkRequest(transferIds: ["x"]))
        #expect(try body(unlink)["transferIds"] as? [String] == ["x"])
    }

    @Test("Bulk delete and bulk category send the ids")
    func bulk() throws {
        let delete = Endpoints.bulkDeleteTransactions(TransactionBulkDeleteRequest(transactionIds: ["1", "2"]))
        #expect(try urlRequest(delete).url?.path == "/api/v1/transactions/bulk-delete")
        #expect(try body(delete)["transactionIds"] as? [String] == ["1", "2"])
        let category = Endpoints.bulkSetCategory(TransactionBulkCategoryRequest(transactionIds: ["1"], categoryId: "c"))
        #expect(try urlRequest(category).httpMethod == "PUT")
        #expect(try body(category)["categoryId"] as? String == "c")
        let group = Endpoints.addTransactionsToGroup(groupId: "g", TransactionGroupAddRequest(transactionIds: ["1"]))
        #expect(try urlRequest(group).url?.path == "/api/v1/transaction-groups/g/transactions")
    }

    // MARK: Templates

    @Test("A template request sends every field, with null for unset ones")
    func templateEncoding() throws {
        let template = TransactionTemplateRequest(
            name: "Coffee",
            transactionType: .expense,
            amount: 3.5,
            categoryId: "c1",
            paymentType: .cash,
            tagIds: ["t1"]
        )
        let endpoint = Endpoints.createTransactionTemplate(template)
        let json = try body(endpoint)
        #expect(json["name"] as? String == "Coffee")
        #expect(json["transactionType"] as? String == "expense")
        #expect(json["paymentType"] as? String == "cash")
        #expect(json["accountId"] is NSNull)
        #expect(json["note"] is NSNull)
        #expect(json["tagIds"] as? [String] == ["t1"])
        #expect(try bodyString(endpoint).contains(#""amount":3.5"#))
        #expect(try urlRequest(Endpoints.updateTransactionTemplate(id: "x", template)).httpMethod == "PUT")
    }

    @Test("Templates decode with nullable fields and unknown enums")
    func templateDecoding() throws {
        let json = """
        [{"id":"tp1","userId":1,"name":"Rent","transactionType":"expense","amount":null,"accountId":"a1",
          "categoryId":null,"payeeId":null,"paymentType":"bankTransfer","note":"Monthly",
          "originalCurrencyCode":null,"tagIds":["t1"],"createdAt":"2026-10-01T10:00:00.000Z"},
         {"id":"tp2","name":"Odd","transactionType":"mystery","paymentType":"barter"}]
        """
        let templates = try decode([TransactionTemplate].self, json)
        #expect(templates[0].amount == nil)
        #expect(templates[0].paymentType == .bankTransfer)
        #expect(templates[0].tagIds == ["t1"])
        #expect(templates[1].transactionType == .unknown)
        #expect(templates[1].tagIds.isEmpty)
    }

    // MARK: Decoding

    @Test("Refund links decode with their nested transactions")
    func refundDecoding() throws {
        let json = """
        [{"id":"r1","userId":1,"originalTxId":"t1","refundTxId":"t2","splitId":null,
          "originalTransaction":\(transactionJSON)},
         {"id":"r2","originalTxId":null,"refundTxId":"t3"}]
        """
        let links = try decode([TransactionRefundLink].self, json)
        #expect(links[0].originalTransaction?.amount == 12.5)
        #expect(links[0].refundTransaction == nil)
        #expect(links[1].originalTxId == nil)
    }

    @Test("Attachments and groups decode")
    func attachmentAndGroupDecoding() throws {
        let attachment = try decode(TransactionAttachment.self, """
        {"id":"f1","transactionId":"t1","userId":1,"filename":"receipt.pdf","mimeType":"application/pdf",
         "size":2048,"createdAt":"2026-10-01T10:00:00.000Z"}
        """)
        #expect(attachment.filename == "receipt.pdf")
        #expect(attachment.isImage == false)
        let groups = try decode([TransactionGroupSummary].self, """
        [{"id":"g1","name":"Trip","note":null,"transactionCount":3,"createdAt":"2026-10-01T10:00:00.000Z"}]
        """)
        #expect(groups.first?.transactionCount == 3)
    }

    // MARK: Attachments

    @Test("Attachment upload sends raw bytes with the encoded filename")
    func attachmentUpload() async throws {
        let server = URLProtocolStub.register { _ in
            .json(#"{"status":"success","response":{"id":"f1","transactionId":"t1","filename":"my receipt.jpg","mimeType":"image/jpeg","size":3}}"#)
        }
        let client = APIClient.stubbed(server: server, token: "signed.token")
        let upload = TransactionAttachmentUpload(transactionId: "t1", filename: "my receipt.jpg", data: Data([1, 2, 3]))
        #expect(upload.encodedFilename == "my%20receipt.jpg")

        let attachment = try await client.uploadTransactionAttachment(upload)

        #expect(attachment.id == "f1")
        let recorded = try #require(URLProtocolStub.requests(for: server).first)
        #expect(recorded.method == "POST")
        #expect(recorded.url.path == "/api/v1/transactions/t1/attachments")
        #expect(recorded.header("Content-Type") == "application/octet-stream")
        #expect(recorded.header("X-Filename") == "my%20receipt.jpg")
        #expect(recorded.header("Authorization") == "Bearer signed.token")
        #expect(recorded.body == Data([1, 2, 3]))
    }
}
