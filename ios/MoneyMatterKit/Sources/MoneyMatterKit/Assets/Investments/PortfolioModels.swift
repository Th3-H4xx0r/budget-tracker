import Foundation

// Investment models mirroring `packages/shared/src/types/investments`. Investment amounts
// arrive either as JSON numbers (Money fields) or numeric strings (computed summaries), so
// every amount decodes through `invCoreDecimal(forKey:)`.

public enum PortfolioType: String, LenientEnum, CaseIterable {
    case investment
    case retirement
    case savings
    case other
    case unknown
}

public enum InvestmentSecurityAssetClass: String, LenientEnum, CaseIterable {
    case cash
    case crypto
    case fixedIncome = "fixed_income"
    case options
    case stocks
    case other
    case unknown
}

public enum InvestmentSecurityProvider: String, LenientEnum, CaseIterable {
    case polygon
    case alphavantage
    case fmp
    case yahoo
    case coingecko
    case composite
    case unknown
}

public enum InvestmentTransactionCategory: String, LenientEnum, CaseIterable {
    case buy
    case sell
    case dividend
    case transfer
    case tax
    case fee
    case cancel
    case other
    case unknown
}

extension KeyedDecodingContainer {
    /// An amount sent as a JSON number or a numeric string; `nil` when missing, `null`, or unparsable.
    func invCoreDecimal(forKey key: Key) -> Decimal? {
        if let number = try? decodeIfPresent(Decimal.self, forKey: key) { return number }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        }
        return nil
    }

    func invCoreDate(forKey key: Key) -> Date? {
        guard let string = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return APIDateFormat.parseTimestamp(string)
    }
}

public struct Portfolio: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let portfolioType: PortfolioType
    public let description: String?
    /// `nil` means the user's base currency.
    public let displayCurrencyCode: String?
    public let isEnabled: Bool
    public let createdAt: Date?
    public let deletedAt: Date?

    public init(
        id: String,
        name: String,
        portfolioType: PortfolioType = .investment,
        description: String? = nil,
        displayCurrencyCode: String? = nil,
        isEnabled: Bool = true,
        createdAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.portfolioType = portfolioType
        self.description = description
        self.displayCurrencyCode = displayCurrencyCode
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, portfolioType, description, displayCurrencyCode, isEnabled, createdAt, deletedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        portfolioType = try container.decodeLenient(PortfolioType.self, forKey: .portfolioType, default: .unknown)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        displayCurrencyCode = try container.decodeIfPresent(String.self, forKey: .displayCurrencyCode)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = container.invCoreDate(forKey: .createdAt)
        deletedAt = container.invCoreDate(forKey: .deletedAt)
    }
}

/// `GET /investments/portfolios` wraps the list with pagination.
struct PortfolioListPage: Decodable, Sendable {
    let data: [Portfolio]
}

/// `GET /investments/portfolios/:id/summary`: values in `currencyCode` (the display currency).
public struct PortfolioSummary: Decodable, Sendable, Hashable {
    public let portfolioId: String
    public let portfolioName: String
    public let totalCurrentValue: Decimal
    public let totalCostBasis: Decimal
    public let unrealizedGainValue: Decimal
    public let unrealizedGainPercent: Decimal
    public let realizedGainValue: Decimal
    public let realizedGainPercent: Decimal
    public let currencyCode: String
    public let totalCashInBaseCurrency: Decimal
    public let availableCashInBaseCurrency: Decimal
    public let totalPortfolioValue: Decimal
    public let baseCurrencyCode: String
    public let totalPortfolioValueInBaseCurrency: Decimal

    /// Unrealized plus realized gain.
    public var totalReturnValue: Decimal { unrealizedGainValue + realizedGainValue }

    /// Total return as a percentage of the cost basis; `nil` without a cost basis.
    public var totalReturnPercent: Decimal? {
        guard totalCostBasis != 0 else { return nil }
        return totalReturnValue / totalCostBasis * 100
    }

