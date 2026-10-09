import Foundation

/// `GET /user`: the app user, with the email from better-auth.
public struct User: Sendable, Hashable, Identifiable, Decodable {
    public let id: Int
    public let username: String
    public let firstName: String?
    public let lastName: String?
    public let middleName: String?
    public let avatar: String?
    public let email: String?
    public let role: UserRole
    public let defaultCategoryId: String?
    public let authUserId: String?
    public let createdAt: Date?
    public let entitlements: Entitlements?
    /// Set by the server from its admin username list, independent of `role`.
    public let isAdmin: Bool

    public init(
        id: Int,
        username: String,
        firstName: String? = nil,
        lastName: String? = nil,
        middleName: String? = nil,
        avatar: String? = nil,
        email: String? = nil,
        role: UserRole = .common,
        defaultCategoryId: String? = nil,
        authUserId: String? = nil,
        createdAt: Date? = nil,
        entitlements: Entitlements? = nil,
        isAdmin: Bool = false
    ) {
        self.id = id
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
        self.middleName = middleName
        self.avatar = avatar
        self.email = email
        self.role = role
        self.defaultCategoryId = defaultCategoryId
        self.authUserId = authUserId
        self.createdAt = createdAt
        self.entitlements = entitlements
        self.isAdmin = isAdmin
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, firstName, lastName, middleName, avatar, email, role
        case defaultCategoryId, authUserId, createdAt, entitlements, isAdmin
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        middleName = try container.decodeIfPresent(String.self, forKey: .middleName)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        role = try container.decodeLenient(UserRole.self, forKey: .role, default: .common)
        defaultCategoryId = try container.decodeIfPresent(String.self, forKey: .defaultCategoryId)
        authUserId = try container.decodeIfPresent(String.self, forKey: .authUserId)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        entitlements = try? container.decodeIfPresent(Entitlements.self, forKey: .entitlements)
        isAdmin = (try? container.decodeIfPresent(Bool.self, forKey: .isAdmin)) ?? false
    }

    /// "First Last", falling back to the username.
    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? username : parts.joined(separator: " ")
    }

    /// Up to two initials for an avatar badge.
    public var initials: String {
        let source = displayName.isEmpty ? (email ?? "?") : displayName
        let letters = source.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

public struct Entitlements: Sendable, Hashable, Decodable {
    public let features: [String]
    public let readOnly: Bool
    public let plan: String?
    public let trialEndsAt: Date?

    private enum CodingKeys: String, CodingKey { case features, readOnly, plan, trialEndsAt }

    public init(features: [String] = [], readOnly: Bool = false, plan: String? = nil, trialEndsAt: Date? = nil) {
        self.features = features
        self.readOnly = readOnly
        self.plan = plan
        self.trialEndsAt = trialEndsAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        features = (try? container.decodeIfPresent([String].self, forKey: .features)) ?? []
        readOnly = (try? container.decodeIfPresent(Bool.self, forKey: .readOnly)) ?? false
        plan = try? container.decodeIfPresent(String.self, forKey: .plan)
        trialEndsAt = try? container.decodeIfPresent(Date.self, forKey: .trialEndsAt)
    }
}
