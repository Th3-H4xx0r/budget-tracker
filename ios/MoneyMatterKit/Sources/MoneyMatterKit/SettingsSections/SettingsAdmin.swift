import Foundation

/// A security from `GET /investments/securities/search`. The bulk upload echoes it back so
/// the server can find or create the security, so every field is kept as sent.
public struct SettingsAdminSecurity: Sendable, Hashable, Identifiable, Codable {
    public let symbol: String
    public let providerSymbol: String
    public let name: String
    public let assetClass: String
    public let providerName: String
    public let exchangeAcronym: String?
    public let exchangeMic: String?
    public let exchangeName: String?
    public let currencyCode: String
    public let cryptoCurrencyCode: String?
    public let cusip: String?
    public let isin: String?
    public let logoUrl: String?
    public let matchType: String?
    public let marketCapRank: Int?

    public var id: String { "\(providerName):\(providerSymbol):\(exchangeMic ?? exchangeAcronym ?? "")" }

    public init(
        symbol: String,
        providerSymbol: String,
        name: String,
        assetClass: String,
        providerName: String,
        currencyCode: String,
        exchangeAcronym: String? = nil,
        exchangeMic: String? = nil,
        exchangeName: String? = nil,
        cryptoCurrencyCode: String? = nil,
        cusip: String? = nil,
        isin: String? = nil,
        logoUrl: String? = nil,
        matchType: String? = nil,
        marketCapRank: Int? = nil
    ) {
        self.symbol = symbol
        self.providerSymbol = providerSymbol
        self.name = name
        self.assetClass = assetClass
        self.providerName = providerName
        self.currencyCode = currencyCode
        self.exchangeAcronym = exchangeAcronym
        self.exchangeMic = exchangeMic
        self.exchangeName = exchangeName
        self.cryptoCurrencyCode = cryptoCurrencyCode
        self.cusip = cusip
        self.isin = isin
        self.logoUrl = logoUrl
        self.matchType = matchType
        self.marketCapRank = marketCapRank
    }

    private enum CodingKeys: String, CodingKey {
        case symbol, providerSymbol, name, assetClass, providerName, exchangeAcronym, exchangeMic
        case exchangeName, currencyCode, cryptoCurrencyCode, cusip, isin, logoUrl, matchType, marketCapRank
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(String.self, forKey: .symbol)
        providerSymbol = (try? container.decodeIfPresent(String.self, forKey: .providerSymbol)) ?? symbol
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? symbol
        assetClass = (try? container.decodeIfPresent(String.self, forKey: .assetClass)) ?? "other"
        providerName = (try? container.decodeIfPresent(String.self, forKey: .providerName)) ?? ""
        exchangeAcronym = try? container.decodeIfPresent(String.self, forKey: .exchangeAcronym)
        exchangeMic = try? container.decodeIfPresent(String.self, forKey: .exchangeMic)
        exchangeName = try? container.decodeIfPresent(String.self, forKey: .exchangeName)
        currencyCode = (try? container.decodeIfPresent(String.self, forKey: .currencyCode)) ?? ""
        cryptoCurrencyCode = try? container.decodeIfPresent(String.self, forKey: .cryptoCurrencyCode)
        cusip = try? container.decodeIfPresent(String.self, forKey: .cusip)
        isin = try? container.decodeIfPresent(String.self, forKey: .isin)
        logoUrl = try? container.decodeIfPresent(String.self, forKey: .logoUrl)
        matchType = try? container.decodeIfPresent(String.self, forKey: .matchType)
        marketCapRank = try? container.decodeIfPresent(Int.self, forKey: .marketCapRank)
    }
}

/// `POST /investments/securities/price-upload-info`: the date range exchange rates cover
/// for the security's currency. Dates are `YYYY-MM-DD` or ISO strings, as the server sends them.
public struct SettingsAdminPriceUploadInfo: Sendable, Hashable, Decodable {
    public let oldestDate: String?
    public let newestDate: String?
    public let currencyCode: String?
    public let minAllowedDate: String?

