import Foundation

/// The security a parsed symbol resolved to. Round-trips unchanged into the execute call.
public struct InvestmentImportSecurity: Codable, Sendable, Hashable {
    public var securityId: String?
    public var providerSymbol: String
    public var symbol: String
    public var name: String
    public var assetClass: String
    public var providerName: String
    public var currencyCode: String
    public var exchangeName: String?
    public var cryptoCurrencyCode: String?
    public var alreadyInDb: Bool

    public init(
        securityId: String? = nil,
        providerSymbol: String,
        symbol: String,
        name: String,
        assetClass: String,
        providerName: String,
        currencyCode: String,
        exchangeName: String? = nil,
        cryptoCurrencyCode: String? = nil,
        alreadyInDb: Bool = false
    ) {
        self.securityId = securityId
        self.providerSymbol = providerSymbol
        self.symbol = symbol
        self.name = name
        self.assetClass = assetClass
        self.providerName = providerName
        self.currencyCode = currencyCode
        self.exchangeName = exchangeName
        self.cryptoCurrencyCode = cryptoCurrencyCode
        self.alreadyInDb = alreadyInDb
    }
}

/// One parsed trade. Amounts are decimal strings, as the server sends and expects them.
public struct InvestmentImportTransaction: Codable, Sendable, Hashable, Identifiable {
    public var tempId: String
    public var date: String
    /// `buy`, `sell`, `dividend`, or another `INVESTMENT_TRANSACTION_CATEGORY` value.
    public var side: String
    public var quantity: String
    public var price: String
    public var fees: String
    public var amount: String
    public var possibleDuplicateOf: String?

    public var id: String { tempId }

    /// Only buys, sells, and dividends can be imported.
    public var isImportable: Bool { InvestmentImportTransaction.importableSides.contains(side) }

    public static let importableSides: Set<String> = ["buy", "sell", "dividend"]

