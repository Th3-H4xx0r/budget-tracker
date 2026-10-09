import Foundation

// MARK: - Categories

/// `POST /categories` body. A subcategory may leave `color` out and inherit its parent's;
/// a root category must send one.
public struct OrgCategoryCreateRequest: Encodable, Sendable, Hashable {
    public var name: String
    /// `#rrggbb`.
    public var color: String?
    /// A Fluent icon name such as `food-20-filled`.
    public var icon: String?
    public var parentId: String?

    public init(name: String, color: String?, icon: String?, parentId: String?) {
        self.name = name
        self.color = color
        self.icon = icon
        self.parentId = parentId
    }

    private enum CodingKeys: String, CodingKey { case name, color, icon, parentId }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(parentId, forKey: .parentId)
    }
}

/// `PUT /categories/:id` body. `icon` and `parentId` accept `null`; `parentId: null` makes
/// the category a root.
public struct OrgCategoryUpdateRequest: Encodable, Sendable, Hashable {
    public var name: String?
    public var color: String?
    public var icon: FieldUpdate<String>
    public var parentId: FieldUpdate<String>

    public init(
        name: String? = nil,
        color: String? = nil,
        icon: FieldUpdate<String> = .unchanged,
        parentId: FieldUpdate<String> = .unchanged
    ) {
        self.name = name
        self.color = color
        self.icon = icon
        self.parentId = parentId
    }

    private enum CodingKeys: String, CodingKey { case name, color, icon, parentId }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(color, forKey: .color)
        try container.orgTaxonomyEncode(icon, forKey: .icon)
        try container.orgTaxonomyEncode(parentId, forKey: .parentId)
    }
}

struct OrgCategoryDeleteBody: Encodable, Sendable {
    let replaceWithCategoryId: String
}

struct OrgCategoryTransactionCount: Decodable, Sendable {
    let transactionCount: Int
}

// MARK: - Tags

/// `POST /tags` and `PUT /tags/:id` body. Every field is sent; a nil `icon` or
/// `description` is sent as `null`, which clears it on update.
public struct OrgTagRequest: Encodable, Sendable, Hashable {
    public var name: String
    /// `#rrggbb`.
    public var color: String
    public var icon: String?
    public var description: String?

    public init(name: String, color: String, icon: String?, description: String?) {
        self.name = name
        self.color = color
        self.icon = icon
        self.description = description
    }

    private enum CodingKeys: String, CodingKey { case name, color, icon, description }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        if let icon { try container.encode(icon, forKey: .icon) } else { try container.encodeNil(forKey: .icon) }
        if let description {
            try container.encode(description, forKey: .description)
        } else {
            try container.encodeNil(forKey: .description)
        }
    }
}

// MARK: - Tag reminders

public enum OrgTagReminderType: String, LenientEnum, CaseIterable {
    /// Fires when tagged spending reaches `amountThreshold`.
    case amountThreshold = "amount_threshold"
    /// Fires when no transaction carries the tag during the period.
    case existenceCheck = "existence_check"
    case unknown

    public static var allKnown: [OrgTagReminderType] { [.amountThreshold, .existenceCheck] }
}

public enum OrgTagReminderFrequency: String, LenientEnum, CaseIterable {
    case daily, weekly, monthly, quarterly, yearly
    case unknown

    public static var allKnown: [OrgTagReminderFrequency] { [.daily, .weekly, .monthly, .quarterly, .yearly] }

    /// Monthly and longer schedules run on a chosen day of the month.
    public var usesDayOfMonth: Bool {
        self == .monthly || self == .quarterly || self == .yearly
    }
}

/// `GET /tags/:tagId/reminders` row.
public struct OrgTagReminder: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let tagId: String
    public let type: OrgTagReminderType
    /// `nil` means real time: the reminder fires as soon as a transaction is tagged.
    public let frequency: OrgTagReminderFrequency?
    /// 1–31, for monthly and longer schedules. `nil` means the 1st.
    public let dayOfMonth: Int?
    /// The `amount_threshold` limit, as a decimal.
    public let amountThreshold: Decimal?
    public let isEnabled: Bool
    public let lastTriggeredAt: Date?

    public init(
        id: String,
        tagId: String,
        type: OrgTagReminderType,
        frequency: OrgTagReminderFrequency? = nil,
        dayOfMonth: Int? = nil,
        amountThreshold: Decimal? = nil,
        isEnabled: Bool = true,
        lastTriggeredAt: Date? = nil
    ) {
        self.id = id
        self.tagId = tagId
        self.type = type
        self.frequency = frequency
        self.dayOfMonth = dayOfMonth
        self.amountThreshold = amountThreshold
        self.isEnabled = isEnabled
        self.lastTriggeredAt = lastTriggeredAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, tagId, type, frequency, dayOfMonth, settings, isEnabled, lastTriggeredAt
    }

    private enum SettingsKeys: String, CodingKey { case amountThreshold }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        tagId = try container.decodeIfPresent(String.self, forKey: .tagId) ?? ""
        type = try container.decodeLenient(OrgTagReminderType.self, forKey: .type, default: .unknown)
        frequency = try container.decodeIfPresent(OrgTagReminderFrequency.self, forKey: .frequency)
        dayOfMonth = try container.decodeIfPresent(Int.self, forKey: .dayOfMonth)
        if let settings = try? container.nestedContainer(keyedBy: SettingsKeys.self, forKey: .settings) {
            amountThreshold = try? settings.decodeIfPresent(Decimal.self, forKey: .amountThreshold)
        } else {
            amountThreshold = nil
        }
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        lastTriggeredAt = try? container.decodeIfPresent(Date.self, forKey: .lastTriggeredAt)
    }
}

