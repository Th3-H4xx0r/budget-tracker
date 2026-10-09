import Foundation

/// Date handling shared by every request and response.
///
/// The API sends timestamps as ISO-8601 with milliseconds and `Z`, and expects the same
/// format back (offsets are rejected on `/transactions`).
public enum APIDateFormat {
    private static let withFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFractionalSeconds = Date.ISO8601FormatStyle()

    /// Parses a timestamp with or without fractional seconds, or a bare `YYYY-MM-DD`
    /// (read as UTC midnight).
    public static func parseTimestamp(_ string: String) -> Date? {
        if let date = try? withFractionalSeconds.parse(string) { return date }
        if let date = try? withoutFractionalSeconds.parse(string) { return date }
        if let day = CalendarDate(string: string) {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = .gmt
            return day.startDate(in: utc)
        }
        return nil
    }

    /// `2026-10-09T08:15:00.000Z`.
    public static func timestampString(from date: Date) -> String {
        withFractionalSeconds.format(date)
    }
}

/// Configured coders. JSON numbers decode straight into `Decimal`, so amounts keep
/// their exact decimal digits.
public enum JSONCoding {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = APIDateFormat.parseTimestamp(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognized date: \(string)"
                )
            }
            return date
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(APIDateFormat.timestampString(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
