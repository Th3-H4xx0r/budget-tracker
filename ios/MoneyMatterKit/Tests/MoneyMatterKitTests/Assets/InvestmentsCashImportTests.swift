import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Investments cash and import")
struct InvestmentsCashImportKitTests {
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

    @Test("Cash balances decode from decimal strings")
    func decodesBalances() throws {
        let json = """
        {"status":"success","response":[{"portfolioId":"p1","currencyCode":"USD","availableCash":"1200.5000000000",
        "totalCash":"1500.0000000000","refAvailableCash":"1100.1","refTotalCash":"1374.2",
        "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"}]}
        """
        let balances = try decode(Endpoints.portfolioCashBalances(portfolioId: "p1"), json: json)
        let balance = try #require(balances.first)
        #expect(balance.currencyCode == "USD")
        #expect(balance.availableCash == Decimal(string: "1200.5"))
        #expect(balance.totalCash == 1500)
        #expect(balance.id == "USD")
    }

    @Test("Transfers decode from their page and classify by direction")
    func decodesTransfers() throws {
        let json = """
        {"status":"success","response":{"data":[
          {"id":"t1","userId":1,"fromAccountId":"a1","toPortfolioId":"p1","fromPortfolioId":null,"toAccountId":null,
           "amount":"500","refAmount":"500","currencyCode":"USD","toCurrencyCode":null,"toAmount":null,"refToAmount":null,
           "transactionId":"tx1","metaData":null,"isAdjustment":false,"affectsCash":true,"date":"2026-03-01","description":"Top up"},
          {"id":"t2","fromAccountId":null,"toPortfolioId":"p1","fromPortfolioId":"p1","toAccountId":null,
           "amount":"100","currencyCode":"USD","toCurrencyCode":"EUR","toAmount":"92.5","isAdjustment":false,"date":"2026-03-02"},
          {"id":"t3","fromAccountId":null,"toPortfolioId":null,"fromPortfolioId":"p1","toAccountId":null,
           "amount":"20","currencyCode":"USD","isAdjustment":true,"date":"2026-03-03","description":null}
        ],"pagination":{"limit":100,"offset":0,"page":1,"totalCount":3}}}
        """
        let transfers = try decode(Endpoints.portfolioCashTransfers(portfolioId: "p1"), json: json)
        #expect(transfers.count == 3)
        #expect(transfers[0].kind(for: "p1") == .fromAccount)
        #expect(transfers[0].isInflow(for: "p1"))
        #expect(transfers[0].transactionId == "tx1")
        #expect(transfers[0].date == CalendarDate(year: 2026, month: 3, day: 1))
        #expect(transfers[1].kind(for: "p1") == .exchange)
        #expect(transfers[1].toAmount == Decimal(string: "92.5"))
        #expect(transfers[2].kind(for: "p1") == .withdrawal)
        #expect(transfers[2].isAdjustment)
        #expect(!transfers[2].isInflow(for: "p1"))
    }

    @Test("Cash amounts are sent as decimal strings")
    func encodesCashTransaction() throws {
        let endpoint = Endpoints.portfolioCashTransactionCreate(portfolioId: "p1", PortfolioCashTransactionRequest(
            type: .withdrawal,
            amount: Decimal(string: "250.75")!,
            currencyCode: "USD",
            date: CalendarDate(year: 2026, month: 4, day: 5),
            isAdjustment: true
        ))
        #expect(try request(endpoint).url?.path == "/api/v1/investments/portfolios/p1/cash-transaction")
        let json = try body(endpoint)
        #expect(json["type"] as? String == "withdrawal")
        #expect(json["amount"] as? String == "250.75")
        #expect(json["date"] as? String == "2026-04-05")
        #expect(json["isAdjustment"] as? Bool == true)
    }

    @Test("Account transfers drop the currency on the way in and keep it on the way out")
    func encodesAccountTransfers() throws {
        let request = PortfolioTransferAccountRequest(
            accountId: "a1",
            amount: 300,
            currencyCode: "EUR",
            date: CalendarDate(year: 2026, month: 5, day: 1)
        )
        let inbound = Endpoints.portfolioTransferFromAccount(portfolioId: "p1", request)
        #expect(try self.request(inbound).url?.path == "/api/v1/investments/portfolios/p1/transfer/from-account")
        let inboundBody = try body(inbound)
        #expect(inboundBody["currencyCode"] == nil)
        #expect(inboundBody["amount"] as? String == "300")

        let outbound = Endpoints.portfolioTransferToAccount(portfolioId: "p1", request)
        #expect(try self.request(outbound).url?.path == "/api/v1/investments/portfolios/p1/transfer/to-account")
        #expect(try body(outbound)["currencyCode"] as? String == "EUR")
    }

    @Test("Exchange sends both amounts as strings")
    func encodesExchange() throws {
        let endpoint = Endpoints.portfolioExchangeCurrency(portfolioId: "p1", PortfolioExchangeRequest(
            fromCurrencyCode: "USD",
            toCurrencyCode: "EUR",
            fromAmount: 100,
            toAmount: Decimal(string: "92.5")!,
            date: CalendarDate(year: 2026, month: 5, day: 2)
        ))
        let json = try body(endpoint)
        #expect(json["fromAmount"] as? String == "100")
        #expect(json["toAmount"] as? String == "92.5")
    }