/// `POST /tags/:tagId/reminders` and `PUT /tags/:tagId/reminders/:id` body.
public struct OrgTagReminderRequest: Encodable, Sendable, Hashable {
    public var type: OrgTagReminderType
    /// `nil` sends `null`: a real-time reminder.
    public var frequency: OrgTagReminderFrequency?
    /// Sent only for monthly and longer schedules; otherwise `null`.
    public var dayOfMonth: Int?
    /// Sent in `settings` for `amount_threshold` reminders.
    public var amountThreshold: Decimal?
    public var isEnabled: Bool

    public init(
        type: OrgTagReminderType,
        frequency: OrgTagReminderFrequency?,
        dayOfMonth: Int?,
        amountThreshold: Decimal?,
        isEnabled: Bool
    ) {
        self.type = type
        self.frequency = frequency
        self.dayOfMonth = dayOfMonth
        self.amountThreshold = amountThreshold
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey { case type, frequency, dayOfMonth, settings, isEnabled }
    private enum SettingsKeys: String, CodingKey { case amountThreshold }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let frequency { try container.encode(frequency, forKey: .frequency) } else { try container.encodeNil(forKey: .frequency) }
        if let dayOfMonth, frequency?.usesDayOfMonth == true {
            try container.encode(dayOfMonth, forKey: .dayOfMonth)
        } else {
            try container.encodeNil(forKey: .dayOfMonth)
        }
        var settings = container.nestedContainer(keyedBy: SettingsKeys.self, forKey: .settings)
        if type == .amountThreshold, let amountThreshold {
            try settings.encode(amountThreshold, forKey: .amountThreshold)
        }
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}

// MARK: - Endpoints

extension Endpoints {
    /// `POST /categories`.
    public static func orgCreateCategory(_ request: OrgCategoryCreateRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/categories", body: request)
    }

    /// `PUT /categories/:id`. Changing `parentId` moves the category.
    public static func orgUpdateCategory(id: String, _ request: OrgCategoryUpdateRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/categories/\(id)", body: request)
    }

    /// `DELETE /categories/:id`. Fails with 409 when transactions use the category and no
    /// replacement is given; the replacement then takes over those transactions.
    public static func orgDeleteCategory(id: String, replaceWithCategoryId: String? = nil) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/categories/\(id)", body: replaceWithCategoryId.map(OrgCategoryDeleteBody.init))
    }

    /// `GET /categories/:id/transaction-count`.
    public static func orgCategoryTransactionCount(id: String) -> Endpoint<Int> {
        Endpoint<OrgCategoryTransactionCount>(.get, "/categories/\(id)/transaction-count").map(\.transactionCount)
    }

    /// `POST /tags`.
    public static func orgCreateTag(_ request: OrgTagRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/tags", body: request)
    }

    /// `PUT /tags/:id`.
    public static func orgUpdateTag(id: String, _ request: OrgTagRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/tags/\(id)", body: request)
    }

    /// `DELETE /tags/:id`.
    public static func orgDeleteTag(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/tags/\(id)")
    }

    /// `GET /tags/:tagId/reminders`.
    public static func orgTagReminders(tagId: String) -> Endpoint<[OrgTagReminder]> {
        Endpoint(.get, "/tags/\(tagId)/reminders")
    }

    /// `POST /tags/:tagId/reminders`.
    public static func orgCreateTagReminder(tagId: String, _ request: OrgTagReminderRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/tags/\(tagId)/reminders", body: request)
    }

    /// `PUT /tags/:tagId/reminders/:id`.
    public static func orgUpdateTagReminder(
        tagId: String,
        id: String,
        _ request: OrgTagReminderRequest
    ) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/tags/\(tagId)/reminders/\(id)", body: request)
    }

    /// `DELETE /tags/:tagId/reminders/:id`.
    public static func orgDeleteTagReminder(tagId: String, id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/tags/\(tagId)/reminders/\(id)")
    }
}

extension KeyedEncodingContainer {
    fileprivate mutating func orgTaxonomyEncode<Value>(_ update: FieldUpdate<Value>, forKey key: Key) throws {
        switch update {
        case .unchanged: break
        case .clear: try encodeNil(forKey: key)
        case .set(let value): try encode(value, forKey: key)
        }
    }
}
