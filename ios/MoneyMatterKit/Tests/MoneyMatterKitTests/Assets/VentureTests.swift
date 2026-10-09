import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Venture")
struct VentureKitTests {
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

    @Test("Deals decode from their page, with decimal strings and an inline platform")
    func decodesDeals() throws {
        let json = """
        {"status":"success","response":{"data":[{
          "id":"d1","userId":1,"platformId":"p1","name":"Acme SPV","vehicleType":"spv",
          "spvSubtype":"single_company","targetCompany":"Acme","currencyCode":"USD","status":"partial_exit",
          "principal":"10000.0000000000","entryFee":"200.0000000000","entryFeePct":"0.02","mgmtFeePct":"0",
          "carryPct":"0.2","hurdlePct":"0.08","investmentDate":"2024-02-01","expectedExitDate":null,"notes":null,
          "platform":{"id":"p1","userId":1,"name":"AngelList","website":null,"description":null,
            "defaultEntryFeePct":"0.02","defaultMgmtFeePct":"0","defaultCarryPct":"0.2","defaultHurdlePct":"0"}
        }],"pagination":{"limit":100,"offset":0,"page":1}}}
        """
        let deals = try decode(Endpoints.ventureDeals(), json: json)
        let deal = try #require(deals.first)
        #expect(deal.status == .partialExit)
        #expect(deal.spvSubtype == .singleCompany)
        #expect(deal.principal == 10000)
        #expect(deal.entryFee == 200)
        #expect(deal.carryPct == Decimal(string: "0.2"))
        #expect(deal.hurdlePct == Decimal(string: "0.08"))
        #expect(deal.investmentDate == CalendarDate(year: 2024, month: 2, day: 1))
        #expect(deal.expectedExitDate == nil)
        #expect(deal.platform?.name == "AngelList")
        #expect(deal.platform?.defaultEntryFeePct == Decimal(string: "0.02"))
    }

    @Test("Unknown statuses and event types decode leniently")
    func decodesLeniently() throws {
        let json = """
        {"status":"success","response":[{"id":"e1","dealId":"d1","type":"secondary_sale","eventDate":"2025-01-10",
        "grossAmount":null,"gpCarryAmount":"12.5","lpNetAmount":null,"navAfter":"15000","quantityPct":null,
        "lpNetAmountOverridden":false,"gpCarryOverridden":true,"currencyCode":"USD","cashFlowMode":"teleport",
        "notes":"Mark-up","links":[{"id":"l1","ventureEventId":"e1","transactionId":"t1","amount":"5","currencyCode":"USD"}]}]}
        """
        let events = try decode(Endpoints.ventureEvents(dealId: "d1"), json: json)
        let event = try #require(events.first)
        #expect(event.type == .unknown)
        #expect(event.cashFlowMode == .unknown)
        #expect(event.navAfter == 15000)
        #expect(event.gpCarryAmount == Decimal(string: "12.5"))
        #expect(event.gpCarryOverridden)
        #expect(event.links.map(\.transactionId) == ["t1"])
    }

    @Test("Metrics keep nil multiples nil")
    func decodesMetrics() throws {
        let json = """
        {"status":"success","response":{"costBasis":"10200","totalInvested":"10200","currentValue":"15000",
        "totalDistributions":"0","pnlAbsolute":"4800","pnlPct":"0.4705882353","tvpi":"1.47","dpi":null,"irr":null}}
        """
        let metrics = try decode(Endpoints.ventureDealMetrics(id: "d1"), json: json)
        #expect(metrics.currentValue == 15000)
        #expect(metrics.pnlAbsolute == 4800)
        #expect(metrics.tvpi == Decimal(string: "1.47"))
        #expect(metrics.dpi == nil)
        #expect(metrics.irr == nil)
    }

