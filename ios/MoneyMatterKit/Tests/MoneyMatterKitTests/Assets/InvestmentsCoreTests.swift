import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Investments core")
struct InvestmentsCoreKitTests {
    private let server = try! ServerEndpoint(validating: "https://budget.example.com")

    private func decode<Value>(_ endpoint: Endpoint<Value>, json: String) throws -> Value {
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

    @Test("Portfolio list unwraps the paginated data and decodes leniently")
    func portfolioList() throws {
        let json = """
        {"status":"success","response":{"data":[
          {"id":"p1","name":"Brokerage","userId":1,"portfolioType":"retirement","description":null,
           "displayCurrencyCode":"EUR","isEnabled":true,"createdAt":"2026-01-02T03:04:05.000Z",
           "updatedAt":"2026-01-02T03:04:05.000Z","deletedAt":null},
          {"id":"p2","name":"Crypto","userId":1,"portfolioType":"hedge_fund","isEnabled":false,
           "deletedAt":"2026-10-01T00:00:00.000Z"}
        ],"pagination":{"limit":100,"offset":0}}}
        """
        let portfolios = try decode(Endpoints.portfolios(), json: json)
        #expect(portfolios.count == 2)
        #expect(portfolios[0].portfolioType == .retirement)
        #expect(portfolios[0].displayCurrencyCode == "EUR")
        #expect(portfolios[0].deletedAt == nil)
        #expect(portfolios[1].portfolioType == .unknown)
        #expect(portfolios[1].isEnabled == false)
        #expect(portfolios[1].deletedAt != nil)
    }

    @Test("Summary accepts numeric strings and numbers")
    func summary() throws {
        let json = """
        {"status":"success","response":{"portfolioId":"p1","portfolioName":"Brokerage",
          "totalCurrentValue":"1500.25","totalCostBasis":1000,"unrealizedGainValue":"500.25",
          "unrealizedGainPercent":"50.025","realizedGainValue":"-20","realizedGainPercent":"-2",
          "currencyCode":"USD","totalCashInBaseCurrency":"300","availableCashInBaseCurrency":"250.5",
          "totalPortfolioValue":"1800.25","baseCurrencyCode":"EUR","totalPortfolioValueInBaseCurrency":"1650"}}
        """
        let summary = try decode(Endpoints.portfolioSummary(id: "p1"), json: json)
        #expect(summary.totalCurrentValue == Decimal(string: "1500.25"))
        #expect(summary.totalCostBasis == 1000)
        #expect(summary.realizedGainValue == -20)
        #expect(summary.availableCashInBaseCurrency == Decimal(string: "250.5"))
        #expect(summary.baseCurrencyCode == "EUR")
        #expect(summary.totalReturnValue == Decimal(string: "480.25"))
        #expect(summary.totalReturnPercent == Decimal(string: "48.025"))
    }

    @Test("Holdings decode with nested security and optional market data")
    func holdings() throws {
        let json = """
        {"status":"success","response":[
          {"portfolioId":"p1","securityId":"s1","quantity":10.5,"costBasis":"1050","refCostBasis":"1050",
           "currencyCode":"USD","excluded":false,"latestPrice":"120.5","priceDate":"2026-10-08T00:00:00.000Z",
           "marketValue":"1265.25","unrealizedGainValue":"215.25","unrealizedGainPercent":"20.5",
           "security":{"id":"s1","name":"Apple Inc.","symbol":"AAPL","providerSymbol":"AAPL","currencyCode":"USD",
             "isBrokerageCash":false,"assetClass":"stocks","providerName":"polygon"}},
          {"portfolioId":"p1","securityId":"s2","quantity":"0.25","costBasis":"5000","currencyCode":"USD",
           "excluded":true,"security":{"id":"s2","name":null,"symbol":"BTC","currencyCode":"USD","assetClass":"nft"}}
        ]}
        """
        let holdings = try decode(Endpoints.holdings(portfolioID: "p1"), json: json)
        #expect(holdings.count == 2)
        #expect(holdings[0].id == "s1")
        #expect(holdings[0].quantity == Decimal(string: "10.5"))
        #expect(holdings[0].latestPrice == Decimal(string: "120.5"))
        #expect(holdings[0].security?.displaySymbol == "AAPL")
        #expect(holdings[0].security?.assetClass == .stocks)
        #expect(holdings[1].marketValue == nil)
        #expect(holdings[1].excluded)
        #expect(holdings[1].security?.assetClass == .unknown)
    }

    @Test("Security search results decode and flag support")
    func securitySearch() throws {
        let json = """
        {"status":"success","response":[
          {"symbol":"AAPL","providerSymbol":"AAPL","name":"Apple Inc.","assetClass":"stocks","providerName":"polygon",
           "exchangeName":"NASDAQ","currencyCode":"USD","matchType":"exact","marketCapRank":null,"isInPortfolio":true},
          {"symbol":"US10Y","providerSymbol":"US10Y","name":"Treasury","assetClass":"fixed_income",
           "providerName":"yahoo","currencyCode":"USD"}
        ]}
        """
        let hits = try decode(Endpoints.investmentSecuritiesSearch(query: "a"), json: json)
        #expect(hits.count == 2)
        #expect(hits[0].isInPortfolio == true)
        #expect(hits[0].isSupported)
        #expect(hits[1].assetClass == .fixedIncome)
        #expect(!hits[1].isSupported)
    }

    @Test("Transaction page decodes trades and skips malformed rows")
    func transactionPage() throws {
        let json = """
        {"status":"success","response":{"transactions":[
          {"id":"t1","securityId":"s1","portfolioId":"p1","transactionType":"expense","date":"2026-06-20T00:00:00.000Z",
           "name":null,"category":"buy","quantity":"10","price":"100.5","fees":"1","amount":"1006",
           "refAmount":"1006","currencyCode":"USD","settlementCurrencyCode":"EUR","settlementAmount":"930",
           "security":{"id":"s1","symbol":"AAPL","currencyCode":"USD","assetClass":"stocks"}},
          {"securityId":"broken"}
        ],"total":7,"limit":20,"offset":0}}
        """
        let page = try decode(Endpoints.investmentTransactions(portfolioID: "p1"), json: json)
        #expect(page.transactions.count == 1)
        #expect(page.total == 7)
        #expect(page.hasMore)
        let trade = try #require(page.transactions.first)
        #expect(trade.category == .buy)
        #expect(trade.price == Decimal(string: "100.5"))
        #expect(trade.day == CalendarDate(year: 2026, month: 6, day: 20))
        #expect(trade.hasSettlement)
        #expect(trade.security?.symbol == "AAPL")
    }

    // MARK: Requests

    @Test("Portfolio list sends onlyDeleted only when set")
    func portfolioListQuery() throws {
        let live = try #require(try request(Endpoints.portfolios()).url?.query)
        #expect(!live.contains("onlyDeleted"))
        let trash = try #require(try request(Endpoints.portfolios(onlyDeleted: true)).url?.query)
        #expect(trash.contains("onlyDeleted=true"))
    }

    @Test("Portfolio create encodes the chosen fields")
    func portfolioCreate() throws {
        let endpoint = Endpoints.portfolioCreate(PortfolioCreateRequest(name: "Brokerage", portfolioType: .savings))
        let json = try body(endpoint)
        #expect(try request(endpoint).httpMethod == "POST")
        #expect(json["name"] as? String == "Brokerage")
        #expect(json["portfolioType"] as? String == "savings")
        #expect(json["isEnabled"] as? Bool == true)
        #expect(json["displayCurrencyCode"] == nil)
    }

    @Test("Portfolio update sends null to clear and omits unchanged fields")
    func portfolioUpdate() throws {
        let endpoint = Endpoints.portfolioUpdate(
            id: "p1",
            PortfolioUpdateRequest(name: "Renamed", description: .clear, displayCurrencyCode: .set("EUR"))
        )
        let json = try body(endpoint)
        #expect(try request(endpoint).httpMethod == "PUT")
        #expect(json["name"] as? String == "Renamed")
        #expect(json["description"] is NSNull)
        #expect(json["displayCurrencyCode"] as? String == "EUR")
        #expect(json["portfolioType"] == nil)
        #expect(json["isEnabled"] == nil)
    }

    @Test("Portfolio delete sends force only for permanent deletes")
    func portfolioDelete() throws {
        let soft = try request(Endpoints.portfolioDelete(id: "p1"))
        #expect(soft.httpMethod == "DELETE")
        #expect(String(decoding: soft.httpBody ?? Data(), as: UTF8.self) == "{}")
        let hard = try body(Endpoints.portfolioDelete(id: "p1", force: true))
        #expect(hard["force"] as? Bool == true)
    }

    @Test("Holding create sends the search result without isInPortfolio")
    func holdingCreate() throws {
        let hit = InvestmentSecuritySearchResult(
            symbol: "AAPL",
            providerSymbol: "AAPL",
            name: "Apple Inc.",
            assetClass: .stocks,
            providerName: .polygon,
            currencyCode: "USD",
            matchType: "exact",
            isInPortfolio: false
        )
        let json = try body(Endpoints.holdingCreate(HoldingCreateRequest(portfolioId: "p1", searchResult: hit)))
        #expect(json["portfolioId"] as? String == "p1")
        #expect(json["securityId"] == nil)
        let result = try #require(json["searchResult"] as? [String: Any])
        #expect(result["symbol"] as? String == "AAPL")
        #expect(result["assetClass"] as? String == "stocks")
        #expect(result["providerName"] as? String == "polygon")
        #expect(result["isInPortfolio"] == nil)
    }

    @Test("Holding delete forces removal of its transactions")
    func holdingDelete() throws {
        let json = try body(Endpoints.holdingDelete(HoldingDeleteRequest(portfolioId: "p1", securityId: "s1")))
        #expect(json["force"] as? Bool == true)
        #expect(json["securityId"] as? String == "s1")
    }

    @Test("Investment transaction create sends numeric strings and a settlement fee")
    func transactionCreate() throws {
        let request = InvestmentTransactionCreateRequest(
            portfolioId: "p1",
            securityId: "s1",
            category: .buy,
            date: CalendarDate(year: 2026, month: 6, day: 20),
            quantity: Decimal(string: "0.00012345")!,
            price: Decimal(string: "64000.5")!,
            fees: 0,
            settlement: InvestmentTransactionSettlement(currencyCode: "EUR", amount: 7, fees: Decimal(string: "0.1"))
        )
        let json = try body(Endpoints.investmentTransactionCreate(request))
        #expect(json["date"] as? String == "2026-06-20")
        #expect(json["quantity"] as? String == "0.00012345")
        #expect(json["price"] as? String == "64000.5")
        #expect(json["fees"] as? String == "0")
        #expect(json["category"] as? String == "buy")
        #expect(json["settlementCurrencyCode"] as? String == "EUR")
        #expect(json["settlementAmount"] as? String == "7")
        #expect(json["settlementFees"] as? String == "0.1")
        #expect(json["settlementRate"] == nil)
        #expect(json["name"] == nil)
    }

    @Test("Investment transaction update omits unset fields and uses PUT")
    func transactionUpdate() throws {
        let endpoint = Endpoints.investmentTransactionUpdate(
            id: "t1",
            InvestmentTransactionUpdateRequest(
                price: 10,
                settlement: InvestmentTransactionSettlement(currencyCode: "EUR", amount: 9, rate: Decimal(string: "0.9"))
            )
        )
        let json = try body(endpoint)
        let built = try request(endpoint)
        #expect(built.httpMethod == "PUT")
        #expect(built.url?.path.hasSuffix("/investments/transaction/t1") == true)
        #expect(json["price"] as? String == "10")
        #expect(json["quantity"] == nil)
        #expect(json["settlementRate"] as? String == "0.9")
        #expect(json["settlementFees"] == nil)
    }
}
