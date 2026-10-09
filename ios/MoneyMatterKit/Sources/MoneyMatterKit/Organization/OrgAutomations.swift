import Foundation

// MARK: Operators and enums

/// Operators for `note` and `merchant` keyword conditions.
public enum OrgAutomationTextOperator: String, LenientEnum, CaseIterable {
    case containsAny = "contains_any"
    case notContainsAny = "not_contains_any"
    case startsWithAny = "starts_with_any"
    case endsWithAny = "ends_with_any"
    case equalsAny = "equals_any"
    case isEmpty = "is_empty"
    case unknown

    public static var editable: [OrgAutomationTextOperator] { allCases.filter { $0 != .unknown } }
}

/// Operators for id-list conditions (payee, account, account group, bank connection).
public enum OrgAutomationListOperator: String, LenientEnum, CaseIterable {
    case isIn = "in"
    case notIn = "not_in"
    case unknown

    public static var editable: [OrgAutomationListOperator] { [.isIn, .notIn] }
}

public enum OrgAutomationAmountOperator: String, LenientEnum, CaseIterable {
    case gte
    case lte
    case between
    case equals
    case unknown

    public static var editable: [OrgAutomationAmountOperator] { [.gte, .lte, .between, .equals] }
}

public enum OrgAutomationNoteMode: String, LenientEnum, CaseIterable {
    case replace
    case append
    case prepend
    case unknown

    public static var editable: [OrgAutomationNoteMode] { [.replace, .append, .prepend] }
}

public enum OrgAutomationMatch: String, LenientEnum, CaseIterable {
    case all
    case any
    case unknown
}

public enum OrgAutomationTextField: String, Sendable, Hashable, CaseIterable {
    case note
    case merchant
}

public enum OrgAutomationListField: String, Sendable, Hashable, CaseIterable {
    case payee
    case account
    case accountGroup
    case bankConnection
}

/// Which currency an amount condition compares in.
public enum OrgAutomationAmountCurrency: Sendable, Hashable, Codable {
    case transaction
    case base
    case specific(code: String)

    private enum CodingKeys: String, CodingKey { case mode, code }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decodeIfPresent(String.self, forKey: .mode)
        switch mode {
        case "base":
            self = .base
        case "specific":
            if let code = try container.decodeIfPresent(String.self, forKey: .code) {
                self = .specific(code: code)
            } else {
                self = .transaction
            }
        default:
            self = .transaction
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .transaction:
            try container.encode("transaction", forKey: .mode)
        case .base:
            try container.encode("base", forKey: .mode)
        case .specific(let code):
            try container.encode("specific", forKey: .mode)
            try container.encode(code, forKey: .code)
        }
    }
}

// MARK: Conditions

/// One rule condition, mirroring the shared `AutomationCondition` union.
public enum OrgAutomationCondition: Sendable, Hashable, Codable {
    case text(field: OrgAutomationTextField, operator: OrgAutomationTextOperator, keywords: [String])
    case list(field: OrgAutomationListField, operator: OrgAutomationListOperator, ids: [String])
    case amount(operator: OrgAutomationAmountOperator, min: Decimal?, max: Decimal?, currency: OrgAutomationAmountCurrency)
    case transactionType(TransactionType)
    case dayOfMonth(min: Int, max: Int)
    /// A field this app version doesn't know. It can't be re-encoded.
    case unknown(field: String)

    private enum CodingKeys: String, CodingKey { case field, `operator`, value, currency }
    private struct Range: Codable { var min: Decimal?; var max: Decimal? }
    private struct DayRange: Codable { var min: Int; var max: Int }

