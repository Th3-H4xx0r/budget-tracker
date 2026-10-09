import Foundation

/// `VEHICLE_CLASS`: picks the default depreciation curve.
public enum VehicleClass: String, LenientEnum, CaseIterable {
    case sedan
    case suv
    case truck
    case luxury
    case ev
    case motorcycle
    case other
    case unknown

    public static var allKnown: [VehicleClass] { allCases.filter { $0 != .unknown } }
}

/// `DEPRECIATION_PRESET`: how the class curve is scaled, or a flat custom rate.
public enum VehicleDepreciationPreset: String, LenientEnum, CaseIterable {
    case classDefault = "class-default"
    case slow
    case average
    case fast
    case custom
    case unknown

    public static var allKnown: [VehicleDepreciationPreset] { allCases.filter { $0 != .unknown } }
}

/// `GET /vehicles` row. Money is in the vehicle account's currency; the account rides
/// inline so a card needs one round-trip.
public struct Vehicle: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let accountId: String
    public let make: String
    public let model: String
    public let trim: String?
    public let year: Int
    public let vehicleClass: VehicleClass
    public let purchasePrice: Decimal
    public let purchaseDate: CalendarDate
    /// Set by a manual value override.
    public let valueAnchor: Decimal?
    public let valueAnchorDate: CalendarDate?
    public let depreciationPreset: VehicleDepreciationPreset
    public let customAnnualRatePct: Decimal?
    public let salvageFloorPct: Decimal
    public let currentMileage: Int?
    public let account: Account?

    public init(
        id: String,
        accountId: String,
        make: String,
        model: String,
        trim: String? = nil,
        year: Int,
        vehicleClass: VehicleClass,
        purchasePrice: Decimal,
        purchaseDate: CalendarDate,
        valueAnchor: Decimal? = nil,
        valueAnchorDate: CalendarDate? = nil,
        depreciationPreset: VehicleDepreciationPreset = .classDefault,
        customAnnualRatePct: Decimal? = nil,
        salvageFloorPct: Decimal = 10,
        currentMileage: Int? = nil,
        account: Account? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.make = make
        self.model = model
        self.trim = trim
        self.year = year
        self.vehicleClass = vehicleClass
        self.purchasePrice = purchasePrice
        self.purchaseDate = purchaseDate
        self.valueAnchor = valueAnchor
        self.valueAnchorDate = valueAnchorDate
        self.depreciationPreset = depreciationPreset
        self.customAnnualRatePct = customAnnualRatePct
        self.salvageFloorPct = salvageFloorPct
        self.currentMileage = currentMileage
        self.account = account
    }

    private enum CodingKeys: String, CodingKey {
        case id, accountId, make, model, trim, year, vehicleClass, purchasePrice, purchaseDate
        case valueAnchor, valueAnchorDate, depreciationPreset, customAnnualRatePct, salvageFloorPct
        case currentMileage, account
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        accountId = try container.decode(String.self, forKey: .accountId)
        make = try container.decodeIfPresent(String.self, forKey: .make) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        trim = try container.decodeIfPresent(String.self, forKey: .trim)
        year = try container.decodeIfPresent(Int.self, forKey: .year) ?? 0
        vehicleClass = try container.decodeLenient(VehicleClass.self, forKey: .vehicleClass, default: .unknown)
        purchasePrice = try container.decodeIfPresent(Decimal.self, forKey: .purchasePrice) ?? 0
        purchaseDate = Self.day(try container.decode(String.self, forKey: .purchaseDate))
            ?? CalendarDate(year: 1970, month: 1, day: 1)
        valueAnchor = try container.decodeIfPresent(Decimal.self, forKey: .valueAnchor)
        valueAnchorDate = try container.decodeIfPresent(String.self, forKey: .valueAnchorDate).flatMap(Self.day)
        depreciationPreset = try container.decodeLenient(
            VehicleDepreciationPreset.self, forKey: .depreciationPreset, default: .classDefault
        )
        customAnnualRatePct = try container.decodeIfPresent(Decimal.self, forKey: .customAnnualRatePct)
        salvageFloorPct = try container.decodeIfPresent(Decimal.self, forKey: .salvageFloorPct) ?? 0
        currentMileage = try container.decodeIfPresent(Int.self, forKey: .currentMileage)
        account = try? container.decodeIfPresent(Account.self, forKey: .account)
    }

    /// Reads `YYYY-MM-DD`, or the day part of a full timestamp.
    private static func day(_ string: String) -> CalendarDate? {
        CalendarDate(string: String(string.prefix(10)))
    }

    /// The account's name, falling back to make and model.
    public var displayName: String {
        if let name = account?.name, !name.isEmpty { return name }
        return "\(make) \(model)"
    }

    /// `2021 Toyota Corolla · LE`.
    public var subtitle: String {
        var text = "\(year) \(make) \(model)"
        if let trim, !trim.isEmpty { text += " · \(trim)" }
        return text
    }

    public var currentValue: Decimal { account?.currentBalance ?? 0 }

    /// Purchase price minus current value: positive when the vehicle lost value.
    public var depreciationAmount: Decimal { purchasePrice - currentValue }

    public var depreciationPercent: Decimal {
        guard purchasePrice != 0 else { return 0 }
        return depreciationAmount / purchasePrice * 100
    }
}