    public init(oldestDate: String?, newestDate: String?, currencyCode: String?, minAllowedDate: String?) {
        self.oldestDate = oldestDate
        self.newestDate = newestDate
        self.currencyCode = currencyCode
        self.minAllowedDate = minAllowedDate
    }

    /// The `YYYY-MM-DD` part of a server date.
    public static func day(_ value: String?) -> String? {
        value.map { String($0.prefix(10)) }
    }
}

/// One row of the bulk upload.
public struct SettingsAdminPriceRow: Sendable, Hashable, Codable {
    public let price: Decimal
    /// `YYYY-MM-DD`.
    public let date: String
    public let currency: String

    public init(price: Decimal, date: String, currency: String) {
        self.price = price
        self.date = date
        self.currency = currency
    }
}

/// `POST /investments/securities/prices/bulk-upload` body.
public struct SettingsAdminBulkUploadRequest: Encodable, Sendable, Hashable {
    public let searchResult: SettingsAdminSecurity
    public let prices: [SettingsAdminPriceRow]
    /// Drop dates outside the available exchange-rate range instead of failing.
    public let autoFilter: Bool
    /// Update existing prices for the same dates instead of skipping them.
    public let override: Bool

    public init(searchResult: SettingsAdminSecurity, prices: [SettingsAdminPriceRow], autoFilter: Bool, override: Bool) {
        self.searchResult = searchResult
        self.prices = prices
        self.autoFilter = autoFilter
        self.override = override
    }
}

public struct SettingsAdminBulkUploadResult: Sendable, Hashable, Decodable {
    public struct Summary: Sendable, Hashable, Decodable {
        public let inserted: Int
        public let duplicates: Int
        public let filtered: Int

        private enum CodingKeys: String, CodingKey { case inserted, duplicates, filtered }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inserted = (try? container.decodeIfPresent(Int.self, forKey: .inserted)) ?? 0
            duplicates = (try? container.decodeIfPresent(Int.self, forKey: .duplicates)) ?? 0
            filtered = (try? container.decodeIfPresent(Int.self, forKey: .filtered)) ?? 0
        }
    }

    public let newOldestDate: String?
    public let newNewestDate: String?
    public let summary: Summary
}

/// A parsed price file: header names plus one dictionary per row.
public struct SettingsAdminPriceFile: Sendable, Hashable {
    public let fields: [String]
    public let rows: [[String: String]]

    public init(fields: [String], rows: [[String: String]]) {
        self.fields = fields
        self.rows = rows
    }

    public enum ParseError: Error, Equatable {
        case empty
        case invalidJSON
    }

    /// Reads a CSV (header row first, quoted fields with `""` escapes) or a JSON array of objects.
    public static func parse(data: Data, isJSON: Bool) throws -> SettingsAdminPriceFile {
        if isJSON { return try parseJSON(data) }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { throw ParseError.empty }
        let headers = parseLine(headerLine)
        let rows = lines.dropFirst().map { line -> [String: String] in
            let values = parseLine(line)
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                row[header] = index < values.count ? values[index] : ""
            }
            return row
        }
        guard !rows.isEmpty else { throw ParseError.empty }
        return SettingsAdminPriceFile(fields: headers, rows: rows)
    }

    static func parseLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var characters = Array(line)[...]
        while let char = characters.popFirst() {
            if char == "\"" {
                if inQuotes, characters.first == "\"" {
                    current.append("\"")
                    characters.removeFirst()
                } else {
                    inQuotes.toggle()
                }
            } else if char == ",", !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }

    private static func parseJSON(_ data: Data) throws -> SettingsAdminPriceFile {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw ParseError.invalidJSON
        }
        guard let first = array.first else { throw ParseError.empty }
        let fields = first.keys.sorted()
        let rows = array.map { object in
            object.mapValues { value -> String in
                if let string = value as? String { return string }
                if let number = value as? NSNumber { return number.stringValue }
                return ""
            }
        }
        return SettingsAdminPriceFile(fields: fields, rows: rows)
    }
}

/// The fields a price file must provide, and how its columns map onto them.
public enum SettingsAdminPriceField: String, CaseIterable, Sendable, Hashable {
    case price
    case date
}

