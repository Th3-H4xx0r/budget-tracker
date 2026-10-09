import Foundation

/// A day with no time or zone, as used by `YYYY-MM-DD` fields and `/stats/*` params.
public struct CalendarDate: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Accepts `YYYY-MM-DD`, or a full ISO timestamp whose first ten characters are the date.
    public init?(string: String) {
        let parts = string.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day `date` falls on in `calendar`'s time zone.
    public init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// Midnight at the start of this day in `calendar`'s time zone.
    public func startDate(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public func adding(days: Int, calendar: Calendar = .current) -> CalendarDate {
        let date = calendar.date(byAdding: .day, value: days, to: startDate(in: calendar)) ?? startDate(in: calendar)
        return CalendarDate(date: date, calendar: calendar)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = CalendarDate(string: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// One calendar month, used for the month period selector and `/stats` ranges.
public struct MonthPeriod: Sendable, Hashable, Comparable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(containing date: Date, calendar: Calendar = .current) {
        let day = CalendarDate(date: date, calendar: calendar)
        self.init(year: day.year, month: day.month)
    }

    public var firstDay: CalendarDate { CalendarDate(year: year, month: month, day: 1) }

    public func lastDay(calendar: Calendar = .current) -> CalendarDate {
        next.firstDay.adding(days: -1, calendar: calendar)
    }

    public var previous: MonthPeriod {
        month == 1 ? MonthPeriod(year: year - 1, month: 12) : MonthPeriod(year: year, month: month - 1)
    }

    public var next: MonthPeriod {
        month == 12 ? MonthPeriod(year: year + 1, month: 1) : MonthPeriod(year: year, month: month + 1)
    }

    public static func < (lhs: MonthPeriod, rhs: MonthPeriod) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}
