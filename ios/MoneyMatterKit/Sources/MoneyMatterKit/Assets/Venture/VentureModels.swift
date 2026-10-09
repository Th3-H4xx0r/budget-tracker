import Foundation

/// `VENTURE_DEAL_STATUS`.
public enum VentureDealStatus: String, LenientEnum, CaseIterable {
    case outstanding
    case partialExit = "partial_exit"
    case fullyExited = "fully_exited"
    case writtenOff = "written_off"
    case unknown

    public static var allKnown: [VentureDealStatus] { allCases.filter { $0 != .unknown } }
}

/// `VENTURE_SPV_SUBTYPE`.
public enum VentureSPVSubtype: String, LenientEnum, CaseIterable {
    case singleCompany = "single_company"
    case multiCompany = "multi_company"
    case unknown

    public static var allKnown: [VentureSPVSubtype] { allCases.filter { $0 != .unknown } }
}

/// `VENTURE_EVENT_TYPE`.
public enum VentureEventType: String, LenientEnum, CaseIterable {
    case initialInvestment = "initial_investment"
    case capitalCall = "capital_call"
    case distribution
    case navUpdate = "nav_update"
    case exit
    case writedown
    case feePayment = "fee_payment"
    case unknown

    public static var allKnown: [VentureEventType] { allCases.filter { $0 != .unknown } }

    /// NAV updates and write-downs move no cash.
    public var isNavOnly: Bool { self == .navUpdate || self == .writedown }

    /// Every type but the initial investment and the NAV-only ones carries a gross amount.
    public var requiresGrossAmount: Bool { self != .initialInvestment && !isNavOnly }

    /// NAV-only events and exits record the NAV after the event.
    public var requiresNavAfter: Bool { isNavOnly || self == .exit }

    /// Distributions and exits are where the GP's carry is taken.
    public var isCarryBearing: Bool { self == .distribution || self == .exit }

    /// Types the user can add next: only the initial investment until one exists, then
    /// everything else.
    public static func creatable(hasInitialInvestment: Bool) -> [VentureEventType] {
        hasInitialInvestment ? allKnown.filter { $0 != .initialInvestment } : [.initialInvestment]
    }
}

/// `VENTURE_CASH_FLOW_MODE`: whether an event moves money through a real account
/// (`linked`), outside the tracked accounts (`out_of_wallet`), or not at all.
public enum VentureCashFlowMode: String, LenientEnum, CaseIterable {
    case linked
    case outOfWallet = "out_of_wallet"
    case none
    case unknown
}

extension KeyedDecodingContainer {
    /// Venture amounts arrive as decimal strings (`"1000.0000000000"`); numbers are accepted too.
    func ventureDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let number = try? decode(Decimal.self, forKey: key) { return number }
        let string = try decode(String.self, forKey: key)
        return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
    }

    func ventureDay(forKey key: Key) throws -> CalendarDate? {
        guard let string = try decodeIfPresent(String.self, forKey: key) else { return nil }
        return CalendarDate(string: String(string.prefix(10)))
    }
}

/// `GET /venture/platforms` row: a syndicate or fund platform with default fee terms.
/// Percentages are fractions, e.g. `0.2` for 20%.
public struct VenturePlatform: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let website: String?
    public let platformDescription: String?
    public let defaultEntryFeePct: Decimal
    public let defaultMgmtFeePct: Decimal
    public let defaultCarryPct: Decimal
    public let defaultHurdlePct: Decimal

    public init(
        id: String,
        name: String,
        website: String? = nil,
        platformDescription: String? = nil,
        defaultEntryFeePct: Decimal = 0,
        defaultMgmtFeePct: Decimal = 0,
        defaultCarryPct: Decimal = 0,
        defaultHurdlePct: Decimal = 0
    ) {
        self.id = id
        self.name = name
        self.website = website
        self.platformDescription = platformDescription
        self.defaultEntryFeePct = defaultEntryFeePct
        self.defaultMgmtFeePct = defaultMgmtFeePct
        self.defaultCarryPct = defaultCarryPct
        self.defaultHurdlePct = defaultHurdlePct
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, website, description
        case defaultEntryFeePct, defaultMgmtFeePct, defaultCarryPct, defaultHurdlePct
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        website = try container.decodeIfPresent(String.self, forKey: .website)
        platformDescription = try container.decodeIfPresent(String.self, forKey: .description)
        defaultEntryFeePct = try container.ventureDecimalIfPresent(forKey: .defaultEntryFeePct) ?? 0
        defaultMgmtFeePct = try container.ventureDecimalIfPresent(forKey: .defaultMgmtFeePct) ?? 0
        defaultCarryPct = try container.ventureDecimalIfPresent(forKey: .defaultCarryPct) ?? 0
        defaultHurdlePct = try container.ventureDecimalIfPresent(forKey: .defaultHurdlePct) ?? 0
    }
}