    enum CodingKeys: String, CodingKey {
        case portfolioId, portfolioName, totalCurrentValue, totalCostBasis, unrealizedGainValue
        case unrealizedGainPercent, realizedGainValue, realizedGainPercent, currencyCode
        case totalCashInBaseCurrency, availableCashInBaseCurrency, totalPortfolioValue
        case baseCurrencyCode, totalPortfolioValueInBaseCurrency
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        portfolioId = try container.decodeIfPresent(String.self, forKey: .portfolioId) ?? ""
        portfolioName = try container.decodeIfPresent(String.self, forKey: .portfolioName) ?? ""
        totalCurrentValue = container.invCoreDecimal(forKey: .totalCurrentValue) ?? 0
        totalCostBasis = container.invCoreDecimal(forKey: .totalCostBasis) ?? 0
        unrealizedGainValue = container.invCoreDecimal(forKey: .unrealizedGainValue) ?? 0
        unrealizedGainPercent = container.invCoreDecimal(forKey: .unrealizedGainPercent) ?? 0
        realizedGainValue = container.invCoreDecimal(forKey: .realizedGainValue) ?? 0
        realizedGainPercent = container.invCoreDecimal(forKey: .realizedGainPercent) ?? 0
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? "USD"
        totalCashInBaseCurrency = container.invCoreDecimal(forKey: .totalCashInBaseCurrency) ?? 0
        availableCashInBaseCurrency = container.invCoreDecimal(forKey: .availableCashInBaseCurrency) ?? 0
        totalPortfolioValue = container.invCoreDecimal(forKey: .totalPortfolioValue) ?? 0
        baseCurrencyCode = try container.decodeIfPresent(String.self, forKey: .baseCurrencyCode) ?? currencyCode
        totalPortfolioValueInBaseCurrency = container.invCoreDecimal(forKey: .totalPortfolioValueInBaseCurrency) ?? 0
    }
}

public struct InvestmentSecurity: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let symbol: String?
    public let currencyCode: String
    public let isBrokerageCash: Bool
    public let exchangeName: String?
    public let logoUrl: String?
    public let assetClass: InvestmentSecurityAssetClass
    public let pricingLastSyncedAt: Date?

    /// The ticker, falling back to the name.
    public var displaySymbol: String { symbol ?? name ?? "—" }

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, currencyCode, isBrokerageCash, exchangeName, logoUrl, assetClass, pricingLastSyncedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? "USD"
        isBrokerageCash = try container.decodeIfPresent(Bool.self, forKey: .isBrokerageCash) ?? false
        exchangeName = try container.decodeIfPresent(String.self, forKey: .exchangeName)
        logoUrl = try container.decodeIfPresent(String.self, forKey: .logoUrl)
        assetClass = try container.decodeLenient(InvestmentSecurityAssetClass.self, forKey: .assetClass, default: .unknown)
        pricingLastSyncedAt = container.invCoreDate(forKey: .pricingLastSyncedAt)
    }
}

/// One position. Keyed by `securityId` within its portfolio.
public struct PortfolioHolding: Decodable, Sendable, Hashable, Identifiable {
    public let portfolioId: String
    public let securityId: String
    public let quantity: Decimal
    public let costBasis: Decimal
    public let currencyCode: String
    public let excluded: Bool
    public let security: InvestmentSecurity?
    public let latestPrice: Decimal?
    public let priceDate: Date?
    public let marketValue: Decimal?
    public let unrealizedGainValue: Decimal?
    public let unrealizedGainPercent: Decimal?
    public let realizedGainValue: Decimal?
    public let displayCurrencyCode: String?
    public let displayCostBasis: Decimal?
    public let displayMarketValue: Decimal?
    public let displayUnrealizedGainValue: Decimal?

    public var id: String { securityId }