    @Test("Deal create sends fractions, a day-only date, and explicit nulls")
    func encodesDeal() throws {
        let endpoint = Endpoints.ventureDealCreate(VentureDealRequest(
            name: "Acme SPV",
            currencyCode: "USD",
            principal: 10000,
            investmentDate: CalendarDate(year: 2024, month: 2, day: 1),
            spvSubtype: .singleCompany,
            entryFeePct: Decimal(string: "0.02")!,
            carryPct: Decimal(string: "0.2")!
        ))
        let urlRequest = try request(endpoint)
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.url?.path == "/api/v1/venture/deals")
        let json = try body(endpoint)
        #expect(json["investmentDate"] as? String == "2024-02-01")
        #expect(json["spvSubtype"] as? String == "single_company")
        #expect((json["carryPct"] as? NSNumber)?.doubleValue == 0.2)
        #expect(json["platformId"] is NSNull)
        #expect(json["expectedExitDate"] is NSNull)
        #expect(json.keys.contains("entryFee") == false)
        #expect(json.keys.contains("status") == false)
    }

    @Test("Status change sends only the status")
    func encodesStatus() throws {
        let endpoint = Endpoints.ventureDealSetStatus(id: "d1", status: .fullyExited)
        #expect(try request(endpoint).httpMethod == "PUT")
        let json = try body(endpoint)
        #expect(json.count == 1)
        #expect(json["status"] as? String == "fully_exited")
    }

    @Test("Event create sends the cash flow mode and amounts")
    func encodesEvent() throws {
        let endpoint = Endpoints.ventureEventCreate(dealId: "d1", VentureEventCreateRequest(
            type: .distribution,
            eventDate: CalendarDate(year: 2025, month: 3, day: 4),
            cashFlowMode: .outOfWallet,
            grossAmount: 2500
        ))
        #expect(try request(endpoint).url?.path == "/api/v1/venture/deals/d1/events")
        let json = try body(endpoint)
        #expect(json["type"] as? String == "distribution")
        #expect(json["cashFlowMode"] as? String == "out_of_wallet")
        #expect(json["eventDate"] as? String == "2025-03-04")
        #expect((json["grossAmount"] as? NSNumber)?.intValue == 2500)
        #expect(json["navAfter"] is NSNull)
    }

    @Test("Event update leaves out amounts the type doesn't use")
    func encodesEventUpdate() throws {
        let endpoint = Endpoints.ventureEventUpdate(id: "e1", VentureEventUpdateRequest(
            eventDate: CalendarDate(year: 2025, month: 6, day: 30),
            navAfter: 18000
        ))
        let urlRequest = try request(endpoint)
        #expect(urlRequest.httpMethod == "PUT")
        #expect(urlRequest.url?.path == "/api/v1/venture/events/e1")
        let json = try body(endpoint)
        #expect(json["eventDate"] as? String == "2025-06-30")
        #expect((json["navAfter"] as? NSNumber)?.intValue == 18000)
        #expect(json.keys.contains("grossAmount") == false)
        #expect(json["notes"] is NSNull)
    }

    @Test("Event delete only sends deleteLinkedTransactions when chosen")
    func eventDeleteQuery() throws {
        #expect(try request(Endpoints.ventureEventDelete(id: "e1")).url?.query == nil)
        let withLinks = try request(Endpoints.ventureEventDelete(id: "e1", deleteLinkedTransactions: true))
        #expect(withLinks.url?.query == "deleteLinkedTransactions=true")
        #expect(withLinks.httpMethod == "DELETE")
    }

    @Test("Event types gate which fields apply")
    func eventTypeRules() {
        #expect(VentureEventType.creatable(hasInitialInvestment: false) == [.initialInvestment])
        #expect(!VentureEventType.creatable(hasInitialInvestment: true).contains(.initialInvestment))
        #expect(VentureEventType.navUpdate.isNavOnly)
        #expect(!VentureEventType.navUpdate.requiresGrossAmount)
        #expect(VentureEventType.exit.requiresNavAfter)
        #expect(VentureEventType.exit.isCarryBearing)
        #expect(!VentureEventType.initialInvestment.requiresGrossAmount)
    }

    @Test("Platform lists ask for the maximum page")
    func platformsQuery() throws {
        let urlRequest = try request(Endpoints.venturePlatforms())
        #expect(urlRequest.url?.path == "/api/v1/venture/platforms")
        #expect(urlRequest.url?.query == "limit=100")
    }
}
