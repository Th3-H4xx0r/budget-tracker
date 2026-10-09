import Foundation

/// `GET /account-group` row with the logo and bank-connection fields the editor needs.
/// Child groups appear both in the flat list and nested under their parent.
public struct OrgAccountGroup: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let parentGroupId: String?
    /// Set for groups a bank connection created and manages.
    public let bankDataProviderConnectionId: String?
    public let logoDomain: String?
    public let logoInitials: String?
    public let logoColor: String?
    public let accounts: [Account]
    public let childGroups: [OrgAccountGroup]

    public init(
        id: String,
        name: String,
        parentGroupId: String? = nil,
        bankDataProviderConnectionId: String? = nil,
        logoDomain: String? = nil,
        logoInitials: String? = nil,
        logoColor: String? = nil,
        accounts: [Account] = [],
        childGroups: [OrgAccountGroup] = []
    ) {
        self.id = id
        self.name = name
        self.parentGroupId = parentGroupId
        self.bankDataProviderConnectionId = bankDataProviderConnectionId
        self.logoDomain = logoDomain
        self.logoInitials = logoInitials
        self.logoColor = logoColor
        self.accounts = accounts
        self.childGroups = childGroups
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, parentGroupId, bankDataProviderConnectionId, logoDomain, logoInitials, logoColor
        case accounts, childGroups
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        parentGroupId = try container.decodeIfPresent(String.self, forKey: .parentGroupId)
        bankDataProviderConnectionId = try container.decodeIfPresent(String.self, forKey: .bankDataProviderConnectionId)
        logoDomain = try container.decodeIfPresent(String.self, forKey: .logoDomain)
        logoInitials = try container.decodeIfPresent(String.self, forKey: .logoInitials)
        logoColor = try container.decodeIfPresent(String.self, forKey: .logoColor)
        accounts = try container.decodeLossyArrayIfPresent([Account].self, forKey: .accounts) ?? []
        childGroups = try container.decodeLossyArrayIfPresent([OrgAccountGroup].self, forKey: .childGroups) ?? []
    }

    /// The root groups of a flat list, children nested; a group whose parent is missing
    /// from the list is treated as a root.
    public static func roots(of groups: [OrgAccountGroup]) -> [OrgAccountGroup] {
        let ids = Set(groups.map(\.id))
        return groups.filter { group in
            guard let parent = group.parentGroupId else { return true }
            return !ids.contains(parent)
        }
    }

    /// Every group nested below this one, depth first.
    public var descendantIDs: Set<String> {
        Set(childGroups.flatMap { [$0.id] + $0.descendantIDs })
    }
}

/// How a group's logo is drawn: a brand domain, monogram letters, or neither. The server
/// rejects a domain and initials together.
public enum OrgAccountGroupLogo: Sendable, Hashable {
    case none
    case domain(String)
    case initials(String, color: String?)
}

/// `POST /account-group` and `PUT /account-group/:id` body.
public struct OrgAccountGroupRequest: Encodable, Sendable, Hashable {
    public var name: String
    /// Only sent on create; moves go through `orgMoveAccountGroup`.
    public var parentGroupId: String?
    public var logo: OrgAccountGroupLogo
    /// Updates send `null` for the logo fields the chosen style doesn't use, to clear them.
    public var isUpdate: Bool

    public init(name: String, parentGroupId: String? = nil, logo: OrgAccountGroupLogo = .none, isUpdate: Bool) {
        self.name = name
        self.parentGroupId = parentGroupId
        self.logo = logo
        self.isUpdate = isUpdate
    }

    private enum CodingKeys: String, CodingKey { case name, parentGroupId, logoDomain, logoInitials, logoColor }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if !isUpdate { try container.encodeIfPresent(parentGroupId, forKey: .parentGroupId) }
        switch logo {
        case .none:
            if isUpdate {
                try container.encodeNil(forKey: .logoDomain)
                try container.encodeNil(forKey: .logoInitials)
                try container.encodeNil(forKey: .logoColor)
            }
        case .domain(let domain):
            try container.encode(domain, forKey: .logoDomain)
            if isUpdate {
                try container.encodeNil(forKey: .logoInitials)
                try container.encodeNil(forKey: .logoColor)
            }
        case .initials(let initials, let color):
            try container.encode(initials, forKey: .logoInitials)
            if let color {
                try container.encode(color, forKey: .logoColor)
            } else if isUpdate {
                try container.encodeNil(forKey: .logoColor)
            }
            if isUpdate { try container.encodeNil(forKey: .logoDomain) }
        }
    }
}

struct OrgMoveAccountGroupBody: Encodable, Sendable {
    let newParentGroupId: String?

    private enum CodingKeys: String, CodingKey { case newParentGroupId }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let newParentGroupId {
            try container.encode(newParentGroupId, forKey: .newParentGroupId)
        } else {
            try container.encodeNil(forKey: .newParentGroupId)
        }
    }
}

struct OrgAccountIDsBody: Encodable, Sendable {
    let accountIds: [String]
}

extension Endpoints {
    /// `GET /account-group` with logo fields. `includeArchived` is a `z.coerce` boolean,
    /// so it's only ever sent as `true`.
    public static func orgAccountGroups(includeArchived: Bool = false) -> Endpoint<[OrgAccountGroup]> {
        var query = QueryBuilder()
        query.addFlag("includeArchived", includeArchived)
        return Endpoint(.get, "/account-group", query: query.items)
    }

    /// `POST /account-group`.
    public static func orgCreateAccountGroup(_ request: OrgAccountGroupRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/account-group", body: request)
    }

    /// `PUT /account-group/:id`.
    public static func orgUpdateAccountGroup(id: String, _ request: OrgAccountGroupRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/account-group/\(id)", body: request)
    }

    /// `PUT /account-group/:id/move`: `nil` makes the group a root.
    public static func orgMoveAccountGroup(id: String, newParentGroupId: String?) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/account-group/\(id)/move", body: OrgMoveAccountGroupBody(newParentGroupId: newParentGroupId))
    }

    /// `DELETE /account-group/:id`.
    public static func orgDeleteAccountGroup(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/account-group/\(id)")
    }

    /// `POST /account-group/:groupId/add-account/:accountId`.
    public static func orgAddAccountToGroup(groupId: String, accountId: String) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/account-group/\(groupId)/add-account/\(accountId)")
    }

    /// `DELETE /account-group/:groupId/accounts`.
    public static func orgRemoveAccountsFromGroup(groupId: String, accountIds: [String]) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/account-group/\(groupId)/accounts", body: OrgAccountIDsBody(accountIds: accountIds))
    }
}