    /// The `field` key the server uses.
    public var fieldKey: String {
        switch self {
        case .text(let field, _, _): field.rawValue
        case .list(let field, _, _): field.rawValue
        case .amount: "amount"
        case .transactionType: "transactionType"
        case .dayOfMonth: "dayOfMonth"
        case .unknown(let field): field
        }
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let field = try container.decodeIfPresent(String.self, forKey: .field) ?? ""
        if let textField = OrgAutomationTextField(rawValue: field) {
            self = .text(
                field: textField,
                operator: try container.decodeIfPresent(OrgAutomationTextOperator.self, forKey: .operator) ?? .unknown,
                keywords: (try? container.decodeIfPresent([String].self, forKey: .value)) ?? []
            )
        } else if let listField = OrgAutomationListField(rawValue: field) {
            self = .list(
                field: listField,
                operator: try container.decodeIfPresent(OrgAutomationListOperator.self, forKey: .operator) ?? .unknown,
                ids: (try? container.decodeIfPresent([String].self, forKey: .value)) ?? []
            )
        } else if field == "amount" {
            let range = (try? container.decodeIfPresent(Range.self, forKey: .value)) ?? Range()
            self = .amount(
                operator: try container.decodeIfPresent(OrgAutomationAmountOperator.self, forKey: .operator) ?? .unknown,
                min: range.min,
                max: range.max,
                currency: (try? container.decodeIfPresent(OrgAutomationAmountCurrency.self, forKey: .currency)) ?? .transaction
            )
        } else if field == "transactionType" {
            self = .transactionType(try container.decodeIfPresent(TransactionType.self, forKey: .value) ?? .unknown)
        } else if field == "dayOfMonth" {
            let range = (try? container.decodeIfPresent(DayRange.self, forKey: .value)) ?? DayRange(min: 1, max: 31)
            self = .dayOfMonth(min: range.min, max: range.max)
        } else {
            self = .unknown(field: field)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fieldKey, forKey: .field)
        switch self {
        case .text(_, let op, let keywords):
            try container.encode(op, forKey: .operator)
            try container.encode(keywords, forKey: .value)
        case .list(_, let op, let ids):
            try container.encode(op, forKey: .operator)
            try container.encode(ids, forKey: .value)
        case .amount(let op, let min, let max, let currency):
            try container.encode(op, forKey: .operator)
            try container.encode(Range(min: min, max: max), forKey: .value)
            try container.encode(currency, forKey: .currency)
        case .transactionType(let type):
            try container.encode("equals", forKey: .operator)
            try container.encode(type, forKey: .value)
        case .dayOfMonth(let min, let max):
            try container.encode("between", forKey: .operator)
            try container.encode(DayRange(min: min, max: max), forKey: .value)
        case .unknown:
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unknown automation condition")
            )
        }
    }
}

public struct OrgAutomationConditions: Sendable, Hashable, Codable {
    public var match: OrgAutomationMatch
    public var items: [OrgAutomationCondition]

    public init(match: OrgAutomationMatch = .all, items: [OrgAutomationCondition] = []) {
        self.match = match
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case match, items }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        match = try container.decodeLenient(OrgAutomationMatch.self, forKey: .match, default: .all)
        items = try container.decodeLossyArrayIfPresent([OrgAutomationCondition].self, forKey: .items) ?? []
    }
}

// MARK: Actions

public enum OrgAutomationAction: Sendable, Hashable, Codable {
    case setCategory(categoryId: String)
    case addTags(tagIds: [String])
    case setPayee(payeeId: String)
    case setNote(mode: OrgAutomationNoteMode, value: String)
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey { case type, categoryId, tagIds, payeeId, mode, value }

    public var typeKey: String {
        switch self {
        case .setCategory: "set_category"
        case .addTags: "add_tags"
        case .setPayee: "set_payee"
        case .setNote: "set_note"
        case .unknown(let type): type
        }
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        switch type {
        case "set_category":
            self = .setCategory(categoryId: try container.decodeIfPresent(String.self, forKey: .categoryId) ?? "")
        case "add_tags":
            self = .addTags(tagIds: try container.decodeIfPresent([String].self, forKey: .tagIds) ?? [])
        case "set_payee":
            self = .setPayee(payeeId: try container.decodeIfPresent(String.self, forKey: .payeeId) ?? "")
        case "set_note":
            self = .setNote(
                mode: try container.decodeLenient(OrgAutomationNoteMode.self, forKey: .mode, default: .replace),
                value: try container.decodeIfPresent(String.self, forKey: .value) ?? ""
            )
        default:
            self = .unknown(type: type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeKey, forKey: .type)
        switch self {
        case .setCategory(let categoryId):
            try container.encode(categoryId, forKey: .categoryId)
        case .addTags(let tagIds):
            try container.encode(tagIds, forKey: .tagIds)
        case .setPayee(let payeeId):
            try container.encode(payeeId, forKey: .payeeId)
        case .setNote(let mode, let value):
            try container.encode(mode, forKey: .mode)
            try container.encode(value, forKey: .value)
        case .unknown:
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unknown automation action")
            )
        }
    }
}

