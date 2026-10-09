import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Vehicles")
struct VehicleKitTests {
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

    private static let vehicleJSON = """
    {
      "id": "v1", "accountId": "acc1", "userId": 7, "make": "Toyota", "model": "Corolla",
      "trim": "LE", "year": 2021, "vehicleClass": "sedan", "purchasePrice": 21500.5,
      "purchaseDate": "2021-03-15", "valueAnchor": 15000, "valueAnchorDate": "2024-01-01",
      "depreciationPreset": "class-default", "customAnnualRatePct": null, "salvageFloorPct": 10,
      "currentMileage": 42000, "valueLastComputedAt": "2026-10-01T00:00:00.000Z",
      "createdAt": "2021-03-15T10:00:00.000Z", "updatedAt": "2026-10-01T00:00:00.000Z",
      "account": {
        "id": "acc1", "name": "Family Car", "initialBalance": 21500.5, "refInitialBalance": 21500.5,
        "currentBalance": 14000, "refCurrentBalance": 14000, "creditLimit": 0, "refCreditLimit": 0,
        "type": "system", "accountCategory": "vehicle", "currencyCode": "USD", "userId": 7,
        "status": "active", "excludeFromStats": false, "bankDataProviderConnectionId": null,
        "bankProviderType": null
      }
    }
    """

    @Test("A vehicle decodes with its inline account and day-only dates")
    func decodesVehicle() throws {
        let vehicles = try decode(Endpoints.vehicles(), json: #"{"status":"success","response":[\#(Self.vehicleJSON)]}"#)
        let vehicle = try #require(vehicles.first)
        #expect(vehicle.id == "v1")
        #expect(vehicle.vehicleClass == .sedan)
        #expect(vehicle.depreciationPreset == .classDefault)
        #expect(vehicle.purchasePrice == Decimal(string: "21500.5"))
        #expect(vehicle.purchaseDate == CalendarDate(year: 2021, month: 3, day: 15))
        #expect(vehicle.valueAnchorDate == CalendarDate(year: 2024, month: 1, day: 1))
        #expect(vehicle.currentMileage == 42000)
        #expect(vehicle.account?.accountCategory == .vehicle)
        #expect(vehicle.displayName == "Family Car")
        #expect(vehicle.subtitle == "2021 Toyota Corolla · LE")
        #expect(vehicle.depreciationAmount == Decimal(string: "7500.5"))
    }

    @Test("Unknown enum values and a missing account decode leniently")
    func decodesLeniently() throws {
        let json = """
        {"status":"success","response":{"id":"v2","accountId":"a2","make":"Zero","model":"SR",
        "year":2023,"vehicleClass":"hovercraft","purchasePrice":9000,"purchaseDate":"2023-05-01",
        "valueAnchor":null,"valueAnchorDate":null,"depreciationPreset":"turbo",
        "customAnnualRatePct":null,"salvageFloorPct":5,"currentMileage":null,"account":null}}
        """
        let vehicle = try #require(try decode(Endpoints.vehicle(id: "v2"), json: json))
        #expect(vehicle.vehicleClass == .unknown)
        #expect(vehicle.depreciationPreset == .unknown)
        #expect(vehicle.account == nil)
        #expect(vehicle.displayName == "Zero SR")
        #expect(vehicle.currentValue == 0)
    }

    @Test("Create sends a day-only purchase date and the enum raw values")
    func encodesCreate() throws {
        let endpoint = Endpoints.vehicleCreate(VehicleCreateRequest(
            name: "Bike",
            currencyCode: "EUR",
            make: "Honda",
            model: "CB500",
            year: 2022,
            vehicleClass: .motorcycle,
            purchasePrice: Decimal(string: "6500.25")!,
            purchaseDate: CalendarDate(year: 2022, month: 6, day: 1),
            depreciationPreset: .classDefault,
            salvageFloorPct: 10
        ))
        let urlRequest = try request(endpoint)
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.url?.path == "/api/v1/vehicles")
        let json = try body(endpoint)
        #expect(json["purchaseDate"] as? String == "2022-06-01")
        #expect(json["vehicleClass"] as? String == "motorcycle")
        #expect(json["depreciationPreset"] as? String == "class-default")
        #expect((json["purchasePrice"] as? NSNumber)?.doubleValue == 6500.25)
        #expect(json["trim"] == nil)
    }

