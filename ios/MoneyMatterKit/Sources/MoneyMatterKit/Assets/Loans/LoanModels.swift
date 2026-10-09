import Foundation

/// `loanDetails.loanType`. Only `supported` types can be created.
public enum LoanType: String, LenientEnum, CaseIterable {
    case mortgage
    case auto
    case student
    case personal
    case heloc
    case business
    case medical
    case other
    case unknown

    /// The types `POST /loans` accepts.
    public static let supported: [LoanType] = [.mortgage, .auto, .student, .personal]
}

/// Why forward-looking projection figures are missing.
public enum LoanProjectionWarning: String, LenientEnum {
    case noPlannedPayment = "no_planned_payment"
    case paymentBelowInterest = "payment_below_interest"
    case unknown
}

/// Payoff projection the server computes per loan. Forward-looking fields are nil when the
/// loan is paid off or stalled (see `warning`).
public struct LoanProjection: Sendable, Hashable, Decodable {
    public let isPaidOff: Bool
    public let warning: LoanProjectionWarning?
    public let payoffDate: CalendarDate?
    public let monthsRemaining: Int?
    public let totalInterestRemaining: Decimal?
    public let estimatedInterestPaid: Decimal?
    public let monthlyPrincipal: Decimal?
    public let paidToDate: Decimal
    public let paidToDatePercent: Decimal
    public let monthlyInterest: Decimal

    public init(
        isPaidOff: Bool,
        warning: LoanProjectionWarning? = nil,
        payoffDate: CalendarDate? = nil,
        monthsRemaining: Int? = nil,
        totalInterestRemaining: Decimal? = nil,
        estimatedInterestPaid: Decimal? = nil,
        monthlyPrincipal: Decimal? = nil,
        paidToDate: Decimal = 0,
        paidToDatePercent: Decimal = 0,
        monthlyInterest: Decimal = 0
    ) {
        self.isPaidOff = isPaidOff
        self.warning = warning
        self.payoffDate = payoffDate
        self.monthsRemaining = monthsRemaining
        self.totalInterestRemaining = totalInterestRemaining
        self.estimatedInterestPaid = estimatedInterestPaid
        self.monthlyPrincipal = monthlyPrincipal
        self.paidToDate = paidToDate
        self.paidToDatePercent = paidToDatePercent
        self.monthlyInterest = monthlyInterest
    }

    enum CodingKeys: String, CodingKey {
        case isPaidOff, warning, payoffDate, monthsRemaining, totalInterestRemaining
        case estimatedInterestPaid, monthlyPrincipal, paidToDate, paidToDatePercent, monthlyInterest
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPaidOff = try container.decodeIfPresent(Bool.self, forKey: .isPaidOff) ?? false
        warning = try container.decodeIfPresent(LoanProjectionWarning.self, forKey: .warning)
        payoffDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .payoffDate)
        monthsRemaining = try container.decodeIfPresent(Int.self, forKey: .monthsRemaining)
        totalInterestRemaining = try container.decodeIfPresent(Decimal.self, forKey: .totalInterestRemaining)
        estimatedInterestPaid = try container.decodeIfPresent(Decimal.self, forKey: .estimatedInterestPaid)
        monthlyPrincipal = try container.decodeIfPresent(Decimal.self, forKey: .monthlyPrincipal)
        paidToDate = try container.decodeIfPresent(Decimal.self, forKey: .paidToDate) ?? 0
        paidToDatePercent = try container.decodeIfPresent(Decimal.self, forKey: .paidToDatePercent) ?? 0
        monthlyInterest = try container.decodeIfPresent(Decimal.self, forKey: .monthlyInterest) ?? 0
    }
}

public enum LoanEventKind: String, LenientEnum {
    case rateChange = "rate_change"
    case termChange = "term_change"
    case plannedPaymentChange = "planned_payment_change"
    case balanceCorrection = "balance_correction"
    case note
    case paidOff = "paid_off"
    case unknown
}