// MARK: Rule

/// Why the server paused a rule: one of its references was deleted.
public struct OrgAutomationPausedReason: Sendable, Hashable, Decodable {
    public let kind: String?
    public let refType: String?
    public let refId: String?
    public let label: String?
    public let at: Date?
}

/// `GET /automations` row.
public struct OrgAutomation: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let isEnabled: Bool
    public let position: Int
    public let conditions: OrgAutomationConditions
    public let actions: [OrgAutomationAction]
    public let matchCount: Int
    public let lastMatchedAt: Date?
    public let pausedReason: OrgAutomationPausedReason?

    public init(
        id: String,
        name: String,
        isEnabled: Bool = true,
        position: Int = 0,
        conditions: OrgAutomationConditions = OrgAutomationConditions(),
        actions: [OrgAutomationAction] = [],
        matchCount: Int = 0,
        lastMatchedAt: Date? = nil,
        pausedReason: OrgAutomationPausedReason? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.position = position
        self.conditions = conditions
        self.actions = actions
        self.matchCount = matchCount
        self.lastMatchedAt = lastMatchedAt
        self.pausedReason = pausedReason
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, position, conditions, actions, matchCount, lastMatchedAt, pausedReason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        conditions = try container.decodeIfPresent(OrgAutomationConditions.self, forKey: .conditions) ?? OrgAutomationConditions()
        actions = try container.decodeLossyArrayIfPresent([OrgAutomationAction].self, forKey: .actions) ?? []
        matchCount = try container.decodeIfPresent(Int.self, forKey: .matchCount) ?? 0
        lastMatchedAt = try container.decodeIfPresent(Date.self, forKey: .lastMatchedAt)
        pausedReason = try? container.decodeIfPresent(OrgAutomationPausedReason.self, forKey: .pausedReason)
    }

    /// Whether every part decoded into a known shape, so the editor can save it back.
    public var isFullyEditable: Bool {
        !conditions.items.contains(where: \.isUnknown) && !actions.contains(where: \.isUnknown) && conditions.match != .unknown
    }
}

/// `POST /automations` and `PATCH /automations/:id` body. Nil fields are left out.
public struct OrgAutomationPayload: Encodable, Sendable, Hashable {
    public var name: String?
    public var isEnabled: Bool?
    public var conditions: OrgAutomationConditions?
    public var actions: [OrgAutomationAction]?

    public init(name: String? = nil, isEnabled: Bool? = nil, conditions: OrgAutomationConditions? = nil, actions: [OrgAutomationAction]? = nil) {
        self.name = name
        self.isEnabled = isEnabled
        self.conditions = conditions
        self.actions = actions
    }
}

/// `POST /automations/preview` result.
public struct OrgAutomationPreview: Sendable, Hashable, Decodable {
    public let matchedCount: Int
    public let settledCount: Int
    public let scannedCount: Int
    public let matches: [Transaction]

    private enum CodingKeys: String, CodingKey { case matchedCount, settledCount, scannedCount, matches }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchedCount = try container.decodeIfPresent(Int.self, forKey: .matchedCount) ?? 0
        settledCount = try container.decodeIfPresent(Int.self, forKey: .settledCount) ?? 0
        scannedCount = try container.decodeIfPresent(Int.self, forKey: .scannedCount) ?? 0
        matches = try container.decodeLossyArrayIfPresent([Transaction].self, forKey: .matches) ?? []
    }
}

