import Foundation

/// `GET /payees/lookup`: the unpaginated list used to resolve `payeeId` to a name.
public struct PayeeLookup: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let logoDomain: String?
    public let logoInitials: String?
    public let logoColor: String?

    public init(id: String, name: String, logoDomain: String? = nil, logoInitials: String? = nil, logoColor: String? = nil) {
        self.id = id
        self.name = name
        self.logoDomain = logoDomain
        self.logoInitials = logoInitials
        self.logoColor = logoColor
    }
}

/// `GET /payees?q=`: a search result for the payee picker.
public struct Payee: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    /// Applied to new transactions for this payee unless the user picks another.
    public let defaultCategoryId: String?
    public let defaultTagIds: [String]
    public let logoDomain: String?
    public let logoInitials: String?
    public let logoColor: String?
    public let stats: PayeeStats?

    public init(
        id: String,
        name: String,
        defaultCategoryId: String? = nil,
        defaultTagIds: [String] = [],
        logoDomain: String? = nil,
        logoInitials: String? = nil,
        logoColor: String? = nil,
        stats: PayeeStats? = nil
    ) {
        self.id = id
        self.name = name
        self.defaultCategoryId = defaultCategoryId
        self.defaultTagIds = defaultTagIds
        self.logoDomain = logoDomain
        self.logoInitials = logoInitials
        self.logoColor = logoColor
        self.stats = stats
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, defaultCategoryId, defaultTagIds, logoDomain, logoInitials, logoColor, stats
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        defaultCategoryId = try container.decodeIfPresent(String.self, forKey: .defaultCategoryId)
        defaultTagIds = try container.decodeIfPresent([String].self, forKey: .defaultTagIds) ?? []
        logoDomain = try container.decodeIfPresent(String.self, forKey: .logoDomain)
        logoInitials = try container.decodeIfPresent(String.self, forKey: .logoInitials)
        logoColor = try container.decodeIfPresent(String.self, forKey: .logoColor)
        stats = try? container.decodeIfPresent(PayeeStats.self, forKey: .stats)
    }

    public var lookup: PayeeLookup {
        PayeeLookup(id: id, name: name, logoDomain: logoDomain, logoInitials: logoInitials, logoColor: logoColor)
    }
}

public struct PayeeStats: Sendable, Hashable, Decodable {
    public let transactionCount: Int?
    public let lastSeenAt: Date?
    public let topCategoryId: String?
}
