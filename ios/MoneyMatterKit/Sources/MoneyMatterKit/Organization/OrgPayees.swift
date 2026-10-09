import Foundation

// MARK: - Models

/// How strongly a payee's default category applies to new transactions.
/// `enforce` sets it outright, `hint` lets AI override it, `off` skips it.
public enum OrgPayeeCategorizationMode: String, LenientEnum, CaseIterable {
    case enforce
    case hint
    case off
    case unknown

    public static var allCases: [OrgPayeeCategorizationMode] { [.enforce, .hint, .off] }
}

/// `GET /payees?sortBy=`.
public enum OrgPayeeSortField: String, Sendable, Hashable, CaseIterable {
    case transactionCount
    case netFlow
    case name
    case lastSeen

    /// Numbers read largest-first; names read A to Z.
    public var defaultDirection: OrgPayeeSortDirection {
        self == .name ? .asc : .desc
    }
}

public enum OrgPayeeSortDirection: String, Sendable, Hashable {
    case asc
    case desc
}

/// One raw bank name that resolves to a payee. The canonical alias can't be deleted.
public struct OrgPayeeAlias: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let payeeId: String?
    public let rawName: String
    public let normalizedName: String?
    public let isCanonical: Bool
    public let createdAt: Date?

    public init(id: String, payeeId: String? = nil, rawName: String, normalizedName: String? = nil, isCanonical: Bool = false, createdAt: Date? = nil) {
        self.id = id
        self.payeeId = payeeId
        self.rawName = rawName
        self.normalizedName = normalizedName
        self.isCanonical = isCanonical
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, payeeId, rawName, normalizedName, isCanonical, createdAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        payeeId = try container.decodeIfPresent(String.self, forKey: .payeeId)
        rawName = try container.decode(String.self, forKey: .rawName)
        normalizedName = try container.decodeIfPresent(String.self, forKey: .normalizedName)
        isCanonical = try container.decodeIfPresent(Bool.self, forKey: .isCanonical) ?? false
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

/// Aggregates computed from the payee's transactions. `netFlowRef` is signed, in the base currency.
public struct OrgPayeeStats: Sendable, Hashable, Decodable {
    public let transactionCount: Int
    public let netFlowRef: Decimal
    public let firstSeenAt: Date?
    public let lastSeenAt: Date?
    public let topCategoryId: String?

    public init(transactionCount: Int = 0, netFlowRef: Decimal = 0, firstSeenAt: Date? = nil, lastSeenAt: Date? = nil, topCategoryId: String? = nil) {
        self.transactionCount = transactionCount
        self.netFlowRef = netFlowRef
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.topCategoryId = topCategoryId
    }

    private enum CodingKeys: String, CodingKey { case transactionCount, netFlowRef, firstSeenAt, lastSeenAt, topCategoryId }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactionCount = try container.decodeIfPresent(Int.self, forKey: .transactionCount) ?? 0
        netFlowRef = try container.decodeIfPresent(Decimal.self, forKey: .netFlowRef) ?? 0
        firstSeenAt = try? container.decodeIfPresent(Date.self, forKey: .firstSeenAt)
        lastSeenAt = try? container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        topCategoryId = try container.decodeIfPresent(String.self, forKey: .topCategoryId)
    }
}