/// `GET /bank-data-providers/connections` row, for the bank connection condition.
public struct OrgAutomationBankConnection: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let providerName: String?
    public let bankName: String?
    public let isActive: Bool?

    public var displayName: String { bankName ?? providerName ?? id }
}

private struct OrgAutomationBankConnectionsBody: Decodable, Sendable {
    let connections: [OrgAutomationBankConnection]
}

private struct OrgAutomationReorderBody: Encodable, Sendable {
    let ids: [String]
}

private struct OrgAutomationPreviewBody: Encodable, Sendable {
    let conditions: OrgAutomationConditions?
    let automationId: String?
    let limit: Int?
}

private struct OrgAutomationApplyBody: Encodable, Sendable {
    let transactionIds: [String]
}

/// `POST /automations/:id/apply` result.
public struct OrgAutomationApplyResult: Sendable, Hashable, Decodable {
    public let appliedCount: Int
    /// Submitted ids that no longer matched, or whose every action was skipped.
    public let skippedIds: [String]

    private enum CodingKeys: String, CodingKey { case appliedCount, skippedIds }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appliedCount = try container.decodeIfPresent(Int.self, forKey: .appliedCount) ?? 0
        skippedIds = try container.decodeIfPresent([String].self, forKey: .skippedIds) ?? []
    }
}

/// Server-side caps from the shared `AUTOMATION_LIMITS`.
public enum OrgAutomationLimits {
    public static let maxConditions = 10
    public static let maxKeywords = 20
    public static let maxKeywordLength = 64
    public static let maxIds = 20
    public static let maxActions = 4
    public static let maxNoteLength = 200
    public static let maxNameLength = 120
    public static let maxApplyIds = 500
}

// MARK: Endpoints

extension Endpoints {
    /// `GET /automations`, in evaluation order.
    public static func orgAutomations() -> Endpoint<[OrgAutomation]> {
        Endpoint(.get, "/automations")
    }

    /// `POST /automations`.
    public static func orgCreateAutomation(_ payload: OrgAutomationPayload) -> Endpoint<OrgAutomation> {
        Endpoint(.post, "/automations", body: payload)
    }

    /// `PATCH /automations/:id`.
    public static func orgUpdateAutomation(id: String, _ payload: OrgAutomationPayload) -> Endpoint<OrgAutomation> {
        Endpoint(.patch, "/automations/\(id)", body: payload)
    }

    /// `DELETE /automations/:id`.
    public static func orgDeleteAutomation(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/automations/\(id)")
    }

    /// `PUT /automations/reorder`: the full id list in the new order.
    public static func orgReorderAutomations(ids: [String]) -> Endpoint<[OrgAutomation]> {
        Endpoint(.put, "/automations/reorder", body: OrgAutomationReorderBody(ids: ids))
    }

    /// `POST /automations/preview` for unsaved conditions.
    public static func orgPreviewAutomation(conditions: OrgAutomationConditions, limit: Int? = nil) -> Endpoint<OrgAutomationPreview> {
        Endpoint(.post, "/automations/preview", body: OrgAutomationPreviewBody(conditions: conditions, automationId: nil, limit: limit))
    }

    /// `POST /automations/preview` for a saved rule, e.g. to review past matches before applying.
    public static func orgPreviewAutomation(automationId: String, limit: Int? = nil) -> Endpoint<OrgAutomationPreview> {
        Endpoint(.post, "/automations/preview", body: OrgAutomationPreviewBody(conditions: nil, automationId: automationId, limit: limit))
    }

    /// `POST /automations/:id/apply`: runs the rule's actions on chosen past transactions.
    public static func orgApplyAutomation(id: String, transactionIds: [String]) -> Endpoint<OrgAutomationApplyResult> {
        Endpoint(.post, "/automations/\(id)/apply", body: OrgAutomationApplyBody(transactionIds: transactionIds))
    }

    /// `GET /bank-data-providers/connections`, unwrapped.
    public static func orgAutomationBankConnections() -> Endpoint<[OrgAutomationBankConnection]> {
        Endpoint<OrgAutomationBankConnectionsBody>(.get, "/bank-data-providers/connections").map { $0.connections }
    }
}
