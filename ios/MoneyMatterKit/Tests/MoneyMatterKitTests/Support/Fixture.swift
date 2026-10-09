import Foundation
@testable import MoneyMatterKit

/// Loads JSON fixtures that mirror the API contract's response bodies.
enum Fixture {
    static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url)
        else {
            fatalError("Missing fixture \(name).json")
        }
        return data
    }

    /// Decodes a fixture the way `APIClient` would for an endpoint with this format.
    static func decode<Value: Decodable>(_ type: Value.Type, from name: String, format: ResponseFormat = .envelope) throws -> Value {
        try ResponseDecoding.decode(type, from: data(name), format: format, decoder: JSONCoding.makeDecoder())
    }

    /// Runs an endpoint's own decoder over a fixture, including any `map` it applies.
    static func decode<Value>(_ endpoint: Endpoint<Value>, from name: String) throws -> Value {
        try endpoint.decodeBody(data(name), JSONCoding.makeDecoder())
    }
}

extension Transaction {
    /// A minimal row for tests that only care about identity.
    static func stub(id: String) -> Transaction {
        Transaction(
            id: id,
            amount: 10,
            time: Date(timeIntervalSince1970: 1_760_000_000),
            transactionType: .expense,
            accountId: "acc-1",
            currencyCode: "EUR",
            reviewStatus: .unreviewed
        )
    }

    static func stubs(prefix: String, count: Int) -> [Transaction] {
        (0..<count).map { stub(id: "\(prefix)-\($0 + 1)") }
    }
}

extension Date {
    /// Parses a fixture timestamp, failing loudly on typos.
    static func iso(_ string: String) -> Date {
        guard let date = APIDateFormat.parseTimestamp(string) else { fatalError("Bad date \(string)") }
        return date
    }
}
