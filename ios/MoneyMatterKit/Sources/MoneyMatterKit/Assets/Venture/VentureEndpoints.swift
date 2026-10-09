import Foundation

/// `POST /venture/deals` and `PUT /venture/deals/:id` body. Percentages are fractions;
/// nil optionals are sent as `null` so an edit can clear them.
public struct VentureDealRequest: Encodable, Sendable, Hashable {
    public var name: String
    public var currencyCode: String
    public var principal: Decimal
    public var investmentDate: CalendarDate
    public var platformId: String?
    public var spvSubtype: VentureSPVSubtype
    public var targetCompany: String?
    public var entryFeePct: Decimal
    /// Left out when nil, so the server derives it from `entryFeePct`.
    public var entryFee: Decimal?
    public var mgmtFeePct: Decimal
    public var carryPct: Decimal
    public var hurdlePct: Decimal
    public var expectedExitDate: CalendarDate?
    public var notes: String?
    /// Edits only.
    public var status: VentureDealStatus?

    public init(
        name: String,
        currencyCode: String,
        principal: Decimal,
        investmentDate: CalendarDate,
        platformId: String? = nil,
        spvSubtype: VentureSPVSubtype = .multiCompany,
        targetCompany: String? = nil,
        entryFeePct: Decimal = 0,
        entryFee: Decimal? = nil,
        mgmtFeePct: Decimal = 0,
        carryPct: Decimal = 0.2,
        hurdlePct: Decimal = 0,
        expectedExitDate: CalendarDate? = nil,
        notes: String? = nil,
        status: VentureDealStatus? = nil
    ) {
        self.name = name
        self.currencyCode = currencyCode
        self.principal = principal
        self.investmentDate = investmentDate
        self.platformId = platformId
        self.spvSubtype = spvSubtype
        self.targetCompany = targetCompany
        self.entryFeePct = entryFeePct
        self.entryFee = entryFee
        self.mgmtFeePct = mgmtFeePct
        self.carryPct = carryPct
        self.hurdlePct = hurdlePct
        self.expectedExitDate = expectedExitDate
        self.notes = notes
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case name, currencyCode, principal, investmentDate, platformId, spvSubtype, targetCompany
        case entryFeePct, entryFee, mgmtFeePct, carryPct, hurdlePct, expectedExitDate, notes, status
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(principal, forKey: .principal)
        try container.encode(investmentDate, forKey: .investmentDate)
        try container.encode(platformId, forKey: .platformId)
        try container.encode(spvSubtype, forKey: .spvSubtype)
        try container.encode(targetCompany, forKey: .targetCompany)
        try container.encode(entryFeePct, forKey: .entryFeePct)
        try container.encodeIfPresent(entryFee, forKey: .entryFee)
        try container.encode(mgmtFeePct, forKey: .mgmtFeePct)
        try container.encode(carryPct, forKey: .carryPct)
        try container.encode(hurdlePct, forKey: .hurdlePct)
        try container.encode(expectedExitDate, forKey: .expectedExitDate)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(status, forKey: .status)
    }
}

/// `PUT /venture/deals/:id` with the status only.
struct VentureDealStatusRequest: Encodable, Sendable, Hashable {
    let status: VentureDealStatus
}

/// `POST /venture/deals/:dealId/events` body.
public struct VentureEventCreateRequest: Encodable, Sendable, Hashable {
    public var type: VentureEventType
    public var eventDate: CalendarDate
    public var cashFlowMode: VentureCashFlowMode
    public var grossAmount: Decimal?
    public var navAfter: Decimal?
    public var gpCarryOverride: Decimal?
    public var lpNetAmountOverride: Decimal?
    public var notes: String?

    public init(
        type: VentureEventType,
        eventDate: CalendarDate,
        cashFlowMode: VentureCashFlowMode,
        grossAmount: Decimal? = nil,
        navAfter: Decimal? = nil,
        gpCarryOverride: Decimal? = nil,
        lpNetAmountOverride: Decimal? = nil,
        notes: String? = nil
    ) {
        self.type = type
        self.eventDate = eventDate
        self.cashFlowMode = cashFlowMode
        self.grossAmount = grossAmount
        self.navAfter = navAfter
        self.gpCarryOverride = gpCarryOverride
        self.lpNetAmountOverride = lpNetAmountOverride
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case type, eventDate, cashFlowMode, grossAmount, navAfter, gpCarryOverride, lpNetAmountOverride, notes
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(eventDate, forKey: .eventDate)
        try container.encode(cashFlowMode, forKey: .cashFlowMode)
        try container.encode(grossAmount, forKey: .grossAmount)
        try container.encode(navAfter, forKey: .navAfter)
        try container.encode(gpCarryOverride, forKey: .gpCarryOverride)
        try container.encode(lpNetAmountOverride, forKey: .lpNetAmountOverride)
        try container.encode(notes, forKey: .notes)
    }
}

/// `PUT /venture/events/:id` body: date, amounts, and notes. The type and cash flow are
/// fixed. Nil amounts are left out, so fields an event type doesn't use stay untouched;
/// nil notes clear them.
public struct VentureEventUpdateRequest: Encodable, Sendable, Hashable {
    public var eventDate: CalendarDate
    public var grossAmount: Decimal?
    public var navAfter: Decimal?
    public var notes: String?

    public init(eventDate: CalendarDate, grossAmount: Decimal? = nil, navAfter: Decimal? = nil, notes: String? = nil) {
        self.eventDate = eventDate
        self.grossAmount = grossAmount
        self.navAfter = navAfter
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case eventDate, grossAmount, navAfter, notes
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventDate, forKey: .eventDate)
        try container.encodeIfPresent(grossAmount, forKey: .grossAmount)
        try container.encodeIfPresent(navAfter, forKey: .navAfter)
        try container.encode(notes, forKey: .notes)
    }
}

