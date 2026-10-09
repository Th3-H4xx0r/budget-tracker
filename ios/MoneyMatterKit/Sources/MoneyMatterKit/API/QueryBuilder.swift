import Foundation

/// Builds query items following the contract's conventions: comma-joined lists, empty
/// values omitted, ISO UTC timestamps, and `YYYY-MM-DD` days.
public struct QueryBuilder: Sendable {
    public private(set) var items: [URLQueryItem] = []

    public init() {}

    public mutating func add(_ name: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        items.append(URLQueryItem(name: name, value: value))
    }

    public mutating func add(_ name: String, _ value: Int?) {
        guard let value else { return }
        add(name, String(value))
    }

    public mutating func add(_ name: String, _ value: Decimal?) {
        guard let value else { return }
        add(name, NSDecimalNumber(decimal: value).stringValue)
    }

    /// Sends `true` or `false`. Use only where the server parses booleans strictly.
    public mutating func add(_ name: String, _ value: Bool?) {
        guard let value else { return }
        add(name, value ? "true" : "false")
    }

    /// Sends `true` only. For `z.coerce.boolean()` params, where the string `"false"`
    /// would read as true, and for opt-in `include*` flags.
    public mutating func addFlag(_ name: String, _ isOn: Bool) {
        if isOn { add(name, "true") }
    }

    /// Comma-joins the values; an empty list sends nothing.
    public mutating func add(_ name: String, list: [String]?) {
        guard let list, !list.isEmpty else { return }
        add(name, list.joined(separator: ","))
    }

    public mutating func add(_ name: String, timestamp: Date?) {
        guard let timestamp else { return }
        add(name, APIDateFormat.timestampString(from: timestamp))
    }

    public mutating func add(_ name: String, day: CalendarDate?) {
        guard let day else { return }
        add(name, day.description)
    }

    /// Percent-encodes the items, leaving `,` and `:` readable.
    static func percentEncodedQuery(_ items: [URLQueryItem]) -> String? {
        guard !items.isEmpty else { return nil }
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~,:"
        )
        return items.map { item in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? item.name
            let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(name)=\(value)"
        }
        .joined(separator: "&")
    }
}
