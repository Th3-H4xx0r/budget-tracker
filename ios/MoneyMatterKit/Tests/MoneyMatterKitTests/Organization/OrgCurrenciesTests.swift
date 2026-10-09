import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Organization: currencies")
struct OrgCurrenciesTests {
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

    @Test("Exchange rates decode with custom defaulting to false")
    func decodeRates() throws {
        let json = """
        {"status":"success","response":[
          {"userId":1,"baseCode":"EUR","quoteCode":"USD","rate":1.0832,"custom":true},
          {"baseCode":"USD","quoteCode":"EUR","rate":0.9232}
        ]}
        """
        let rates = try decode(Endpoints.orgUserExchangeRates(), json: json)
        #expect(rates.count == 2)
        #expect(rates[0].baseCode == "EUR")
        #expect(rates[0].rate == Decimal(string: "1.0832"))
        #expect(rates[0].custom)
        #expect(rates[1].custom == false)
    }

    @Test("Custom rates are sent as pairs")
    func editRates() throws {
        let endpoint = Endpoints.orgEditExchangeRates([
            OrgExchangeRatePair(baseCode: "EUR", quoteCode: "USD", rate: Decimal(string: "1.1")!),
            OrgExchangeRatePair(baseCode: "USD", quoteCode: "EUR", rate: Decimal(string: "0.909091")!),
        ])
        let request = try request(endpoint)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/v1/user/currency/rates")
        let pairs = try #require(try body(endpoint)["pairs"] as? [[String: Any]])
        #expect(pairs.count == 2)
        #expect(pairs[0]["baseCode"] as? String == "EUR")
        #expect(pairs[0]["quoteCode"] as? String == "USD")
        #expect((pairs[0]["rate"] as? NSNumber)?.doubleValue == 1.1)
    }

    @Test("Restoring live rates deletes both directions")
    func deleteCustomRates() throws {
        let endpoint = Endpoints.orgDeleteCustomRates([
            OrgExchangeRateKey(baseCode: "EUR", quoteCode: "USD"),
            OrgExchangeRateKey(baseCode: "USD", quoteCode: "EUR"),
        ])
        #expect(try request(endpoint).httpMethod == "DELETE")
        let pairs = try #require(try body(endpoint)["pairs"] as? [[String: Any]])
        #expect(pairs.count == 2)
        #expect(pairs[1]["baseCode"] as? String == "USD")
        #expect(pairs[1]["rate"] == nil)
    }

    @Test("Removing a currency sends its code in the body")
    func deleteCurrency() throws {
        let endpoint = Endpoints.orgDeleteUserCurrency(code: "GBP")
        let request = try request(endpoint)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/v1/user/currency")
        #expect(try body(endpoint)["currencyCode"] as? String == "GBP")
    }

    @Test("Change base sends newCurrencyCode and decodes the queued job")
    func changeBase() throws {
        let endpoint = Endpoints.orgChangeBaseCurrency(code: "EUR")
        let request = try request(endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v1/user/currencies/change-base")
        #expect(try body(endpoint)["newCurrencyCode"] as? String == "EUR")
        let started = try decode(endpoint, json: #"{"status":"success","response":{"jobId":"j1","state":"queued"}}"#)
        #expect(started.state == .queued)
        #expect(started.jobId == "j1")
        #expect(started.state.isInFlight)
    }

    @Test("Change status decodes every state, unknown included")
    func changeStatus() throws {
        let endpoint = Endpoints.orgBaseCurrencyChangeStatus()
        #expect(try request(endpoint).url?.path == "/api/v1/user/currencies/change-base/status")

        let idle = try decode(endpoint, json: #"{"status":"success","response":{"state":"idle"}}"#)
        #expect(idle.state == .idle)
        #expect(!idle.state.isInFlight)

        let running = try decode(endpoint, json: #"{"status":"success","response":{"state":"running","jobId":"j1","step":"balances","startedAt":1760000000000}}"#)
        #expect(running.state == .running)
        #expect(running.step == "balances")
        #expect(running.state.isInFlight)

        let failed = try decode(endpoint, json: #"{"status":"success","response":{"state":"failed","jobId":"j1","error":"Rates missing"}}"#)
        #expect(failed.state == .failed)
        #expect(failed.error == "Rates missing")

        let completed = try decode(endpoint, json: #"{"status":"success","response":{"state":"completed","jobId":"j1","finishedAt":1,"result":{"accounts":3}}}"#)
        #expect(completed.state == .completed)

        let odd = try decode(endpoint, json: #"{"status":"success","response":{"state":"paused"}}"#)
        #expect(odd.state == .unknown)
    }
}