/// A full payee as `GET /payees`, `GET /payees/:id`, and payee writes return it.
/// Writes omit `stats`; `GET /payees/:id` includes `aliases`.
public struct OrgPayee: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let defaultCategoryId: String?
    public let categorizationMode: OrgPayeeCategorizationMode
    public let defaultTagIds: [String]
    public let logoDomain: String?
    public let logoInitials: String?
    public let logoColor: String?
    /// `auto`, `manual`, or nil before the logo resolver has run.
    public let logoSource: String?
    public let aliases: [OrgPayeeAlias]?
    public let stats: OrgPayeeStats?

    public init(
        id: String,
        name: String,
        defaultCategoryId: String? = nil,
        categorizationMode: OrgPayeeCategorizationMode = .enforce,
        defaultTagIds: [String] = [],
        logoDomain: String? = nil,
        logoInitials: String? = nil,
        logoColor: String? = nil,
        logoSource: String? = nil,
        aliases: [OrgPayeeAlias]? = nil,
        stats: OrgPayeeStats? = nil
    ) {
        self.id = id
        self.name = name
        self.defaultCategoryId = defaultCategoryId
        self.categorizationMode = categorizationMode
        self.defaultTagIds = defaultTagIds
        self.logoDomain = logoDomain
        self.logoInitials = logoInitials
        self.logoColor = logoColor
        self.logoSource = logoSource
        self.aliases = aliases
        self.stats = stats
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, defaultCategoryId, categorizationMode, defaultTagIds
        case logoDomain, logoInitials, logoColor, logoSource, aliases, stats
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        defaultCategoryId = try container.decodeIfPresent(String.self, forKey: .defaultCategoryId)
        categorizationMode = try container.decodeLenient(OrgPayeeCategorizationMode.self, forKey: .categorizationMode, default: .enforce)
        defaultTagIds = try container.decodeIfPresent([String].self, forKey: .defaultTagIds) ?? []
        logoDomain = try container.decodeIfPresent(String.self, forKey: .logoDomain)
        logoInitials = try container.decodeIfPresent(String.self, forKey: .logoInitials)
        logoColor = try container.decodeIfPresent(String.self, forKey: .logoColor)
        logoSource = try container.decodeIfPresent(String.self, forKey: .logoSource)
        aliases = try container.decodeLossyArrayIfPresent([OrgPayeeAlias].self, forKey: .aliases)
        stats = try? container.decodeIfPresent(OrgPayeeStats.self, forKey: .stats)
    }

    /// The category the list shows: the default, else the most-used one.
    public var displayCategoryId: String? {
        defaultCategoryId ?? stats?.topCategoryId
    }

    public var lookup: PayeeLookup {
        PayeeLookup(id: id, name: name, logoDomain: logoDomain, logoInitials: logoInitials, logoColor: logoColor)
    }
}

/// `GET /payees/ignored-names` row: a bank name that never becomes a payee.
public struct OrgPayeeIgnoredName: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let normalizedName: String
    public let rawSample: String?
    public let createdAt: Date?

    public init(id: String, normalizedName: String, rawSample: String? = nil, createdAt: Date? = nil) {
        self.id = id
        self.normalizedName = normalizedName
        self.rawSample = rawSample
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, normalizedName, rawSample, createdAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        normalizedName = try container.decodeIfPresent(String.self, forKey: .normalizedName) ?? ""
        rawSample = try container.decodeIfPresent(String.self, forKey: .rawSample)
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    /// The name as the user typed it, else the normalized form.
    public var displayName: String {
        if let rawSample, !rawSample.isEmpty { return rawSample }
        return normalizedName
    }
}

/// The payee-related slice of `GET /user/settings`; other keys are ignored.
public struct OrgPayeeUserSettings: Sendable, Hashable, Decodable {
    /// Derive the payee from the transaction description when the bank sends no merchant.
    public let payeeExtractionUsesDescription: Bool
    /// How many times a name must appear before it becomes a payee (1–3).
    public let payeePromotionThreshold: Int

    public init(payeeExtractionUsesDescription: Bool = false, payeePromotionThreshold: Int = 2) {
        self.payeeExtractionUsesDescription = payeeExtractionUsesDescription
        self.payeePromotionThreshold = payeePromotionThreshold
    }

    private enum CodingKeys: String, CodingKey { case payeeExtractionUsesDescription, payeePromotionThreshold }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payeeExtractionUsesDescription = try container.decodeIfPresent(Bool.self, forKey: .payeeExtractionUsesDescription) ?? false
        payeePromotionThreshold = try container.decodeIfPresent(Int.self, forKey: .payeePromotionThreshold) ?? 2
    }
}

public struct OrgPayeeApplyTagsResult: Sendable, Hashable, Decodable {
    public let updatedTransactionsCount: Int
}

public struct OrgPayeeBulkModeResult: Sendable, Hashable, Decodable {
    public let updatedCount: Int
}

public struct OrgPayeeDeleteAndIgnoreResult: Sendable, Hashable, Decodable {
    public let ignoredAddedCount: Int
}

// MARK: - Requests