/// `POST /venture/platforms` and `PUT /venture/platforms/:id` body. Percentages are fractions.
public struct VenturePlatformRequest: Encodable, Sendable, Hashable {
    public var name: String
    public var website: String?
    public var description: String?
    public var defaultEntryFeePct: Decimal
    public var defaultMgmtFeePct: Decimal
    public var defaultCarryPct: Decimal
    public var defaultHurdlePct: Decimal

    public init(
        name: String,
        website: String? = nil,
        description: String? = nil,
        defaultEntryFeePct: Decimal = 0,
        defaultMgmtFeePct: Decimal = 0,
        defaultCarryPct: Decimal = 0,
        defaultHurdlePct: Decimal = 0
    ) {
        self.name = name
        self.website = website
        self.description = description
        self.defaultEntryFeePct = defaultEntryFeePct
        self.defaultMgmtFeePct = defaultMgmtFeePct
        self.defaultCarryPct = defaultCarryPct
        self.defaultHurdlePct = defaultHurdlePct
    }

    private enum CodingKeys: String, CodingKey {
        case name, website, description, defaultEntryFeePct, defaultMgmtFeePct, defaultCarryPct, defaultHurdlePct
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(website, forKey: .website)
        try container.encode(description, forKey: .description)
        try container.encode(defaultEntryFeePct, forKey: .defaultEntryFeePct)
        try container.encode(defaultMgmtFeePct, forKey: .defaultMgmtFeePct)
        try container.encode(defaultCarryPct, forKey: .defaultCarryPct)
        try container.encode(defaultHurdlePct, forKey: .defaultHurdlePct)
    }
}

extension Endpoints {
    /// The server caps venture pages at 100 rows.
    static let venturePageLimit = 100

    /// `GET /venture/deals`, unwrapped from its `{data, pagination}` page.
    public static func ventureDeals(status: VentureDealStatus? = nil, platformId: String? = nil) -> Endpoint<[VentureDeal]> {
        var query = QueryBuilder()
        query.add("status", status?.rawValue)
        query.add("platformId", platformId)
        query.add("limit", venturePageLimit)
        return Endpoint<VenturePage<VentureDeal>>(.get, "/venture/deals", query: query.items).map(\.data)
    }

    /// `GET /venture/deals/:id`.
    public static func ventureDeal(id: String) -> Endpoint<VentureDeal> {
        Endpoint(.get, "/venture/deals/\(id)")
    }

    /// `GET /venture/deals/:id/metrics`.
    public static func ventureDealMetrics(id: String) -> Endpoint<VentureDealMetrics> {
        Endpoint(.get, "/venture/deals/\(id)/metrics")
    }

    /// `POST /venture/deals`.
    public static func ventureDealCreate(_ request: VentureDealRequest) -> Endpoint<VentureDeal> {
        Endpoint(.post, "/venture/deals", body: request)
    }

    /// `PUT /venture/deals/:id`.
    public static func ventureDealUpdate(id: String, _ request: VentureDealRequest) -> Endpoint<VentureDeal> {
        Endpoint(.put, "/venture/deals/\(id)", body: request)
    }

    /// `PUT /venture/deals/:id` changing only the status.
    public static func ventureDealSetStatus(id: String, status: VentureDealStatus) -> Endpoint<VentureDeal> {
        Endpoint(.put, "/venture/deals/\(id)", body: VentureDealStatusRequest(status: status))
    }

    /// `DELETE /venture/deals/:id`.
    public static func ventureDealDelete(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/venture/deals/\(id)")
    }

    /// `GET /venture/deals/:dealId/events`.
    public static func ventureEvents(dealId: String) -> Endpoint<[VentureEvent]> {
        Endpoint(.get, "/venture/deals/\(dealId)/events")
    }

    /// `POST /venture/deals/:dealId/events`.
    public static func ventureEventCreate(dealId: String, _ request: VentureEventCreateRequest) -> Endpoint<VentureEvent> {
        Endpoint(.post, "/venture/deals/\(dealId)/events", body: request)
    }

    /// `PUT /venture/events/:id`.
    public static func ventureEventUpdate(id: String, _ request: VentureEventUpdateRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/venture/events/\(id)", body: request)
    }

    /// `DELETE /venture/events/:id`. `deleteLinkedTransactions` only matters for linked events.
    public static func ventureEventDelete(id: String, deleteLinkedTransactions: Bool? = nil) -> Endpoint<EmptyResponse> {
        var query = QueryBuilder()
        query.add("deleteLinkedTransactions", deleteLinkedTransactions)
        return Endpoint(.delete, "/venture/events/\(id)", query: query.items)
    }

    /// `GET /venture/platforms`, unwrapped from its page.
    public static func venturePlatforms() -> Endpoint<[VenturePlatform]> {
        var query = QueryBuilder()
        query.add("limit", venturePageLimit)
        return Endpoint<VenturePage<VenturePlatform>>(.get, "/venture/platforms", query: query.items).map(\.data)
    }

    /// `POST /venture/platforms`.
    public static func venturePlatformCreate(_ request: VenturePlatformRequest) -> Endpoint<VenturePlatform> {
        Endpoint(.post, "/venture/platforms", body: request)
    }

    /// `PUT /venture/platforms/:id`.
    public static func venturePlatformUpdate(id: String, _ request: VenturePlatformRequest) -> Endpoint<VenturePlatform> {
        Endpoint(.put, "/venture/platforms/\(id)", body: request)
    }

    /// `DELETE /venture/platforms/:id`.
    public static func venturePlatformDelete(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/venture/platforms/\(id)")
    }
}
