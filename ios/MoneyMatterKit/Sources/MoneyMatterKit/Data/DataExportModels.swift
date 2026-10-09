import Foundation

public enum DataExportFormat: String, Sendable, Hashable, Codable, CaseIterable {
    case json, csv, xlsx
}

public enum DataExportGroup: String, Sendable, Hashable, Codable, CaseIterable {
    case transactions, budgets, subscriptions, investments
}

public struct DataExportDateRange: Sendable, Hashable, Encodable {
    public var from: CalendarDate?
    public var to: CalendarDate?

    public init(from: CalendarDate?, to: CalendarDate?) {
        self.from = from
        self.to = to
    }

    private enum CodingKeys: String, CodingKey { case from, to }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(from?.description, forKey: .from)
        try container.encodeIfPresent(to?.description, forKey: .to)
    }
}

/// Body of `POST /user/data-export`. Empty `accountIds` means every account.
public struct DataExportRequest: Sendable, Hashable, Encodable {
    public var format: DataExportFormat
    public var groups: [DataExportGroup]
    public var dateRange: DataExportDateRange?
    public var accountIds: [String]?

    public init(format: DataExportFormat, groups: [DataExportGroup], dateRange: DataExportDateRange? = nil, accountIds: [String]? = nil) {
        self.format = format
        self.groups = groups
        self.dateRange = dateRange
        self.accountIds = (accountIds?.isEmpty ?? true) ? nil : accountIds
    }
}

/// The generated zip, with the server's filename and row count.
public struct DataExportFile: Sendable {
    public let data: Data
    public let filename: String
    public let totalRows: Int?

    public static let defaultFilename = "moneymatter-export.zip"

    /// Reads `filename="..."` from a `Content-Disposition` header.
    public static func filename(fromContentDisposition header: String?) -> String {
        guard let header, let range = header.range(of: "filename=") else { return defaultFilename }
        let raw = header[range.upperBound...]
            .split(separator: ";").first.map(String.init) ?? ""
        let name = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        let safe = name.replacingOccurrences(of: "/", with: "_")
        return safe.isEmpty ? defaultFilename : safe
    }

    /// `X-Total-Rows` when it's a plain non-negative integer.
    public static func totalRows(fromHeader header: String?) -> Int? {
        guard let header, !header.isEmpty, header.allSatisfy(\.isNumber) else { return nil }
        return Int(header)
    }
}