    public var amountValue: Decimal { Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    public var quantityValue: Decimal { Decimal(string: quantity, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    public var priceValue: Decimal { Decimal(string: price, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
}

/// A parsed symbol and its trades.
public struct InvestmentImportHolding: Codable, Sendable, Hashable, Identifiable {
    public var tempId: String
    public var parsedSymbol: String
    public var parsedName: String?
    public var resolvedSecurity: InvestmentImportSecurity?
    /// `auto`, `ambiguous`, or `unmapped`.
    public var resolvedConfidence: String
    public var portfolioId: String
    public var currencyCode: String?
    public var hasExistingHolding: Bool
    public var transactions: [InvestmentImportTransaction]

    public var id: String { tempId }

    private enum CodingKeys: String, CodingKey {
        case tempId, parsedSymbol, parsedName, resolvedSecurity, resolvedConfidence, portfolioId
        case currencyCode, hasExistingHolding, transactions
    }

    public init(
        tempId: String,
        parsedSymbol: String,
        parsedName: String? = nil,
        resolvedSecurity: InvestmentImportSecurity? = nil,
        resolvedConfidence: String = "unmapped",
        portfolioId: String,
        currencyCode: String? = nil,
        hasExistingHolding: Bool = false,
        transactions: [InvestmentImportTransaction]
    ) {
        self.tempId = tempId
        self.parsedSymbol = parsedSymbol
        self.parsedName = parsedName
        self.resolvedSecurity = resolvedSecurity
        self.resolvedConfidence = resolvedConfidence
        self.portfolioId = portfolioId
        self.currencyCode = currencyCode
        self.hasExistingHolding = hasExistingHolding
        self.transactions = transactions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tempId = try container.decode(String.self, forKey: .tempId)
        parsedSymbol = try container.decode(String.self, forKey: .parsedSymbol)
        parsedName = try container.decodeIfPresent(String.self, forKey: .parsedName)
        resolvedSecurity = try? container.decodeIfPresent(InvestmentImportSecurity.self, forKey: .resolvedSecurity)
        resolvedConfidence = try container.decodeIfPresent(String.self, forKey: .resolvedConfidence) ?? "unmapped"
        portfolioId = try container.decode(String.self, forKey: .portfolioId)
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode)
        hasExistingHolding = try container.decodeIfPresent(Bool.self, forKey: .hasExistingHolding) ?? false
        transactions = try container.decodeLossyArrayIfPresent([InvestmentImportTransaction].self, forKey: .transactions) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tempId, forKey: .tempId)
        try container.encode(parsedSymbol, forKey: .parsedSymbol)
        try container.encode(parsedName, forKey: .parsedName)
        try container.encode(resolvedSecurity, forKey: .resolvedSecurity)
        try container.encode(resolvedConfidence, forKey: .resolvedConfidence)
        try container.encode(portfolioId, forKey: .portfolioId)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(hasExistingHolding, forKey: .hasExistingHolding)
        try container.encode(transactions, forKey: .transactions)
    }

    /// Ready to import: resolved to a security, with at least one importable trade.
    public var isImportable: Bool {
        resolvedSecurity != nil && transactions.contains(where: \.isImportable)
    }
}

/// `POST /investments/transactions-import/extract` reply.
public struct InvestmentImportExtraction: Decodable, Sendable, Hashable {
    public let holdings: [InvestmentImportHolding]
    public let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case holdings, warnings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holdings = try container.decodeLossyArrayIfPresent([InvestmentImportHolding].self, forKey: .holdings) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

/// `POST /investments/transactions-import/execute` reply.
public struct InvestmentImportResult: Decodable, Sendable, Hashable {
    public let createdSecurities: Int
    public let createdHoldings: Int
    public let mergedHoldings: Int
    public let createdTransactions: Int
    public let skippedPossibleDuplicates: Int
    public let skippedHoldings: Int
    public let failedTransactions: Int
    public let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case createdSecurities, createdHoldings, mergedHoldings, createdTransactions
        case skippedPossibleDuplicates, skippedHoldings, failedTransactions, warnings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdSecurities = try container.decodeIfPresent(Int.self, forKey: .createdSecurities) ?? 0
        createdHoldings = try container.decodeIfPresent(Int.self, forKey: .createdHoldings) ?? 0
        mergedHoldings = try container.decodeIfPresent(Int.self, forKey: .mergedHoldings) ?? 0
        createdTransactions = try container.decodeIfPresent(Int.self, forKey: .createdTransactions) ?? 0
        skippedPossibleDuplicates = try container.decodeIfPresent(Int.self, forKey: .skippedPossibleDuplicates) ?? 0
        skippedHoldings = try container.decodeIfPresent(Int.self, forKey: .skippedHoldings) ?? 0
        failedTransactions = try container.decodeIfPresent(Int.self, forKey: .failedTransactions) ?? 0
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

/// Which CSV columns hold which fields, and how the side column's values map to sides.
public struct InvestmentImportColumnMapping: Encodable, Sendable, Hashable {
    public var symbol: String
    public var date: String
    public var side: String
    public var quantity: String
    public var price: String
    public var fees: String?
    public var currency: String?
    public var name: String?
    public var defaultCurrency: String?
    /// `stocks` or `crypto`.
    public var defaultAssetClassHint: String
    /// Side-column value → `buy`, `sell`, `dividend`, …, or `skip`.
    public var sideValueMapping: [String: String]

    public init(
        symbol: String,
        date: String,
        side: String,
        quantity: String,
        price: String,
        fees: String? = nil,
        currency: String? = nil,
        name: String? = nil,
        defaultCurrency: String? = nil,
        defaultAssetClassHint: String = "stocks",
        sideValueMapping: [String: String] = [:]
    ) {
        self.symbol = symbol
        self.date = date
        self.side = side
        self.quantity = quantity
        self.price = price
        self.fees = fees
        self.currency = currency
        self.name = name
        self.defaultCurrency = defaultCurrency
        self.defaultAssetClassHint = defaultAssetClassHint
        self.sideValueMapping = sideValueMapping
    }

    private enum CodingKeys: String, CodingKey {
        case symbol, date, side, quantity, price, fees, currency, name, defaultCurrency
        case defaultAssetClassHint, sideValueMapping
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(date, forKey: .date)
        try container.encode(side, forKey: .side)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(price, forKey: .price)
        try container.encode(fees, forKey: .fees)
        try container.encode(currency, forKey: .currency)
        try container.encode(name, forKey: .name)
        try container.encode(defaultCurrency, forKey: .defaultCurrency)
        try container.encode(defaultAssetClassHint, forKey: .defaultAssetClassHint)
        try container.encode(sideValueMapping, forKey: .sideValueMapping)
    }

    /// A best guess for a side-column value: `buy`, `sell`, `dividend`, `fee`, `tax`, or `skip`.
    public static func guessSide(for value: String) -> String {
        let lower = value.lowercased()
        if lower.contains("buy") || lower.contains("purchase") || lower == "b" { return "buy" }
        if lower.contains("sell") || lower.contains("sale") || lower == "s" { return "sell" }
        if lower.contains("div") { return "dividend" }
        return "skip"
    }
}

/// `POST /investments/transactions-import/extract` body.
struct InvestmentImportExtractRequest: Encodable, Sendable {
    let source: String
    let fileBase64: String
    let defaultPortfolioId: String
    let columnMapping: InvestmentImportColumnMapping?
}

/// `POST /investments/transactions-import/execute` body.
public struct InvestmentImportExecuteRequest: Encodable, Sendable, Hashable {
    public var holdings: [InvestmentImportHolding]
    public var skipTempIds: [String]

    /// Keeps resolved holdings and their importable trades only, since the server rejects
    /// other sides and empty holdings.
    public init(holdings: [InvestmentImportHolding], skipTempIds: Set<String>) {
        self.holdings = holdings.compactMap { holding in
            guard holding.resolvedSecurity != nil else { return nil }
            var copy = holding
            copy.transactions = holding.transactions.filter(\.isImportable)
            return copy.transactions.isEmpty ? nil : copy
        }
        self.skipTempIds = skipTempIds.sorted()
    }
}

/// A CSV file read on the device: its headers and rows, keyed by header.
public struct InvestmentImportCSV: Sendable, Hashable {
    public let headers: [String]
    public let rows: [[String: String]]

    /// The server's row limit.
    public static let maxRows = 50_000

    public enum ParseError: Error, Sendable, Equatable {
        case empty
        case noHeaders
        case tooManyRows
    }

    /// Parses `text`, detecting `,`, `;`, or tab from the header line, and honouring
    /// double-quoted fields with `""` escapes. Blank lines are skipped.
    public static func parse(_ text: String) throws(ParseError) -> InvestmentImportCSV {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        let firstLine = trimmed.prefix { $0 != "\n" && $0 != "\r" }
        let delimiter: Character = [",", ";", "\t"].max { a, b in
            firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count
        } ?? ","

        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(trimmed).makeIterator()
        var pending: Character? = iterator.next()
        while let char = pending {
            pending = iterator.next()
            if inQuotes {
                if char == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" {
                inQuotes = true
            } else if char == delimiter {
                record.append(field)
                field = ""
            } else if char == "\n" || char == "\r" || char == "\r\n" {
                record.append(field)
                field = ""
                if !record.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    records.append(record)
                }
                record = []
            } else {
                field.append(char)
            }
        }
        record.append(field)
        if !record.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            records.append(record)
        }

        guard let headerRow = records.first else { throw .empty }
        let rawHeaders = headerRow.map { $0.trimmingCharacters(in: .whitespaces) }
        guard !rawHeaders.allSatisfy(\.isEmpty) else { throw .noHeaders }
        let headers = rawHeaders.enumerated().map { index, header in
            header.isEmpty ? "Column \(index + 1)" : header
        }
        let dataRows = records.dropFirst()
        guard dataRows.count <= maxRows else { throw .tooManyRows }
        let rows = dataRows.map { values in
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                row[header] = index < values.count ? values[index].trimmingCharacters(in: .whitespaces) : ""
            }
            return row
        }
        return InvestmentImportCSV(headers: headers, rows: rows)
    }

    /// The distinct non-empty values of one column, in first-seen order.
    public func distinctValues(of column: String) -> [String] {
        var seen = Set<String>()
        var values: [String] = []
        for row in rows {
            guard let value = row[column], !value.isEmpty, seen.insert(value).inserted else { continue }
            values.append(value)
        }
        return values
    }

    /// The header most likely to hold a field, matched case-insensitively against `candidates`.
    public func guessColumn(_ candidates: [String]) -> String? {
        for candidate in candidates {
            if let match = headers.first(where: { $0.lowercased() == candidate }) { return match }
        }
        for candidate in candidates {
            if let match = headers.first(where: { $0.lowercased().contains(candidate) }) { return match }
        }
        return nil
    }
}

extension Endpoints {
    /// `POST /investments/transactions-import/extract` with a mapped CSV.
    public static func investmentImportExtractCSV(
        fileData: Data,
        portfolioId: String,
        mapping: InvestmentImportColumnMapping
    ) -> Endpoint<InvestmentImportExtraction> {
        Endpoint(.post, "/investments/transactions-import/extract", body: InvestmentImportExtractRequest(
            source: "csv",
            fileBase64: fileData.base64EncodedString(),
            defaultPortfolioId: portfolioId,
            columnMapping: mapping
        ))
    }

    /// `POST /investments/transactions-import/extract` read by the user's AI model, for
    /// statements that aren't CSV (e.g. PDF).
    public static func investmentImportExtractAI(fileData: Data, portfolioId: String) -> Endpoint<InvestmentImportExtraction> {
        Endpoint(.post, "/investments/transactions-import/extract", body: InvestmentImportExtractRequest(
            source: "ai",
            fileBase64: fileData.base64EncodedString(),
            defaultPortfolioId: portfolioId,
            columnMapping: nil
        ))
    }

    /// `POST /investments/transactions-import/execute`.
    public static func investmentImportExecute(_ request: InvestmentImportExecuteRequest) -> Endpoint<InvestmentImportResult> {
        Endpoint(.post, "/investments/transactions-import/execute", body: request)
    }
}