    @Test("Transfer delete only flags linked deletion when asked")
    func transferDeleteQuery() throws {
        let plain = try request(Endpoints.portfolioCashTransferDelete(portfolioId: "p1", transferId: "t1"))
        #expect(plain.url?.query == nil)
        #expect(plain.httpMethod == "DELETE")
        let linked = try request(Endpoints.portfolioCashTransferDelete(portfolioId: "p1", transferId: "t1", deleteLinkedTransaction: true))
        #expect(linked.url?.query == "deleteLinkedTransaction=true")
    }

    @Test("CSV parsing detects the delimiter and handles quotes")
    func parsesCSV() throws {
        let text = "Symbol;Date;Side;Qty;Price\n\"AAPL\";2026-01-02;BUY;10;\"185,5\"\n\nMSFT;2026-01-03;Sell;2;410\n"
        let csv = try InvestmentImportCSV.parse(text)
        #expect(csv.headers == ["Symbol", "Date", "Side", "Qty", "Price"])
        #expect(csv.rows.count == 2)
        #expect(csv.rows[0]["Price"] == "185,5")
        #expect(csv.distinctValues(of: "Side") == ["BUY", "Sell"])
        #expect(csv.guessColumn(["quantity", "qty"]) == "Qty")
        #expect(InvestmentImportColumnMapping.guessSide(for: "BUY") == "buy")
        #expect(InvestmentImportColumnMapping.guessSide(for: "Sell") == "sell")
        #expect(InvestmentImportColumnMapping.guessSide(for: "Interest") == "skip")
        #expect(throws: InvestmentImportCSV.ParseError.empty) { try InvestmentImportCSV.parse("  \n") }
    }

    @Test("Extraction decodes, and execute keeps only resolved, importable trades")
    func extractAndExecute() throws {
        let json = """
        {"status":"success","response":{"holdings":[
          {"tempId":"h1","parsedSymbol":"AAPL","parsedName":"Apple","resolvedConfidence":"auto","portfolioId":"p1",
           "currencyCode":"USD","hasExistingHolding":true,
           "resolvedSecurity":{"securityId":"s1","providerSymbol":"AAPL","symbol":"AAPL","name":"Apple Inc.",
             "assetClass":"stocks","providerName":"polygon","currencyCode":"USD","alreadyInDb":true},
           "transactions":[
             {"tempId":"x1","date":"2026-01-02","side":"buy","quantity":"10","price":"185.5","fees":"1","amount":"1856","possibleDuplicateOf":null},
             {"tempId":"x2","date":"2026-01-05","side":"fee","quantity":"0","price":"0","fees":"2","amount":"2","possibleDuplicateOf":null}
           ]},
          {"tempId":"h2","parsedSymbol":"ZZZZ","parsedName":null,"resolvedSecurity":null,"resolvedConfidence":"unmapped",
           "portfolioId":"p1","currencyCode":null,"hasExistingHolding":false,
           "transactions":[{"tempId":"x3","date":"2026-01-02","side":"buy","quantity":"1","price":"1","fees":"0","amount":"1","possibleDuplicateOf":null}]}
        ],"warnings":["Row 7 skipped"],"fileType":"csv","tokenCount":{"input":0,"output":0}}}
        """
        let mapping = InvestmentImportColumnMapping(symbol: "Symbol", date: "Date", side: "Side", quantity: "Qty", price: "Price")
        let extraction = try decode(
            Endpoints.investmentImportExtractCSV(fileData: Data("a".utf8), portfolioId: "p1", mapping: mapping),
            json: json
        )
        #expect(extraction.holdings.count == 2)
        #expect(extraction.warnings == ["Row 7 skipped"])
        #expect(extraction.holdings[0].resolvedSecurity?.name == "Apple Inc.")
        #expect(extraction.holdings[0].isImportable)
        #expect(!extraction.holdings[1].isImportable)

        let execute = Endpoints.investmentImportExecute(InvestmentImportExecuteRequest(
            holdings: extraction.holdings,
            skipTempIds: ["x9"]
        ))
        let json2 = try body(execute)
        let holdings = try #require(json2["holdings"] as? [[String: Any]])
        #expect(holdings.count == 1)
        let transactions = try #require(holdings.first?["transactions"] as? [[String: Any]])
        #expect(transactions.map { $0["tempId"] as? String } == ["x1"])
        #expect(json2["skipTempIds"] as? [String] == ["x9"])
        let security = try #require(holdings.first?["resolvedSecurity"] as? [String: Any])
        #expect(security["alreadyInDb"] as? Bool == true)
    }

    @Test("CSV extraction sends the mapping with explicit nulls")
    func encodesExtract() throws {
        let mapping = InvestmentImportColumnMapping(
            symbol: "Symbol", date: "Date", side: "Side", quantity: "Qty", price: "Price",
            sideValueMapping: ["BUY": "buy", "X": "skip"]
        )
        let endpoint = Endpoints.investmentImportExtractCSV(fileData: Data("abc".utf8), portfolioId: "p1", mapping: mapping)
        let json = try body(endpoint)
        #expect(json["source"] as? String == "csv")
        #expect(json["fileBase64"] as? String == "YWJj")
        #expect(json["defaultPortfolioId"] as? String == "p1")
        let columns = try #require(json["columnMapping"] as? [String: Any])
        #expect(columns["fees"] is NSNull)
        #expect(columns["defaultAssetClassHint"] as? String == "stocks")
        #expect((columns["sideValueMapping"] as? [String: String])?["X"] == "skip")
    }
}