/// `POST /payees` and `PATCH /payees/:id` body. Logo fields: `.clear` sends `null`.
/// A logo domain and custom initials are mutually exclusive; set one and clear the other.
public struct OrgPayeeWriteRequest: Encodable, Sendable, Hashable {
    public var name: String?
    public var defaultCategoryId: FieldUpdate<String>
    public var categorizationMode: OrgPayeeCategorizationMode?
    public var defaultTagIds: [String]?
    public var logoDomain: FieldUpdate<String>
    public var logoInitials: FieldUpdate<String>
    public var logoColor: FieldUpdate<String>

    public init(
        name: String? = nil,
        defaultCategoryId: FieldUpdate<String> = .unchanged,
        categorizationMode: OrgPayeeCategorizationMode? = nil,
        defaultTagIds: [String]? = nil,
        logoDomain: FieldUpdate<String> = .unchanged,
        logoInitials: FieldUpdate<String> = .unchanged,
        logoColor: FieldUpdate<String> = .unchanged
    ) {
        self.name = name
        self.defaultCategoryId = defaultCategoryId
        self.categorizationMode = categorizationMode
        self.defaultTagIds = defaultTagIds
        self.logoDomain = logoDomain
        self.logoInitials = logoInitials
        self.logoColor = logoColor
    }

    private enum CodingKeys: String, CodingKey {
        case name, defaultCategoryId, categorizationMode, defaultTagIds, logoDomain, logoInitials, logoColor
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.orgPayeeEncode(defaultCategoryId, forKey: .defaultCategoryId)
        if let categorizationMode, categorizationMode != .unknown {
            try container.encode(categorizationMode, forKey: .categorizationMode)
        }
        try container.encodeIfPresent(defaultTagIds, forKey: .defaultTagIds)
        try container.orgPayeeEncode(logoDomain, forKey: .logoDomain)
        try container.orgPayeeEncode(logoInitials, forKey: .logoInitials)
        try container.orgPayeeEncode(logoColor, forKey: .logoColor)
    }
}

/// `PATCH /user/settings` body for the payee settings; absent keys stay as stored.
public struct OrgPayeeSettingsPatch: Encodable, Sendable, Hashable {
    public var payeeExtractionUsesDescription: Bool?
    public var payeePromotionThreshold: Int?

    public init(payeeExtractionUsesDescription: Bool? = nil, payeePromotionThreshold: Int? = nil) {
        self.payeeExtractionUsesDescription = payeeExtractionUsesDescription
        self.payeePromotionThreshold = payeePromotionThreshold
    }
}

struct OrgPayeeMergeBody: Encodable, Sendable {
    let targetPayeeId: String
}

struct OrgPayeeRawNameBody: Encodable, Sendable {
    let rawName: String
}

struct OrgPayeeIgnoredNameBody: Encodable, Sendable {
    let rawName: String
    let force: Bool?
}

struct OrgPayeeBulkModeBody: Encodable, Sendable {
    let mode: OrgPayeeCategorizationMode
}

struct OrgPayeeEmptyBody: Encodable, Sendable {}

extension KeyedEncodingContainer {
    fileprivate mutating func orgPayeeEncode<Value>(_ update: FieldUpdate<Value>, forKey key: Key) throws {
        switch update {
        case .unchanged:
            break
        case .clear:
            try encodeNil(forKey: key)
        case .set(let value):
            try encode(value, forKey: key)
        }
    }
}

// MARK: - Endpoints

extension Endpoints {
    /// `GET /payees`: payees with stats, sorted server-side. A search caps the page at 20.
    public static func orgPayees(
        query: String? = nil,
        sortBy: OrgPayeeSortField? = nil,
        sortDir: OrgPayeeSortDirection? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) -> Endpoint<[OrgPayee]> {
        var builder = QueryBuilder()
        builder.add("q", query?.trimmingCharacters(in: .whitespacesAndNewlines))
        builder.add("limit", limit)
        builder.add("offset", offset)
        builder.add("sortBy", sortBy?.rawValue)
        builder.add("sortDir", sortDir?.rawValue)
        return Endpoint(.get, "/payees", query: builder.items)
    }

    /// `GET /payees/:id`: the payee with aliases and stats.
    public static func orgPayee(id: String) -> Endpoint<OrgPayee> {
        Endpoint(.get, "/payees/\(id)")
    }

