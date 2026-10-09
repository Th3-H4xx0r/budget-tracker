import Foundation

/// `GET /user/currencies/rates` row: `1 baseCode = rate quoteCode`. `custom` marks a rate the
/// user set by hand, which turns off live updates for the pair.
public struct OrgExchangeRate: Sendable, Hashable, Decodable {
    public let baseCode: String
    public let quoteCode: String
    public let rate: Decimal
    public let custom: Bool

    public init(baseCode: String, quoteCode: String, rate: Decimal, custom: Bool = false) {
        self.baseCode = baseCode
        self.quoteCode = quoteCode
        self.rate = rate
        self.custom = custom
    }

    private enum CodingKeys: String, CodingKey { case baseCode, quoteCode, rate, custom }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseCode = try container.decode(String.self, forKey: .baseCode)
        quoteCode = try container.decode(String.self, forKey: .quoteCode)
        rate = try container.decodeIfPresent(Decimal.self, forKey: .rate) ?? 0
        custom = try container.decodeIfPresent(Bool.self, forKey: .custom) ?? false
    }
}

/// One direction of a custom rate in `PUT /user/currency/rates`.
public struct OrgExchangeRatePair: Encodable, Sendable, Hashable {
    public let baseCode: String
    public let quoteCode: String
    public let rate: Decimal

    public init(baseCode: String, quoteCode: String, rate: Decimal) {
        self.baseCode = baseCode
        self.quoteCode = quoteCode
        self.rate = rate
    }
}

/// One direction of a pair in `DELETE /user/currency/rates`, which restores live rates.
public struct OrgExchangeRateKey: Encodable, Sendable, Hashable {
    public let baseCode: String
    public let quoteCode: String

    public init(baseCode: String, quoteCode: String) {
        self.baseCode = baseCode
        self.quoteCode = quoteCode
    }
}

public enum OrgBaseCurrencyChangeState: String, LenientEnum {
    case idle, queued, running, completed, failed
    case unknown

    /// Still working; keep polling.
    public var isInFlight: Bool { self == .queued || self == .running }
}

/// `GET /user/currencies/change-base/status` and the `POST /user/currencies/change-base` reply.
public struct OrgBaseCurrencyChangeStatus: Sendable, Hashable, Decodable {
    public let state: OrgBaseCurrencyChangeState
    public let jobId: String?
    /// The running step, e.g. `accounts` or `balances`.
    public let step: String?
    public let error: String?

    public init(state: OrgBaseCurrencyChangeState, jobId: String? = nil, step: String? = nil, error: String? = nil) {
        self.state = state
        self.jobId = jobId
        self.step = step
        self.error = error
    }

    private enum CodingKeys: String, CodingKey { case state, jobId, step, error }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decodeLenient(OrgBaseCurrencyChangeState.self, forKey: .state, default: .unknown)
        jobId = try container.decodeIfPresent(String.self, forKey: .jobId)
        step = try container.decodeIfPresent(String.self, forKey: .step)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
    }
}

struct OrgCurrencyCodeBody: Encodable, Sendable {
    let currencyCode: String
}

struct OrgChangeBaseCurrencyBody: Encodable, Sendable {
    let newCurrencyCode: String
}

struct OrgRatePairsBody<Pair: Encodable & Sendable>: Encodable, Sendable {
    let pairs: [Pair]
}

extension Endpoints {
    /// `GET /user/currencies/rates`.
    public static func orgUserExchangeRates() -> Endpoint<[OrgExchangeRate]> {
        Endpoint(.get, "/user/currencies/rates")
    }

    /// `PUT /user/currency/rates`: sets custom rates; send both directions of a pair.
    public static func orgEditExchangeRates(_ pairs: [OrgExchangeRatePair]) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/user/currency/rates", body: OrgRatePairsBody(pairs: pairs))
    }

    /// `DELETE /user/currency/rates`: drops custom rates so the pair follows live rates again.
    public static func orgDeleteCustomRates(_ pairs: [OrgExchangeRateKey]) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/user/currency/rates", body: OrgRatePairsBody(pairs: pairs))
    }

    /// `DELETE /user/currency`: disconnects a currency. Fails while accounts use it.
    public static func orgDeleteUserCurrency(code: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/user/currency", body: OrgCurrencyCodeBody(currencyCode: code))
    }

    /// `POST /user/currencies/change-base`: queues the base-currency recalculation job.
    public static func orgChangeBaseCurrency(code: String) -> Endpoint<OrgBaseCurrencyChangeStatus> {
        Endpoint(.post, "/user/currencies/change-base", body: OrgChangeBaseCurrencyBody(newCurrencyCode: code))
    }

    /// `GET /user/currencies/change-base/status`: `idle` when nothing is running.
    public static func orgBaseCurrencyChangeStatus() -> Endpoint<OrgBaseCurrencyChangeStatus> {
        Endpoint(.get, "/user/currencies/change-base/status")
    }
}