    enum CodingKeys: String, CodingKey {
        case portfolioId, securityId, quantity, costBasis, currencyCode, excluded, security, latestPrice, priceDate
        case marketValue, unrealizedGainValue, unrealizedGainPercent, realizedGainValue
        case displayCurrencyCode, displayCostBasis, displayMarketValue, displayUnrealizedGainValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        portfolioId = try container.decodeIfPresent(String.self, forKey: .portfolioId) ?? ""
        securityId = try container.decode(String.self, forKey: .securityId)
        quantity = container.invCoreDecimal(forKey: .quantity) ?? 0
        costBasis = container.invCoreDecimal(forKey: .costBasis) ?? 0
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? "USD"
        excluded = try container.decodeIfPresent(Bool.self, forKey: .excluded) ?? false
        security = try? container.decodeIfPresent(InvestmentSecurity.self, forKey: .security)
        latestPrice = container.invCoreDecimal(forKey: .latestPrice)
        priceDate = container.invCoreDate(forKey: .priceDate)
        marketValue = container.invCoreDecimal(forKey: .marketValue)
        unrealizedGainValue = container.invCoreDecimal(forKey: .unrealizedGainValue)
        unrealizedGainPercent = container.invCoreDecimal(forKey: .unrealizedGainPercent)
        realizedGainValue = container.invCoreDecimal(forKey: .realizedGainValue)
        displayCurrencyCode = try container.decodeIfPresent(String.self, forKey: .displayCurrencyCode)
        displayCostBasis = container.invCoreDecimal(forKey: .displayCostBasis)
        displayMarketValue = container.invCoreDecimal(forKey: .displayMarketValue)
        displayUnrealizedGainValue = container.invCoreDecimal(forKey: .displayUnrealizedGainValue)
    }
}

/// A `/investments/securities/search` hit. Sent back verbatim to add a holding.
public struct InvestmentSecuritySearchResult: Codable, Sendable, Hashable, Identifiable {
    public let symbol: String
    public let providerSymbol: String
    public let priceSourceSymbol: String?
    public let name: String
    public let assetClass: InvestmentSecurityAssetClass
    public let providerName: InvestmentSecurityProvider
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
    /// Already held in the queried portfolio. Not sent back.
    public let isInPortfolio: Bool?

    public var id: String { "\(providerName.rawValue):\(providerSymbol):\(exchangeMic ?? "")" }

    /// Only stocks and crypto can be added as holdings.
    public var isSupported: Bool { assetClass == .stocks || assetClass == .crypto }

    public init(
        symbol: String,
        providerSymbol: String,
        priceSourceSymbol: String? = nil,
        name: String,
        assetClass: InvestmentSecurityAssetClass,
        providerName: InvestmentSecurityProvider,
        exchangeAcronym: String? = nil,
        exchangeMic: String? = nil,
        exchangeName: String? = nil,
        currencyCode: String,
        cryptoCurrencyCode: String? = nil,
        cusip: String? = nil,
        isin: String? = nil,
        logoUrl: String? = nil,
        matchType: String? = nil,
        marketCapRank: Int? = nil,
        isInPortfolio: Bool? = nil
    ) {
        self.symbol = symbol
        self.providerSymbol = providerSymbol
        self.priceSourceSymbol = priceSourceSymbol
        self.name = name
        self.assetClass = assetClass
        self.providerName = providerName
        self.exchangeAcronym = exchangeAcronym
        self.exchangeMic = exchangeMic
        self.exchangeName = exchangeName
        self.currencyCode = currencyCode
        self.cryptoCurrencyCode = cryptoCurrencyCode
        self.cusip = cusip
        self.isin = isin
        self.logoUrl = logoUrl
        self.matchType = matchType
        self.marketCapRank = marketCapRank
        self.isInPortfolio = isInPortfolio
    }

    enum CodingKeys: String, CodingKey {
        case symbol, providerSymbol, priceSourceSymbol, name, assetClass, providerName, exchangeAcronym
        case exchangeMic, exchangeName, currencyCode, cryptoCurrencyCode, cusip, isin, logoUrl, matchType
        case marketCapRank, isInPortfolio
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? ""
        providerSymbol = try container.decodeIfPresent(String.self, forKey: .providerSymbol) ?? symbol
        priceSourceSymbol = try container.decodeIfPresent(String.self, forKey: .priceSourceSymbol)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? symbol
        assetClass = try container.decodeLenient(InvestmentSecurityAssetClass.self, forKey: .assetClass, default: .unknown)
        providerName = try container.decodeLenient(InvestmentSecurityProvider.self, forKey: .providerName, default: .unknown)
        exchangeAcronym = try container.decodeIfPresent(String.self, forKey: .exchangeAcronym)
        exchangeMic = try container.decodeIfPresent(String.self, forKey: .exchangeMic)
        exchangeName = try container.decodeIfPresent(String.self, forKey: .exchangeName)
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? "USD"
        cryptoCurrencyCode = try container.decodeIfPresent(String.self, forKey: .cryptoCurrencyCode)
        cusip = try container.decodeIfPresent(String.self, forKey: .cusip)
        isin = try container.decodeIfPresent(String.self, forKey: .isin)
        logoUrl = try container.decodeIfPresent(String.self, forKey: .logoUrl)
        matchType = try container.decodeIfPresent(String.self, forKey: .matchType)
        marketCapRank = try? container.decodeIfPresent(Int.self, forKey: .marketCapRank)
        isInPortfolio = try container.decodeIfPresent(Bool.self, forKey: .isInPortfolio)
    }