/// A transaction linked to a venture event.
public struct VentureEventLink: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let transactionId: String
}

/// `GET /venture/deals/:id/events` row.
public struct VentureEvent: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let dealId: String
    public let type: VentureEventType
    public let eventDate: CalendarDate
    public let grossAmount: Decimal?
    public let gpCarryAmount: Decimal?
    public let lpNetAmount: Decimal?
    public let navAfter: Decimal?
    public let quantityPct: Decimal?
    public let lpNetAmountOverridden: Bool
    public let gpCarryOverridden: Bool
    public let currencyCode: String
    public let cashFlowMode: VentureCashFlowMode
    public let notes: String?
    public let links: [VentureEventLink]

    private enum CodingKeys: String, CodingKey {
        case id, dealId, type, eventDate, grossAmount, gpCarryAmount, lpNetAmount, navAfter, quantityPct
        case lpNetAmountOverridden, gpCarryOverridden, currencyCode, cashFlowMode, notes, links
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        dealId = try container.decodeIfPresent(String.self, forKey: .dealId) ?? ""
        type = try container.decodeLenient(VentureEventType.self, forKey: .type, default: .unknown)
        eventDate = try container.ventureDay(forKey: .eventDate) ?? CalendarDate(year: 1970, month: 1, day: 1)
        grossAmount = try container.ventureDecimalIfPresent(forKey: .grossAmount)
        gpCarryAmount = try container.ventureDecimalIfPresent(forKey: .gpCarryAmount)
        lpNetAmount = try container.ventureDecimalIfPresent(forKey: .lpNetAmount)
        navAfter = try container.ventureDecimalIfPresent(forKey: .navAfter)
        quantityPct = try container.ventureDecimalIfPresent(forKey: .quantityPct)
        lpNetAmountOverridden = try container.decodeIfPresent(Bool.self, forKey: .lpNetAmountOverridden) ?? false
        gpCarryOverridden = try container.decodeIfPresent(Bool.self, forKey: .gpCarryOverridden) ?? false
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? ""
        cashFlowMode = try container.decodeLenient(VentureCashFlowMode.self, forKey: .cashFlowMode, default: .unknown)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        links = try container.decodeLossyArrayIfPresent([VentureEventLink].self, forKey: .links) ?? []
    }
}

