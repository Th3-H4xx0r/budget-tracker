import Foundation

/// `GET /models/currencies`: an ISO 4217 currency the server knows.
public struct Currency: Sendable, Hashable, Identifiable, Decodable {
    public let code: String
    /// The currency's English name, e.g. "US Dollar".
    public let currency: String
    /// Minor-unit digits (2 for USD, 0 for JPY).
    public let digits: Int
    public let number: Int
    public let isDisabled: Bool

    public var id: String { code }

    public init(code: String, currency: String, digits: Int = 2, number: Int = 0, isDisabled: Bool = false) {
        self.code = code
        self.currency = currency
        self.digits = digits
        self.number = number
        self.isDisabled = isDisabled
    }

    private enum CodingKeys: String, CodingKey { case code, currency, digits, number, isDisabled }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? code
        digits = try container.decodeIfPresent(Int.self, forKey: .digits) ?? 2
        number = try container.decodeIfPresent(Int.self, forKey: .number) ?? 0
        isDisabled = try container.decodeIfPresent(Bool.self, forKey: .isDisabled) ?? false
    }
}

/// `GET /user/currencies`: a currency the user has connected.
public struct UserCurrency: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let userId: Int
    public let currencyCode: String
    public let exchangeRate: Decimal?
    public let liveRateUpdate: Bool
    public let isDefaultCurrency: Bool
    public let currency: Currency?

    public init(
        id: String,
        userId: Int,
        currencyCode: String,
        exchangeRate: Decimal? = nil,
        liveRateUpdate: Bool = true,
        isDefaultCurrency: Bool = false,
        currency: Currency? = nil
    ) {
        self.id = id
        self.userId = userId
        self.currencyCode = currencyCode
        self.exchangeRate = exchangeRate
        self.liveRateUpdate = liveRateUpdate
        self.isDefaultCurrency = isDefaultCurrency
        self.currency = currency
    }

    private enum CodingKeys: String, CodingKey {
        case id, userId, currencyCode, exchangeRate, liveRateUpdate, isDefaultCurrency, currency
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId) ?? 0
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        exchangeRate = try container.decodeIfPresent(Decimal.self, forKey: .exchangeRate)
        liveRateUpdate = try container.decodeIfPresent(Bool.self, forKey: .liveRateUpdate) ?? false
        isDefaultCurrency = try container.decodeIfPresent(Bool.self, forKey: .isDefaultCurrency) ?? false
        currency = try container.decodeIfPresent(Currency.self, forKey: .currency)
    }

    /// Minor-unit digits, defaulting to 2 when the nested currency is missing.
    public var digits: Int { currency?.digits ?? 2 }
}

/// `POST /user/currencies` result.
public struct AddedUserCurrencies: Sendable, Hashable, Decodable {
    public let currencies: [UserCurrency]
    public let alreadyExistingCodes: [String]

    private enum CodingKeys: String, CodingKey { case currencies, alreadyExistingCodes }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currencies = try container.decodeIfPresent([UserCurrency].self, forKey: .currencies) ?? []
        alreadyExistingCodes = try container.decodeIfPresent([String].self, forKey: .alreadyExistingCodes) ?? []
    }
}