/// One entry in a loan's timeline. `from`/`to` are APR percent for rate changes, months for
/// term changes, and decimal amounts for payment changes and balance corrections.
public struct LoanEvent: Sendable, Hashable, Decodable {
    public let kind: LoanEventKind
    public let at: Date
    public let from: Decimal?
    public let to: Decimal?
    public let reason: String?
    public let text: String?

    public init(kind: LoanEventKind, at: Date, from: Decimal? = nil, to: Decimal? = nil, reason: String? = nil, text: String? = nil) {
        self.kind = kind
        self.at = at
        self.from = from
        self.to = to
        self.reason = reason
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case type, at, from, to, reason, text
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeLenient(LoanEventKind.self, forKey: .type, default: .unknown)
        at = try container.decode(Date.self, forKey: .at)
        from = try container.decodeIfPresent(Decimal.self, forKey: .from)
        to = try container.decodeIfPresent(Decimal.self, forKey: .to)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        text = try container.decodeIfPresent(String.self, forKey: .text)
    }
}

/// The loan sidecar of `GET /loans`. Money is decimal in the loan currency; `ref*` twins are
/// in the base currency.
public struct LoanDetails: Sendable, Hashable, Decodable {
    public let id: String
    public let loanType: LoanType
    public let originalPrincipal: Decimal
    public let refOriginalPrincipal: Decimal
    public let interestRate: Decimal
    public let termMonths: Int?
    public let startDate: CalendarDate
    public let balanceAnchorDate: CalendarDate?
    public let minPayment: Decimal?
    public let refMinPayment: Decimal?
    public let plannedPayment: Decimal?
    public let refPlannedPayment: Decimal?
    public let paymentDayOfMonth: Int?
    public let lenderName: String?
    public let accountNumber: String?
    public let events: [LoanEvent]

    enum CodingKeys: String, CodingKey {
        case id, loanType, originalPrincipal, refOriginalPrincipal, interestRate, termMonths, startDate
        case balanceAnchorDate, minPayment, refMinPayment, plannedPayment, refPlannedPayment
        case paymentDayOfMonth, lenderName, accountNumber, events
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        loanType = try container.decodeLenient(LoanType.self, forKey: .loanType, default: .other)
        originalPrincipal = try container.decodeIfPresent(Decimal.self, forKey: .originalPrincipal) ?? 0
        refOriginalPrincipal = try container.decodeIfPresent(Decimal.self, forKey: .refOriginalPrincipal) ?? originalPrincipal
        interestRate = try container.decodeIfPresent(Decimal.self, forKey: .interestRate) ?? 0
        termMonths = try container.decodeIfPresent(Int.self, forKey: .termMonths)
        startDate = try container.decode(CalendarDate.self, forKey: .startDate)
        balanceAnchorDate = try? container.decodeIfPresent(CalendarDate.self, forKey: .balanceAnchorDate)
        minPayment = try container.decodeIfPresent(Decimal.self, forKey: .minPayment)
        refMinPayment = try container.decodeIfPresent(Decimal.self, forKey: .refMinPayment)
        plannedPayment = try container.decodeIfPresent(Decimal.self, forKey: .plannedPayment)
        refPlannedPayment = try container.decodeIfPresent(Decimal.self, forKey: .refPlannedPayment)
        paymentDayOfMonth = try container.decodeIfPresent(Int.self, forKey: .paymentDayOfMonth)
        lenderName = try container.decodeIfPresent(String.self, forKey: .lenderName)
        accountNumber = try container.decodeIfPresent(String.self, forKey: .accountNumber)
        events = try container.decodeLossyArrayIfPresent([LoanEvent].self, forKey: .events) ?? []
    }
}

/// A loan from `/loans`: the underlying account (spread at the top level of the JSON), plus
/// its details and projection. Liability balances arrive negative.
public struct Loan: Sendable, Hashable, Identifiable, Decodable {
    public let account: Account
    public let loanDetails: LoanDetails
    public let projection: LoanProjection
    public let paymentsCount: Int

