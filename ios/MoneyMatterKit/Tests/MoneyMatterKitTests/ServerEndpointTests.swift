import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("ServerEndpoint and dates")
struct ServerEndpointTests {
    @Test("Normalizes to an origin and derives the API base")
    func normalizes() throws {
        let server = try ServerEndpoint(validating: "  https://Budget.PKrishna.dev/some/path?x=1  ")
        #expect(server.originString == "https://budget.pkrishna.dev")
        #expect(server.apiBaseURL.absoluteString == "https://budget.pkrishna.dev/api/v1")
        #expect(server.host == "budget.pkrishna.dev")
    }

    @Test("Adds https when the scheme is missing")
    func defaultsToHTTPS() throws {
        let server = try ServerEndpoint(validating: "budget.pkrishna.dev")
        #expect(server.originString == "https://budget.pkrishna.dev")
    }

    @Test("Keeps an explicit port")
    func port() throws {
        let server = try ServerEndpoint(validating: "http://localhost:8081")
        #expect(server.originString == "http://localhost:8081")
        #expect(server.hostAndPort == "localhost:8081")
    }

    @Test("Drops an explicit default port so the Origin matches the trusted origin")
    func defaultPort() throws {
        #expect(try ServerEndpoint(validating: "https://budget.pkrishna.dev:443").originString == "https://budget.pkrishna.dev")
        #expect(try ServerEndpoint(validating: "http://localhost:80").originString == "http://localhost")
        #expect(try ServerEndpoint(validating: "https://budget.pkrishna.dev:8443").hostAndPort == "budget.pkrishna.dev:8443")
    }

    @Test("Allows http only for local hosts", arguments: ["http://localhost", "http://127.0.0.1:3000", "http://mac-mini.local:8081"])
    func localHTTP(input: String) throws {
        _ = try ServerEndpoint(validating: input)
    }

    @Test("Rejects http for public hosts")
    func publicHTTP() {
        #expect(throws: ServerURLError.insecureScheme) {
            _ = try ServerEndpoint(validating: "http://budget.pkrishna.dev")
        }
    }

    @Test("Rejects input that isn't a server URL", arguments: ["", "   ", "ftp://example.com", "https://"])
    func invalid(input: String) {
        #expect(throws: ServerURLError.invalid) {
            _ = try ServerEndpoint(validating: input)
        }
    }

    @Test("Calendar dates parse days and timestamp prefixes")
    func calendarDates() {
        #expect(CalendarDate(string: "2026-10-09") == CalendarDate(year: 2026, month: 10, day: 9))
        #expect(CalendarDate(string: "2026-10-09T23:59:59.000Z") == CalendarDate(year: 2026, month: 10, day: 9))
        #expect(CalendarDate(string: "2026-13-01") == nil)
        #expect(CalendarDate(year: 2026, month: 3, day: 7).description == "2026-03-07")
        #expect(CalendarDate(year: 2026, month: 1, day: 31) < CalendarDate(year: 2026, month: 2, day: 1))
    }

    @Test("Month periods know their bounds and neighbours")
    func monthPeriods() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let february = MonthPeriod(year: 2028, month: 2)
        #expect(february.firstDay == CalendarDate(year: 2028, month: 2, day: 1))
        #expect(february.lastDay(calendar: calendar) == CalendarDate(year: 2028, month: 2, day: 29))
        #expect(MonthPeriod(year: 2026, month: 1).previous == MonthPeriod(year: 2025, month: 12))
        #expect(MonthPeriod(year: 2026, month: 12).next == MonthPeriod(year: 2027, month: 1))
    }

    @Test("Timestamps parse with and without fractional seconds and format with milliseconds")
    func timestamps() {
        let withMillis = APIDateFormat.parseTimestamp("2026-10-09T08:15:00.123Z")
        let withoutMillis = APIDateFormat.parseTimestamp("2026-10-09T08:15:00Z")
        #expect(withMillis != nil)
        #expect(withoutMillis != nil)
        #expect(APIDateFormat.timestampString(from: withoutMillis!) == "2026-10-09T08:15:00.000Z")
        #expect(APIDateFormat.parseTimestamp("not a date") == nil)
    }
}