    @Test("Update is a PATCH that sends null only for cleared fields")
    func encodesUpdate() throws {
        let endpoint = Endpoints.vehicleUpdate(id: "v1", VehicleUpdateRequest(
            name: "Renamed",
            trim: .clear,
            depreciationPreset: .custom,
            customAnnualRatePct: .set(12),
            currentMileage: .unchanged
        ))
        let urlRequest = try request(endpoint)
        #expect(urlRequest.httpMethod == "PATCH")
        #expect(urlRequest.url?.path == "/api/v1/vehicles/v1")
        let json = try body(endpoint)
        #expect(json["name"] as? String == "Renamed")
        #expect(json["trim"] is NSNull)
        #expect(json["depreciationPreset"] as? String == "custom")
        #expect((json["customAnnualRatePct"] as? NSNumber)?.intValue == 12)
        #expect(json.keys.contains("currentMileage") == false)
        #expect(json.keys.contains("make") == false)
    }

    @Test("A value override posts the target balance to the account")
    func encodesOverride() throws {
        let endpoint = Endpoints.vehicleValueOverride(
            accountId: "acc1",
            VehicleValueOverrideRequest(targetBalance: 12000, note: "Dealer quote")
        )
        let urlRequest = try request(endpoint)
        #expect(urlRequest.url?.path == "/api/v1/accounts/acc1/balance-adjustment")
        let json = try body(endpoint)
        #expect((json["targetBalance"] as? NSNumber)?.intValue == 12000)
        #expect(json["note"] as? String == "Dealer quote")
    }

    @Test("Override history asks for transfers on the account and keeps out-of-wallet ones")
    func overrideHistoryQuery() throws {
        let urlRequest = try request(Endpoints.vehicleValueOverrides(accountId: "acc1"))
        let query = try #require(urlRequest.url?.query)
        #expect(query.contains("accountIds=acc1"))
        #expect(query.contains("transferFilter=only"))
    }

    @Test("Default curve: one full year of a sedan loses 20%")
    func depreciationFirstYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let start = CalendarDate(year: 2020, month: 1, day: 1).startDate(in: calendar)
        let oneYear = CalendarDate(year: 2021, month: 1, day: 1).startDate(in: calendar)
        let value = VehicleDepreciation.value(
            anchorValue: 10000,
            anchorDate: start,
            asOf: oneYear,
            vehicleClass: .sedan,
            preset: .classDefault,
            customAnnualRatePct: nil,
            floor: 0,
            calendar: calendar
        )
        #expect(abs(value - 8000) < 0.001)
    }

    @Test("Presets scale the curve, custom rates are flat, and the floor holds")
    func depreciationPresetsAndFloor() throws {
        #expect(abs(VehicleDepreciation.annualRate(vehicleClass: .sedan, preset: .slow, customAnnualRatePct: nil, yearIndex: 0) - 0.14) < 0.0001)
        #expect(abs(VehicleDepreciation.annualRate(vehicleClass: .truck, preset: .fast, customAnnualRatePct: nil, yearIndex: 0) - 0.195) < 0.0001)
        #expect(abs(VehicleDepreciation.annualRate(vehicleClass: .sedan, preset: .average, customAnnualRatePct: nil, yearIndex: 20) - 0.04) < 0.0001)
        #expect(VehicleDepreciation.annualRate(vehicleClass: .luxury, preset: .custom, customAnnualRatePct: 30, yearIndex: 5) == 0.3)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let start = CalendarDate(year: 2000, month: 1, day: 1).startDate(in: calendar)
        let later = CalendarDate(year: 2030, month: 1, day: 1).startDate(in: calendar)
        let floored = VehicleDepreciation.value(
            anchorValue: 10000,
            anchorDate: start,
            asOf: later,
            vehicleClass: .sedan,
            preset: .custom,
            customAnnualRatePct: 50,
            floor: 1000,
            calendar: calendar
        )
        #expect(floored == 1000)
    }

    @Test("An override splits the timeline with a vertical step on its date")
    func timelineWithOverride() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let purchase = CalendarDate(year: 2020, month: 1, day: 1).startDate(in: calendar)
        let overrideDate = CalendarDate(year: 2021, month: 1, day: 1).startDate(in: calendar)
        let timeline = VehicleDepreciation.timeline(
            purchaseValue: 10000,
            purchaseDate: purchase,
            override: VehicleDepreciationPoint(date: overrideDate, value: 9500),
            vehicleClass: .sedan,
            preset: .classDefault,
            customAnnualRatePct: nil,
            salvageFloorPct: 10,
            monthsHorizon: 12,
            calendar: calendar
        )
        #expect(timeline.first?.value == 10000)
        let onOverride = timeline.filter { $0.date == overrideDate }
        // The curve value, then the override value, on the same date.
        #expect(onOverride.count == 2)
        #expect(abs((onOverride.first?.value ?? 0) - 8000) < 0.001)
        #expect(onOverride.last?.value == 9500)
        // Purchase plus 12 monthly points, the override, then 12 more months.
        #expect(timeline.count == 26)
        #expect(timeline.last.map { $0.value < 9500 } == true)
    }
}