    /// Encodes the fields the create-holding schema accepts; `isInPortfolio` is response-only.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(providerSymbol, forKey: .providerSymbol)
        try container.encodeIfPresent(priceSourceSymbol, forKey: .priceSourceSymbol)
        try container.encode(name, forKey: .name)
        try container.encode(assetClass, forKey: .assetClass)
        try container.encode(providerName, forKey: .providerName)
        try container.encodeIfPresent(exchangeAcronym, forKey: .exchangeAcronym)
        try container.encodeIfPresent(exchangeMic, forKey: .exchangeMic)
        try container.encodeIfPresent(exchangeName, forKey: .exchangeName)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encodeIfPresent(cryptoCurrencyCode, forKey: .cryptoCurrencyCode)
        try container.encodeIfPresent(cusip, forKey: .cusip)
        try container.encodeIfPresent(isin, forKey: .isin)
        try container.encodeIfPresent(logoUrl, forKey: .logoUrl)
        if matchType == "exact" || matchType == "partial" {
            try container.encode(matchType, forKey: .matchType)
        }
        try container.encodeIfPresent(marketCapRank, forKey: .marketCapRank)
    }
}

/// A buy, sell, dividend, or other trade on one holding.
public struct InvestmentTransaction: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let securityId: String
    public let portfolioId: String
    public let date: Date?
    public let name: String?
    public let category: InvestmentTransactionCategory
    public let quantity: Decimal?
    public let price: Decimal?
    public let fees: Decimal?
    public let amount: Decimal
    public let currencyCode: String
    public let settlementCurrencyCode: String?
    public let settlementAmount: Decimal?
    public let security: InvestmentSecurity?

    /// The trade day. Date-only trades are stored at UTC midnight, so the UTC calendar day is used.
    public var day: CalendarDate? {
        guard let date else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        return CalendarDate(date: date, calendar: utc)
    }

    /// Settles in a currency other than the security's.
    public var hasSettlement: Bool {
        guard let settlementCurrencyCode else { return false }
        return settlementCurrencyCode != currencyCode
    }

    enum CodingKeys: String, CodingKey {
        case id, securityId, portfolioId, date, name, category, quantity, price, fees, amount, currencyCode
        case settlementCurrencyCode, settlementAmount, security
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        securityId = try container.decodeIfPresent(String.self, forKey: .securityId) ?? ""
        portfolioId = try container.decodeIfPresent(String.self, forKey: .portfolioId) ?? ""
        date = container.invCoreDate(forKey: .date)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        category = try container.decodeLenient(InvestmentTransactionCategory.self, forKey: .category, default: .unknown)
        quantity = container.invCoreDecimal(forKey: .quantity)
        price = container.invCoreDecimal(forKey: .price)
        fees = container.invCoreDecimal(forKey: .fees)
        amount = container.invCoreDecimal(forKey: .amount) ?? 0
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? "USD"
        settlementCurrencyCode = try container.decodeIfPresent(String.self, forKey: .settlementCurrencyCode)
        settlementAmount = container.invCoreDecimal(forKey: .settlementAmount)
        security = try? container.decodeIfPresent(InvestmentSecurity.self, forKey: .security)
    }
}

/// `GET /investments/transactions`: one page, newest first.
public struct InvestmentTransactionPage: Decodable, Sendable, Hashable {
    public let transactions: [InvestmentTransaction]
    public let total: Int
    public let limit: Int
    public let offset: Int

    enum CodingKeys: String, CodingKey { case transactions, total, limit, offset }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactions = try container.decodeLossyArrayIfPresent([InvestmentTransaction].self, forKey: .transactions) ?? []
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? transactions.count
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? transactions.count
        offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
    }

    public var hasMore: Bool { offset + transactions.count < total }
}