    public var id: String { account.id }
    public var name: String { account.name }
    public var currencyCode: String { account.currencyCode }
    public var isArchived: Bool { account.status == .archived }
    /// The positive amount still owed, in the loan currency.
    public var outstanding: Decimal { LoanMath.outstanding(balance: account.currentBalance) }
    /// The positive amount still owed, in the base currency.
    public var refOutstanding: Decimal { LoanMath.outstanding(balance: account.refCurrentBalance) }
    /// Base-currency units per loan-currency unit, taken from the principal pair.
    public var refRate: Decimal {
        loanDetails.originalPrincipal > 0 ? loanDetails.refOriginalPrincipal / loanDetails.originalPrincipal : 1
    }
    /// When the loan was settled, from its `paid_off` event.
    public var paidOffAt: Date? {
        loanDetails.events.last(where: { $0.kind == .paidOff })?.at
    }

    enum CodingKeys: String, CodingKey {
        case loanDetails, projection, paymentsCount
    }

    public init(from decoder: any Decoder) throws {
        account = try Account(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        loanDetails = try container.decode(LoanDetails.self, forKey: .loanDetails)
        projection = try container.decode(LoanProjection.self, forKey: .projection)
        paymentsCount = try container.decodeIfPresent(Int.self, forKey: .paymentsCount) ?? 0
    }
}

/// One point of `GET /loans/:id/balance-history`: a signed balance in the loan currency,
/// negative while debt is outstanding.
public struct LoanBalancePoint: Sendable, Hashable, Decodable {
    public let date: CalendarDate
    public let amount: Decimal

    public init(date: CalendarDate, amount: Decimal) {
        self.date = date
        self.amount = amount
    }
}

/// `POST /loans` body. `initialBalance` is the positive outstanding amount.
public struct LoanCreateRequest: Encodable, Sendable, Hashable {
    public var name: String
    public var currencyCode: String
    public var initialBalance: Decimal
    public var loanType: LoanType
    public var originalPrincipal: Decimal
    public var interestRate: Decimal
    public var termMonths: Int?
    public var startDate: CalendarDate
    public var minPayment: Decimal?
    public var plannedPayment: Decimal?
    public var paymentDayOfMonth: Int?
    public var lenderName: String?
    public var accountNumber: String?

    public init(
        name: String,
        currencyCode: String,
        initialBalance: Decimal,
        loanType: LoanType,
        originalPrincipal: Decimal,
        interestRate: Decimal,
        termMonths: Int? = nil,
        startDate: CalendarDate,
        minPayment: Decimal? = nil,
        plannedPayment: Decimal? = nil,
        paymentDayOfMonth: Int? = nil,
        lenderName: String? = nil,
        accountNumber: String? = nil
    ) {
        self.name = name
        self.currencyCode = currencyCode
        self.initialBalance = initialBalance
        self.loanType = loanType
        self.originalPrincipal = originalPrincipal
        self.interestRate = interestRate
        self.termMonths = termMonths
        self.startDate = startDate
        self.minPayment = minPayment
        self.plannedPayment = plannedPayment
        self.paymentDayOfMonth = paymentDayOfMonth
        self.lenderName = lenderName
        self.accountNumber = accountNumber
    }
}

/// `PATCH /loans/:id` body. `.unchanged` fields are left out; `.clear` sends `null`.
/// `currentBalanceAsOf` is only sent alongside `currentBalance`.
public struct LoanUpdateRequest: Encodable, Sendable, Hashable {
    public var name: String?
    public var currentBalance: Decimal?
    public var currentBalanceAsOf: CalendarDate?
    public var interestRate: Decimal?
    public var termMonths: FieldUpdate<Int>
    public var startDate: CalendarDate?
    public var minPayment: FieldUpdate<Decimal>
    public var plannedPayment: FieldUpdate<Decimal>
    public var paymentDayOfMonth: FieldUpdate<Int>
    public var lenderName: FieldUpdate<String>
    public var accountNumber: FieldUpdate<String>

