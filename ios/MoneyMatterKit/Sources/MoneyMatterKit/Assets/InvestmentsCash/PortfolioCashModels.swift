import Foundation

/// `GET /investments/portfolios/:id/balance` row: cash held in one currency.
public struct PortfolioCashBalance: Sendable, Hashable, Identifiable, Decodable {
    public let portfolioId: String
    public let currencyCode: String
    /// Cash not committed to pending orders.
    public let availableCash: Decimal
    public let totalCash: Decimal
    public let refAvailableCash: Decimal
    public let refTotalCash: Decimal

    public var id: String { currencyCode }

    public init(
        portfolioId: String,
        currencyCode: String,
        availableCash: Decimal,
        totalCash: Decimal,
        refAvailableCash: Decimal = 0,
        refTotalCash: Decimal = 0
    ) {
        self.portfolioId = portfolioId
        self.currencyCode = currencyCode
        self.availableCash = availableCash
        self.totalCash = totalCash
        self.refAvailableCash = refAvailableCash
        self.refTotalCash = refTotalCash
    }

    private enum CodingKeys: String, CodingKey {
        case portfolioId, currencyCode, availableCash, totalCash, refAvailableCash, refTotalCash
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        portfolioId = try container.decodeIfPresent(String.self, forKey: .portfolioId) ?? ""
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        availableCash = try container.ventureDecimalIfPresent(forKey: .availableCash) ?? 0
        totalCash = try container.ventureDecimalIfPresent(forKey: .totalCash) ?? 0
        refAvailableCash = try container.ventureDecimalIfPresent(forKey: .refAvailableCash) ?? 0
        refTotalCash = try container.ventureDecimalIfPresent(forKey: .refTotalCash) ?? 0
    }
}

/// `GET /investments/portfolios/:id/transfers` row: a cash movement into, out of, or
/// within a portfolio. Amounts arrive as decimal strings.
public struct PortfolioCashTransfer: Sendable, Hashable, Identifiable, Decodable {
    /// How a transfer moved cash, seen from one portfolio.
    public enum Kind: Sendable, Hashable {
        case deposit
        case withdrawal
        case fromAccount
        case toAccount
        case fromPortfolio
        case toPortfolio
        case exchange
    }

    public let id: String
    public let fromAccountId: String?
    public let toPortfolioId: String?
    public let fromPortfolioId: String?
    public let toAccountId: String?
    public let amount: Decimal
    public let currencyCode: String
    public let toCurrencyCode: String?
    public let toAmount: Decimal?
    public let transactionId: String?
    /// Adjustments correct the balance and don't count as contributions.
    public let isAdjustment: Bool
    public let date: CalendarDate
    public let transferDescription: String?

    public init(
        id: String,
        fromAccountId: String? = nil,
        toPortfolioId: String? = nil,
        fromPortfolioId: String? = nil,
        toAccountId: String? = nil,
        amount: Decimal,
        currencyCode: String,
        toCurrencyCode: String? = nil,
        toAmount: Decimal? = nil,
        transactionId: String? = nil,
        isAdjustment: Bool = false,
        date: CalendarDate,
        transferDescription: String? = nil
    ) {
        self.id = id
        self.fromAccountId = fromAccountId
        self.toPortfolioId = toPortfolioId
        self.fromPortfolioId = fromPortfolioId
        self.toAccountId = toAccountId
        self.amount = amount
        self.currencyCode = currencyCode
        self.toCurrencyCode = toCurrencyCode
        self.toAmount = toAmount
        self.transactionId = transactionId
        self.isAdjustment = isAdjustment
        self.date = date
        self.transferDescription = transferDescription
    }

    private enum CodingKeys: String, CodingKey {
        case id, fromAccountId, toPortfolioId, fromPortfolioId, toAccountId, amount, currencyCode
        case toCurrencyCode, toAmount, transactionId, isAdjustment, date, description
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        fromAccountId = try container.decodeIfPresent(String.self, forKey: .fromAccountId)
        toPortfolioId = try container.decodeIfPresent(String.self, forKey: .toPortfolioId)
        fromPortfolioId = try container.decodeIfPresent(String.self, forKey: .fromPortfolioId)
        toAccountId = try container.decodeIfPresent(String.self, forKey: .toAccountId)
        amount = try container.ventureDecimalIfPresent(forKey: .amount) ?? 0
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? ""
        toCurrencyCode = try container.decodeIfPresent(String.self, forKey: .toCurrencyCode)
        toAmount = try container.ventureDecimalIfPresent(forKey: .toAmount)
        transactionId = try container.decodeIfPresent(String.self, forKey: .transactionId)
        isAdjustment = try container.decodeIfPresent(Bool.self, forKey: .isAdjustment) ?? false
        date = try container.ventureDay(forKey: .date) ?? CalendarDate(year: 1970, month: 1, day: 1)
        transferDescription = try container.decodeIfPresent(String.self, forKey: .description)
    }