    /// `POST /payees`. 409 when the name already resolves to another payee.
    public static func orgCreatePayee(_ request: OrgPayeeWriteRequest) -> Endpoint<OrgPayee> {
        Endpoint(.post, "/payees", body: request)
    }

    /// `PATCH /payees/:id`.
    public static func orgUpdatePayee(id: String, _ request: OrgPayeeWriteRequest) -> Endpoint<OrgPayee> {
        Endpoint(.patch, "/payees/\(id)", body: request)
    }

    /// `DELETE /payees/:id`: unlinks its transactions and deletes it (204).
    public static func orgDeletePayee(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/payees/\(id)")
    }

    /// `DELETE /payees/:id?ignoreFuture=true`: deletes it and adds its names to the ignore list.
    public static func orgDeletePayeeAndIgnore(id: String) -> Endpoint<OrgPayeeDeleteAndIgnoreResult> {
        Endpoint(
            .delete,
            "/payees/\(id)",
            query: [URLQueryItem(name: "ignoreFuture", value: "true")]
        )
    }

    /// `POST /payees/:id/merge`: moves the source's transactions and aliases to the target.
    public static func orgMergePayee(sourceId: String, targetPayeeId: String) -> Endpoint<OrgPayee> {
        Endpoint(.post, "/payees/\(sourceId)/merge", body: OrgPayeeMergeBody(targetPayeeId: targetPayeeId))
    }

    /// `POST /payees/:id/aliases`. 409 when the name belongs to another payee.
    public static func orgCreatePayeeAlias(payeeId: String, rawName: String) -> Endpoint<OrgPayee> {
        Endpoint(.post, "/payees/\(payeeId)/aliases", body: OrgPayeeRawNameBody(rawName: rawName))
    }

    /// `DELETE /payees/:id/aliases/:aliasId`. 422 for the canonical alias.
    public static func orgDeletePayeeAlias(payeeId: String, aliasId: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/payees/\(payeeId)/aliases/\(aliasId)")
    }

    /// `POST /payees/:id/apply-tags`: adds the default tags to the payee's existing transactions.
    public static func orgApplyPayeeTags(id: String) -> Endpoint<OrgPayeeApplyTagsResult> {
        Endpoint(.post, "/payees/\(id)/apply-tags", body: OrgPayeeEmptyBody())
    }

    /// `POST /payees/:id/reset-logo`: hands the logo back to the automatic resolver.
    public static func orgResetPayeeLogo(id: String) -> Endpoint<OrgPayee> {
        Endpoint(.post, "/payees/\(id)/reset-logo", body: OrgPayeeEmptyBody())
    }

    /// `PATCH /payees/bulk-categorization-mode`: sets the mode on every payee.
    public static func orgBulkPayeeCategorizationMode(_ mode: OrgPayeeCategorizationMode) -> Endpoint<OrgPayeeBulkModeResult> {
        Endpoint(.patch, "/payees/bulk-categorization-mode", body: OrgPayeeBulkModeBody(mode: mode))
    }

    /// `GET /payees/ignored-names`.
    public static func orgPayeeIgnoredNames() -> Endpoint<[OrgPayeeIgnoredName]> {
        Endpoint(.get, "/payees/ignored-names")
    }

    /// `POST /payees/ignored-names`. 409 when a payee already has the name; `force` deletes that payee.
    public static func orgAddPayeeIgnoredName(rawName: String, force: Bool = false) -> Endpoint<OrgPayeeIgnoredName> {
        Endpoint(.post, "/payees/ignored-names", body: OrgPayeeIgnoredNameBody(rawName: rawName, force: force ? true : nil))
    }

    /// `DELETE /payees/ignored-names/:id`.
    public static func orgRemovePayeeIgnoredName(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/payees/ignored-names/\(id)")
    }

    /// `GET /user/settings`, decoding only the payee settings.
    public static func orgPayeeUserSettings() -> Endpoint<OrgPayeeUserSettings> {
        Endpoint(.get, "/user/settings")
    }

    /// `PATCH /user/settings`: the server deep-merges the keys sent.
    public static func orgPatchPayeeSettings(_ patch: OrgPayeeSettingsPatch) -> Endpoint<OrgPayeeUserSettings> {
        Endpoint(.patch, "/user/settings", body: patch)
    }
}