    public init(
        name: String? = nil,
        currentBalance: Decimal? = nil,
        currentBalanceAsOf: CalendarDate? = nil,
        interestRate: Decimal? = nil,
        termMonths: FieldUpdate<Int> = .unchanged,
        startDate: CalendarDate? = nil,
        minPayment: FieldUpdate<Decimal> = .unchanged,
        plannedPayment: FieldUpdate<Decimal> = .unchanged,
        paymentDayOfMonth: FieldUpdate<Int> = .unchanged,
        lenderName: FieldUpdate<String> = .unchanged,
        accountNumber: FieldUpdate<String> = .unchanged
    ) {
        self.name = name
        self.currentBalance = currentBalance
        self.currentBalanceAsOf = currentBalanceAsOf
        self.interestRate = interestRate
        self.termMonths = termMonths
        self.startDate = startDate
        self.minPayment = minPayment
        self.plannedPayment = plannedPayment
        self.paymentDayOfMonth = paymentDayOfMonth
        self.lenderName = lenderName
        self.accountNumber = accountNumber
    }

    /// True when nothing would be sent; the server rejects an empty patch.
    public var isEmpty: Bool {
        name == nil && currentBalance == nil && interestRate == nil && startDate == nil
            && termMonths == .unchanged && minPayment == .unchanged && plannedPayment == .unchanged
            && paymentDayOfMonth == .unchanged && lenderName == .unchanged && accountNumber == .unchanged
    }

    enum CodingKeys: String, CodingKey {
        case name, currentBalance, currentBalanceAsOf, interestRate, termMonths, startDate
        case minPayment, plannedPayment, paymentDayOfMonth, lenderName, accountNumber
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(currentBalance, forKey: .currentBalance)
        if currentBalance != nil {
            try container.encodeIfPresent(currentBalanceAsOf, forKey: .currentBalanceAsOf)
        }
        try container.encodeIfPresent(interestRate, forKey: .interestRate)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try Self.encode(termMonths, into: &container, forKey: .termMonths)
        try Self.encode(minPayment, into: &container, forKey: .minPayment)
        try Self.encode(plannedPayment, into: &container, forKey: .plannedPayment)
        try Self.encode(paymentDayOfMonth, into: &container, forKey: .paymentDayOfMonth)
        try Self.encode(lenderName, into: &container, forKey: .lenderName)
        try Self.encode(accountNumber, into: &container, forKey: .accountNumber)
    }

    private static func encode<Value>(
        _ update: FieldUpdate<Value>,
        into container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        switch update {
        case .unchanged: break
        case .clear: try container.encodeNil(forKey: key)
        case .set(let value): try container.encode(value, forKey: key)
        }
    }
}

struct LoanNoteRequest: Encodable, Sendable, Hashable {
    let text: String
}

/// `POST /loans/:id/link-payments` body.
public struct LoanLinkPaymentsRequest: Encodable, Sendable, Hashable {
    public var transactionIds: [String]
    /// Acknowledges pushing the loan past its outstanding balance.
    public var confirmOverpay: Bool?

    public init(transactionIds: [String], confirmOverpay: Bool? = nil) {
        self.transactionIds = transactionIds
        self.confirmOverpay = confirmOverpay
    }
}

/// `POST /loans/:id/link-payments` reply.
public struct LoanLinkPaymentsResult: Sendable, Hashable, Decodable {
    public let loan: Loan
    public let linkedCount: Int
}

/// `POST /loans/:id/unlink-payment` reply.
public struct LoanUnlinkPaymentResult: Sendable, Hashable, Decodable {
    public let loan: Loan
    public let restoredTransactionId: String?
}

struct LoanUnlinkPaymentRequest: Encodable, Sendable, Hashable {
    let transactionId: String
}