    /// The transfer's direction relative to `portfolioID`.
    public func kind(for portfolioID: String) -> Kind {
        if let toCurrencyCode, toCurrencyCode != currencyCode,
           fromPortfolioId == portfolioID, toPortfolioId == portfolioID {
            return .exchange
        }
        if toPortfolioId == portfolioID {
            if fromAccountId != nil { return .fromAccount }
            if let fromPortfolioId, fromPortfolioId != portfolioID { return .fromPortfolio }
            return .deposit
        }
        if toAccountId != nil { return .toAccount }
        if let toPortfolioId, toPortfolioId != portfolioID { return .toPortfolio }
        return .withdrawal
    }

    /// True when cash came into the portfolio.
    public func isInflow(for portfolioID: String) -> Bool {
        switch kind(for: portfolioID) {
        case .deposit, .fromAccount, .fromPortfolio: true
        case .withdrawal, .toAccount, .toPortfolio, .exchange: false
        }
    }
}

/// Amounts the investments routes take as decimal strings (`positiveAmountString`).
struct PortfolioCashAmount: Encodable, Sendable, Hashable {
    let value: Decimal

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: value).stringValue)
    }
}

/// `POST /investments/portfolios/:id/cash-transaction` body: cash deposited or withdrawn
/// without a tracked account on the other side.
public struct PortfolioCashTransactionRequest: Encodable, Sendable, Hashable {
    public enum Direction: String, Encodable, Sendable, Hashable {
        case deposit
        case withdrawal
    }

    public var type: Direction
    public var amount: Decimal
    public var currencyCode: String
    public var date: CalendarDate
    public var description: String?
    public var isAdjustment: Bool

    public init(
        type: Direction,
        amount: Decimal,
        currencyCode: String,
        date: CalendarDate,
        description: String? = nil,
        isAdjustment: Bool = false
    ) {
        self.type = type
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.description = description
        self.isAdjustment = isAdjustment
    }

    private enum CodingKeys: String, CodingKey {
        case type, amount, currencyCode, date, description, isAdjustment
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(PortfolioCashAmount(value: amount), forKey: .amount)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(isAdjustment, forKey: .isAdjustment)
    }
}

/// `POST /investments/portfolios/:id/transfer/from-account` (into the portfolio, in the
/// account's currency) or `/transfer/to-account` (out of it, from the portfolio's cash in
/// `currencyCode`).
public struct PortfolioTransferAccountRequest: Encodable, Sendable, Hashable {
    public var accountId: String
    public var amount: Decimal
    /// Out-of-portfolio transfers only: which cash balance pays.
    public var currencyCode: String?
    public var date: CalendarDate
    public var description: String?