/// `POST /vehicles` body. Creates the vehicle account too.
public struct VehicleCreateRequest: Encodable, Sendable, Hashable {
    public var name: String
    public var currencyCode: String
    public var make: String
    public var model: String
    public var trim: String?
    public var year: Int
    public var vehicleClass: VehicleClass
    public var purchasePrice: Decimal
    /// `YYYY-MM-DD`.
    public var purchaseDate: CalendarDate
    public var depreciationPreset: VehicleDepreciationPreset?
    public var customAnnualRatePct: Decimal?
    public var salvageFloorPct: Decimal?
    public var currentMileage: Int?

    public init(
        name: String,
        currencyCode: String,
        make: String,
        model: String,
        trim: String? = nil,
        year: Int,
        vehicleClass: VehicleClass,
        purchasePrice: Decimal,
        purchaseDate: CalendarDate,
        depreciationPreset: VehicleDepreciationPreset? = nil,
        customAnnualRatePct: Decimal? = nil,
        salvageFloorPct: Decimal? = nil,
        currentMileage: Int? = nil
    ) {
        self.name = name
        self.currencyCode = currencyCode
        self.make = make
        self.model = model
        self.trim = trim
        self.year = year
        self.vehicleClass = vehicleClass
        self.purchasePrice = purchasePrice
        self.purchaseDate = purchaseDate
        self.depreciationPreset = depreciationPreset
        self.customAnnualRatePct = customAnnualRatePct
        self.salvageFloorPct = salvageFloorPct
        self.currentMileage = currentMileage
    }
}

/// `PATCH /vehicles/:id` body. Nil fields are left out; `.clear` sends `null` for the
/// nullable `trim`, `customAnnualRatePct`, and `currentMileage`.
public struct VehicleUpdateRequest: Encodable, Sendable, Hashable {
    public var name: String?
    public var make: String?
    public var model: String?
    public var trim: FieldUpdate<String>
    public var year: Int?
    public var vehicleClass: VehicleClass?
    public var depreciationPreset: VehicleDepreciationPreset?
    public var customAnnualRatePct: FieldUpdate<Decimal>
    public var salvageFloorPct: Decimal?
    public var currentMileage: FieldUpdate<Int>

    public init(
        name: String? = nil,
        make: String? = nil,
        model: String? = nil,
        trim: FieldUpdate<String> = .unchanged,
        year: Int? = nil,
        vehicleClass: VehicleClass? = nil,
        depreciationPreset: VehicleDepreciationPreset? = nil,
        customAnnualRatePct: FieldUpdate<Decimal> = .unchanged,
        salvageFloorPct: Decimal? = nil,
        currentMileage: FieldUpdate<Int> = .unchanged
    ) {
        self.name = name
        self.make = make
        self.model = model
        self.trim = trim
        self.year = year
        self.vehicleClass = vehicleClass
        self.depreciationPreset = depreciationPreset
        self.customAnnualRatePct = customAnnualRatePct
        self.salvageFloorPct = salvageFloorPct
        self.currentMileage = currentMileage
    }

    private enum CodingKeys: String, CodingKey {
        case name, make, model, trim, year, vehicleClass, depreciationPreset
        case customAnnualRatePct, salvageFloorPct, currentMileage
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(make, forKey: .make)
        try container.encodeIfPresent(model, forKey: .model)
        try Self.encode(trim, forKey: .trim, in: &container)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(vehicleClass, forKey: .vehicleClass)
        try container.encodeIfPresent(depreciationPreset, forKey: .depreciationPreset)
        try Self.encode(customAnnualRatePct, forKey: .customAnnualRatePct, in: &container)
        try container.encodeIfPresent(salvageFloorPct, forKey: .salvageFloorPct)
        try Self.encode(currentMileage, forKey: .currentMileage, in: &container)
    }

    private static func encode<Value>(
        _ update: FieldUpdate<Value>,
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

/// `POST /accounts/:id/balance-adjustment` body: the vehicle value override.
public struct VehicleValueOverrideRequest: Encodable, Sendable, Hashable {
    public var targetBalance: Decimal
    public var note: String?
    public var time: Date?

    public init(targetBalance: Decimal, note: String? = nil, time: Date? = nil) {
        self.targetBalance = targetBalance
        self.note = note
        self.time = time
    }
}

/// `POST /accounts/:id/balance-adjustment` reply.
public struct VehicleValueOverrideResult: Sendable, Hashable, Decodable {
    public let previousBalance: Decimal
    public let newBalance: Decimal
}
