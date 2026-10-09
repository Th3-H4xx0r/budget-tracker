import Foundation

/// Formats an amount the way the investment endpoints' `numericString()` fields expect:
/// plain digits with a `.` separator, no grouping.
public enum InvestmentTransactionNumber {
    public static func string(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

/// `POST /investments/portfolios` body.
public struct PortfolioCreateRequest: Encodable, Sendable, Hashable {
    public var name: String
    public var portfolioType: PortfolioType
    public var description: String?
    /// `nil` uses the base currency.
    public var displayCurrencyCode: String?
    public var isEnabled: Bool

    public init(
        name: String,
        portfolioType: PortfolioType = .investment,
        description: String? = nil,
        displayCurrencyCode: String? = nil,
        isEnabled: Bool = true
    ) {
        self.name = name
        self.portfolioType = portfolioType
        self.description = description
        self.displayCurrencyCode = displayCurrencyCode
        self.isEnabled = isEnabled
    }
}

/// `PUT /investments/portfolios/:id` body. The schema is strict, so only set fields are sent;
/// `description` and `displayCurrencyCode` accept `null` to clear.
public struct PortfolioUpdateRequest: Encodable, Sendable, Hashable {
    public var name: String?
    public var portfolioType: PortfolioType?
    public var description: FieldUpdate<String>
    public var displayCurrencyCode: FieldUpdate<String>
    public var isEnabled: Bool?

    public init(
        name: String? = nil,
        portfolioType: PortfolioType? = nil,
        description: FieldUpdate<String> = .unchanged,
        displayCurrencyCode: FieldUpdate<String> = .unchanged,
        isEnabled: Bool? = nil
    ) {
        self.name = name
        self.portfolioType = portfolioType
        self.description = description
        self.displayCurrencyCode = displayCurrencyCode
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey { case name, portfolioType, description, displayCurrencyCode, isEnabled }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(portfolioType, forKey: .portfolioType)
        try Self.encode(description, forKey: .description, in: &container)
        try Self.encode(displayCurrencyCode, forKey: .displayCurrencyCode, in: &container)
        try container.encodeIfPresent(isEnabled, forKey: .isEnabled)
    }

    private static func encode(
        _ update: FieldUpdate<String>,
        forKey key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch update {
        case .unchanged: break
        case .clear: try container.encodeNil(forKey: key)
        case .set(let value): try container.encode(value, forKey: key)
        }
    }
}

/// `DELETE /investments/portfolios/:id` body. Without `force` the portfolio moves to the trash.
struct PortfolioDeleteRequest: Encodable, Sendable, Hashable {
    let force: Bool?
}

/// `POST /investments/holding` body: an existing security or a search hit to create it from.
public struct HoldingCreateRequest: Encodable, Sendable, Hashable {
    public var portfolioId: String
    public var securityId: String?
    public var searchResult: InvestmentSecuritySearchResult?

    public init(portfolioId: String, searchResult: InvestmentSecuritySearchResult) {
        self.portfolioId = portfolioId
        self.searchResult = searchResult
        self.securityId = nil
    }

    public init(portfolioId: String, securityId: String) {
        self.portfolioId = portfolioId
        self.securityId = securityId
        self.searchResult = nil
    }
}

/// `DELETE /investments/holding` body. `force` also deletes the holding's transactions.
public struct HoldingDeleteRequest: Encodable, Sendable, Hashable {
    public var portfolioId: String
    public var securityId: String
    public var force: Bool?

    public init(portfolioId: String, securityId: String, force: Bool? = true) {
        self.portfolioId = portfolioId
        self.securityId = securityId
        self.force = force
    }
}

/// The cash side of a trade when it settles in another currency. Send either `fees` or
/// `rate`; with neither, the server derives the fee from the market rate.
public struct InvestmentTransactionSettlement: Sendable, Hashable {
    public var currencyCode: String
    public var amount: Decimal
    public var fees: Decimal?
    public var rate: Decimal?

    public init(currencyCode: String, amount: Decimal, fees: Decimal? = nil, rate: Decimal? = nil) {
        self.currencyCode = currencyCode
        self.amount = amount
        self.fees = fees
        self.rate = rate
    }
}

/// `POST /investments/transaction` body. Amounts go as numeric strings.
public struct InvestmentTransactionCreateRequest: Encodable, Sendable, Hashable {
    public var portfolioId: String
    public var securityId: String
    public var category: InvestmentTransactionCategory
    public var date: CalendarDate
    public var quantity: Decimal
    public var price: Decimal
    public var fees: Decimal?
    public var name: String?
    public var settlement: InvestmentTransactionSettlement?

    public init(
        portfolioId: String,
        securityId: String,
        category: InvestmentTransactionCategory,
        date: CalendarDate,
        quantity: Decimal,
        price: Decimal,
        fees: Decimal? = nil,
        name: String? = nil,
        settlement: InvestmentTransactionSettlement? = nil
    ) {
        self.portfolioId = portfolioId
        self.securityId = securityId
        self.category = category
        self.date = date
        self.quantity = quantity
        self.price = price
        self.fees = fees
        self.name = name
        self.settlement = settlement
    }

    enum CodingKeys: String, CodingKey {
        case portfolioId, securityId, category, date, quantity, price, fees, name
        case settlementCurrencyCode, settlementAmount, settlementFees, settlementRate
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(portfolioId, forKey: .portfolioId)
        try container.encode(securityId, forKey: .securityId)
        try container.encode(category, forKey: .category)
        try container.encode(date, forKey: .date)
        try container.encode(InvestmentTransactionNumber.string(quantity), forKey: .quantity)
        try container.encode(InvestmentTransactionNumber.string(price), forKey: .price)
        if let fees { try container.encode(InvestmentTransactionNumber.string(fees), forKey: .fees) }
        if let name, !name.isEmpty { try container.encode(name, forKey: .name) }
        try encodeSettlement(settlement, into: &container)
    }

    private func encodeSettlement(
        _ settlement: InvestmentTransactionSettlement?,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        guard let settlement else { return }
        try container.encode(settlement.currencyCode, forKey: .settlementCurrencyCode)
        try container.encode(InvestmentTransactionNumber.string(settlement.amount), forKey: .settlementAmount)
        if let fees = settlement.fees {
            try container.encode(InvestmentTransactionNumber.string(fees), forKey: .settlementFees)
        } else if let rate = settlement.rate {
            try container.encode(InvestmentTransactionNumber.string(rate), forKey: .settlementRate)
        }
    }
}

/// `PUT /investments/transaction/:id` body. Nil fields are left unchanged.
public struct InvestmentTransactionUpdateRequest: Encodable, Sendable, Hashable {
    public var category: InvestmentTransactionCategory?
    public var date: CalendarDate?
    public var quantity: Decimal?
    public var price: Decimal?
    public var fees: Decimal?
    public var name: String?
    public var settlement: InvestmentTransactionSettlement?

    public init(
        category: InvestmentTransactionCategory? = nil,
        date: CalendarDate? = nil,
        quantity: Decimal? = nil,
        price: Decimal? = nil,
        fees: Decimal? = nil,
        name: String? = nil,
        settlement: InvestmentTransactionSettlement? = nil
    ) {
        self.category = category
        self.date = date
        self.quantity = quantity
        self.price = price
        self.fees = fees
        self.name = name
        self.settlement = settlement
    }

    enum CodingKeys: String, CodingKey {
        case category, date, quantity, price, fees, name
        case settlementCurrencyCode, settlementAmount, settlementFees, settlementRate
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(date, forKey: .date)
        if let quantity { try container.encode(InvestmentTransactionNumber.string(quantity), forKey: .quantity) }
        if let price { try container.encode(InvestmentTransactionNumber.string(price), forKey: .price) }
        if let fees { try container.encode(InvestmentTransactionNumber.string(fees), forKey: .fees) }
        try container.encodeIfPresent(name, forKey: .name)
        if let settlement {
            try container.encode(settlement.currencyCode, forKey: .settlementCurrencyCode)
            try container.encode(InvestmentTransactionNumber.string(settlement.amount), forKey: .settlementAmount)
            if let fees = settlement.fees {
                try container.encode(InvestmentTransactionNumber.string(fees), forKey: .settlementFees)
            } else if let rate = settlement.rate {
                try container.encode(InvestmentTransactionNumber.string(rate), forKey: .settlementRate)
            }
        }
    }
}