    public init(accountId: String, amount: Decimal, currencyCode: String? = nil, date: CalendarDate, description: String? = nil) {
        self.accountId = accountId
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case accountId, amount, currencyCode, date, description
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(PortfolioCashAmount(value: amount), forKey: .amount)
        try container.encodeIfPresent(currencyCode, forKey: .currencyCode)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

/// `POST /investments/portfolios/:id/exchange-currency` body.
public struct PortfolioExchangeRequest: Encodable, Sendable, Hashable {
    public var fromCurrencyCode: String
    public var toCurrencyCode: String
    public var fromAmount: Decimal
    public var toAmount: Decimal
    public var date: CalendarDate
    public var description: String?

    public init(
        fromCurrencyCode: String,
        toCurrencyCode: String,
        fromAmount: Decimal,
        toAmount: Decimal,
        date: CalendarDate,
        description: String? = nil
    ) {
        self.fromCurrencyCode = fromCurrencyCode
        self.toCurrencyCode = toCurrencyCode
        self.fromAmount = fromAmount
        self.toAmount = toAmount
        self.date = date
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case fromCurrencyCode, toCurrencyCode, fromAmount, toAmount, date, description
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fromCurrencyCode, forKey: .fromCurrencyCode)
        try container.encode(toCurrencyCode, forKey: .toCurrencyCode)
        try container.encode(PortfolioCashAmount(value: fromAmount), forKey: .fromAmount)
        try container.encode(PortfolioCashAmount(value: toAmount), forKey: .toAmount)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

/// `POST /investments/portfolios/:id/transfer` body: cash moved to another portfolio.
public struct PortfolioTransferPortfolioRequest: Encodable, Sendable, Hashable {
    public var toPortfolioId: String
    public var currencyCode: String
    public var amount: Decimal
    public var date: CalendarDate
    public var description: String?

    public init(toPortfolioId: String, currencyCode: String, amount: Decimal, date: CalendarDate, description: String? = nil) {
        self.toPortfolioId = toPortfolioId
        self.currencyCode = currencyCode
        self.amount = amount
        self.date = date
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case toPortfolioId, currencyCode, amount, date, description
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toPortfolioId, forKey: .toPortfolioId)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(PortfolioCashAmount(value: amount), forKey: .amount)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

struct PortfolioCashAdjustmentRequest: Encodable, Sendable, Hashable {
    let isAdjustment: Bool
}

struct PortfolioCashTransferPage: Decodable, Sendable {
    let data: [PortfolioCashTransfer]
}

extension Endpoints {
    /// `GET /investments/portfolios/:id/balance`: cash per currency.
    public static func portfolioCashBalances(portfolioId: String) -> Endpoint<[PortfolioCashBalance]> {
        Endpoint(.get, "/investments/portfolios/\(portfolioId)/balance")
    }

    /// `GET /investments/portfolios/:id/transfers`, newest first.
    public static func portfolioCashTransfers(portfolioId: String, limit: Int = 100, offset: Int = 0) -> Endpoint<[PortfolioCashTransfer]> {
        var query = QueryBuilder()
        query.add("limit", limit)
        query.add("offset", offset)
        return Endpoint<PortfolioCashTransferPage>(.get, "/investments/portfolios/\(portfolioId)/transfers", query: query.items)
            .map(\.data)
    }

    /// `POST /investments/portfolios/:id/cash-transaction`.
    public static func portfolioCashTransactionCreate(
        portfolioId: String,
        _ request: PortfolioCashTransactionRequest
    ) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/investments/portfolios/\(portfolioId)/cash-transaction", body: request)
    }

    /// `POST /investments/portfolios/:id/transfer/from-account`: account → portfolio.
    public static func portfolioTransferFromAccount(
        portfolioId: String,
        _ request: PortfolioTransferAccountRequest
    ) -> Endpoint<EmptyResponse> {
        var body = request
        body.currencyCode = nil
        return Endpoint(.post, "/investments/portfolios/\(portfolioId)/transfer/from-account", body: body)
    }

    /// `POST /investments/portfolios/:id/transfer/to-account`: portfolio → account.
    public static func portfolioTransferToAccount(
        portfolioId: String,
        _ request: PortfolioTransferAccountRequest
    ) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/investments/portfolios/\(portfolioId)/transfer/to-account", body: request)
    }

    /// `POST /investments/portfolios/:id/transfer`: portfolio → portfolio.
    public static func portfolioTransferToPortfolio(
        portfolioId: String,
        _ request: PortfolioTransferPortfolioRequest
    ) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/investments/portfolios/\(portfolioId)/transfer", body: request)
    }

    /// `POST /investments/portfolios/:id/exchange-currency`.
    public static func portfolioExchangeCurrency(portfolioId: String, _ request: PortfolioExchangeRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/investments/portfolios/\(portfolioId)/exchange-currency", body: request)
    }

    /// `PATCH /investments/portfolios/:id/transfers/:transferId/adjustment`.
    public static func portfolioCashSetAdjustment(
        portfolioId: String,
        transferId: String,
        isAdjustment: Bool
    ) -> Endpoint<EmptyResponse> {
        Endpoint(
            .patch,
            "/investments/portfolios/\(portfolioId)/transfers/\(transferId)/adjustment",
            body: PortfolioCashAdjustmentRequest(isAdjustment: isAdjustment)
        )
    }

    /// `DELETE /investments/portfolios/:id/transfers/:transferId`. `deleteLinkedTransaction`
    /// also removes the account-side transaction of an account transfer.
    public static func portfolioCashTransferDelete(
        portfolioId: String,
        transferId: String,
        deleteLinkedTransaction: Bool = false
    ) -> Endpoint<EmptyResponse> {
        var query = QueryBuilder()
        query.addFlag("deleteLinkedTransaction", deleteLinkedTransaction)
        return Endpoint(.delete, "/investments/portfolios/\(portfolioId)/transfers/\(transferId)", query: query.items)
    }
}