/// `GET /venture/deals` row. Percentages are fractions.
public struct VentureDeal: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let platformId: String?
    public let name: String
    public let spvSubtype: VentureSPVSubtype?
    public let targetCompany: String?
    public let currencyCode: String
    public let status: VentureDealStatus
    public let principal: Decimal
    public let entryFee: Decimal
    public let entryFeePct: Decimal
    public let mgmtFeePct: Decimal
    public let carryPct: Decimal
    public let hurdlePct: Decimal
    public let investmentDate: CalendarDate
    public let expectedExitDate: CalendarDate?
    public let notes: String?
    public let platform: VenturePlatform?

    public init(
        id: String,
        platformId: String? = nil,
        name: String,
        spvSubtype: VentureSPVSubtype? = nil,
        targetCompany: String? = nil,
        currencyCode: String,
        status: VentureDealStatus = .outstanding,
        principal: Decimal,
        entryFee: Decimal = 0,
        entryFeePct: Decimal = 0,
        mgmtFeePct: Decimal = 0,
        carryPct: Decimal = 0,
        hurdlePct: Decimal = 0,
        investmentDate: CalendarDate,
        expectedExitDate: CalendarDate? = nil,
        notes: String? = nil,
        platform: VenturePlatform? = nil
    ) {
        self.id = id
        self.platformId = platformId
        self.name = name
        self.spvSubtype = spvSubtype
        self.targetCompany = targetCompany
        self.currencyCode = currencyCode
        self.status = status
        self.principal = principal
        self.entryFee = entryFee
        self.entryFeePct = entryFeePct
        self.mgmtFeePct = mgmtFeePct
        self.carryPct = carryPct
        self.hurdlePct = hurdlePct
        self.investmentDate = investmentDate
        self.expectedExitDate = expectedExitDate
        self.notes = notes
        self.platform = platform
    }

    private enum CodingKeys: String, CodingKey {
        case id, platformId, name, spvSubtype, targetCompany, currencyCode, status, principal, entryFee
        case entryFeePct, mgmtFeePct, carryPct, hurdlePct, investmentDate, expectedExitDate, notes, platform
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        platformId = try container.decodeIfPresent(String.self, forKey: .platformId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        spvSubtype = try container.decodeIfPresent(VentureSPVSubtype.self, forKey: .spvSubtype)
        targetCompany = try container.decodeIfPresent(String.self, forKey: .targetCompany)
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? ""
        status = try container.decodeLenient(VentureDealStatus.self, forKey: .status, default: .unknown)
        principal = try container.ventureDecimalIfPresent(forKey: .principal) ?? 0
        entryFee = try container.ventureDecimalIfPresent(forKey: .entryFee) ?? 0
        entryFeePct = try container.ventureDecimalIfPresent(forKey: .entryFeePct) ?? 0
        mgmtFeePct = try container.ventureDecimalIfPresent(forKey: .mgmtFeePct) ?? 0
        carryPct = try container.ventureDecimalIfPresent(forKey: .carryPct) ?? 0
        hurdlePct = try container.ventureDecimalIfPresent(forKey: .hurdlePct) ?? 0
        investmentDate = try container.ventureDay(forKey: .investmentDate) ?? CalendarDate(year: 1970, month: 1, day: 1)
        expectedExitDate = try container.ventureDay(forKey: .expectedExitDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        platform = try? container.decodeIfPresent(VenturePlatform.self, forKey: .platform)
    }
}

/// `GET /venture/deals/:id/metrics`. Multiples and IRR are nil until computable.
public struct VentureDealMetrics: Sendable, Hashable, Decodable {
    public let costBasis: Decimal
    public let totalInvested: Decimal
    public let currentValue: Decimal
    public let totalDistributions: Decimal
    public let pnlAbsolute: Decimal
    /// A fraction, e.g. `0.25` for +25%.
    public let pnlPct: Decimal?
    public let tvpi: Decimal?
    public let dpi: Decimal?
    /// A fraction.
    public let irr: Decimal?

    private enum CodingKeys: String, CodingKey {
        case costBasis, totalInvested, currentValue, totalDistributions, pnlAbsolute, pnlPct, tvpi, dpi, irr
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        costBasis = try container.ventureDecimalIfPresent(forKey: .costBasis) ?? 0
        totalInvested = try container.ventureDecimalIfPresent(forKey: .totalInvested) ?? 0
        currentValue = try container.ventureDecimalIfPresent(forKey: .currentValue) ?? 0
        totalDistributions = try container.ventureDecimalIfPresent(forKey: .totalDistributions) ?? 0
        pnlAbsolute = try container.ventureDecimalIfPresent(forKey: .pnlAbsolute) ?? 0
        pnlPct = try container.ventureDecimalIfPresent(forKey: .pnlPct)
        tvpi = try container.ventureDecimalIfPresent(forKey: .tvpi)
        dpi = try container.ventureDecimalIfPresent(forKey: .dpi)
        irr = try container.ventureDecimalIfPresent(forKey: .irr)
    }
}

/// The `{data, pagination}` wrapper of the venture list routes.
struct VenturePage<Element: Decodable & Sendable>: Decodable, Sendable {
    let data: [Element]
}