/// Supported date layouts for the date column.
public enum SettingsAdminDateFormat: String, CaseIterable, Sendable, Hashable, Identifiable {
    case dayMonthYearSlash = "dd/MM/yyyy"
    case monthDayYearSlash = "MM/dd/yyyy"
    case isoDash = "yyyy-MM-dd"
    case dayMonthYearDash = "dd-MM-yyyy"
    case monthDayYearDash = "MM-dd-yyyy"

    public var id: String { rawValue }

    /// The `YYYY-MM-DD` form of `value`, or `nil` when it doesn't match this layout.
    public func normalize(_ value: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.dateFormat = rawValue
        parser.isLenient = false
        guard let date = parser.date(from: value.trimmingCharacters(in: .whitespaces)) else { return nil }
        parser.dateFormat = "yyyy-MM-dd"
        return parser.string(from: date)
    }
}

public struct SettingsAdminPriceMapping: Sendable, Hashable {
    public var columns: [SettingsAdminPriceField: String]
    public var dateFormat: SettingsAdminDateFormat

    public init(columns: [SettingsAdminPriceField: String] = [:], dateFormat: SettingsAdminDateFormat = .dayMonthYearSlash) {
        self.columns = columns
        self.dateFormat = dateFormat
    }

    public var isComplete: Bool { SettingsAdminPriceField.allCases.allSatisfy { columns[$0] != nil } }

    /// Picks the first column whose name equals or contains the field name; `price` also
    /// matches `value` and `amount` columns.
    public static func autoDetect(fields: [String]) -> SettingsAdminPriceMapping {
        var mapping = SettingsAdminPriceMapping()
        for required in SettingsAdminPriceField.allCases {
            let key = required.rawValue
            let match = fields.first { field in
                let lower = field.lowercased()
                return lower == key || lower.contains(key)
                    || (required == .price && (lower.contains("value") || lower.contains("amount")))
            }
            if let match { mapping.columns[required] = match }
        }
        return mapping
    }

    public enum TransformError: Error, Equatable {
        case incompleteMapping
        case invalidDate(row: Int, value: String)
        case invalidPrice(row: Int, value: String)
    }

    /// Builds the upload rows, failing on the first row with an unparseable date or price.
    public func rows(from file: SettingsAdminPriceFile, currency: String) throws -> [SettingsAdminPriceRow] {
        guard let priceColumn = columns[.price], let dateColumn = columns[.date] else {
            throw TransformError.incompleteMapping
        }
        return try file.rows.enumerated().map { index, row in
            let rawDate = row[dateColumn] ?? ""
            guard let date = dateFormat.normalize(rawDate) else {
                throw TransformError.invalidDate(row: index + 1, value: rawDate)
            }
            let rawPrice = (row[priceColumn] ?? "").trimmingCharacters(in: .whitespaces)
            guard let price = Decimal(string: rawPrice, locale: Locale(identifier: "en_US_POSIX")), price > 0 else {
                throw TransformError.invalidPrice(row: index + 1, value: rawPrice)
            }
            return SettingsAdminPriceRow(price: price, date: date, currency: currency)
        }
    }
}

extension Endpoints {
    struct SettingsAdminCurrencyBody: Encodable, Sendable {
        let currencyCode: String
    }

    /// `GET /investments/securities/search`.
    public static func settingsAdminSearchSecurities(query: String) -> Endpoint<[SettingsAdminSecurity]> {
        var builder = QueryBuilder()
        builder.add("query", query)
        return Endpoint(.get, "/investments/securities/search", query: builder.items)
    }

    /// `POST /investments/securities/price-upload-info` (admin only).
    public static func settingsAdminPriceUploadInfo(currencyCode: String) -> Endpoint<SettingsAdminPriceUploadInfo> {
        Endpoint(.post, "/investments/securities/price-upload-info", body: SettingsAdminCurrencyBody(currencyCode: currencyCode))
    }

    /// `POST /investments/securities/prices/bulk-upload` (admin only).
    public static func settingsAdminBulkUploadPrices(_ request: SettingsAdminBulkUploadRequest) -> Endpoint<SettingsAdminBulkUploadResult> {
        Endpoint(.post, "/investments/securities/prices/bulk-upload", body: request)
    }
}
