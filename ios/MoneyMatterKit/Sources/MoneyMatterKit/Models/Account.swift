import Foundation

/// `GET /accounts`. Balances are in the account currency; the `ref*` twins are in the
/// user's base currency.
public struct Account: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let initialBalance: Decimal
    public let refInitialBalance: Decimal
    public let currentBalance: Decimal
    public let refCurrentBalance: Decimal
    public let creditLimit: Decimal
    public let refCreditLimit: Decimal
    public let type: AccountType
    public let accountCategory: AccountCategory
    public let currencyCode: String
    public let userId: Int?
    public let status: AccountStatus
    public let excludeFromStats: Bool
    public let bankDataProviderConnectionId: String?
    public let bankProviderType: BankProviderType?
    public let needsRelink: Bool?
    public let logoDomain: String?
    public let logoInitials: String?
    public let logoColor: String?
    public let share: AccountShare?

    public init(
        id: String,
        name: String,
        currencyCode: String,
        currentBalance: Decimal = 0,
        refCurrentBalance: Decimal? = nil,
        initialBalance: Decimal = 0,
        refInitialBalance: Decimal? = nil,
        creditLimit: Decimal = 0,
        refCreditLimit: Decimal? = nil,
        type: AccountType = .system,
        accountCategory: AccountCategory = .general,
        userId: Int? = nil,
        status: AccountStatus = .active,
        excludeFromStats: Bool = false,
        bankDataProviderConnectionId: String? = nil,
        bankProviderType: BankProviderType? = nil,
        needsRelink: Bool? = nil,
        logoDomain: String? = nil,
        logoInitials: String? = nil,
        logoColor: String? = nil,
        share: AccountShare? = nil
    ) {
        self.id = id
        self.name = name
        self.currencyCode = currencyCode
        self.currentBalance = currentBalance
        self.refCurrentBalance = refCurrentBalance ?? currentBalance
        self.initialBalance = initialBalance
        self.refInitialBalance = refInitialBalance ?? initialBalance
        self.creditLimit = creditLimit
        self.refCreditLimit = refCreditLimit ?? creditLimit
        self.type = type
        self.accountCategory = accountCategory
        self.userId = userId
        self.status = status
        self.excludeFromStats = excludeFromStats
        self.bankDataProviderConnectionId = bankDataProviderConnectionId
        self.bankProviderType = bankProviderType
        self.needsRelink = needsRelink
        self.logoDomain = logoDomain
        self.logoInitials = logoInitials
        self.logoColor = logoColor
        self.share = share
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, initialBalance, refInitialBalance, currentBalance, refCurrentBalance
        case creditLimit, refCreditLimit, type, accountCategory, currencyCode, userId, status
        case excludeFromStats, bankDataProviderConnectionId, bankProviderType, needsRelink
        case logoDomain, logoInitials, logoColor, share
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        initialBalance = try container.decodeIfPresent(Decimal.self, forKey: .initialBalance) ?? 0
        refInitialBalance = try container.decodeIfPresent(Decimal.self, forKey: .refInitialBalance) ?? initialBalance
        currentBalance = try container.decodeIfPresent(Decimal.self, forKey: .currentBalance) ?? 0
        refCurrentBalance = try container.decodeIfPresent(Decimal.self, forKey: .refCurrentBalance) ?? currentBalance
        creditLimit = try container.decodeIfPresent(Decimal.self, forKey: .creditLimit) ?? 0
        refCreditLimit = try container.decodeIfPresent(Decimal.self, forKey: .refCreditLimit) ?? creditLimit
        type = try container.decodeLenient(AccountType.self, forKey: .type, default: .unknown)
        accountCategory = try container.decodeLenient(AccountCategory.self, forKey: .accountCategory, default: .general)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId)
        status = try container.decodeLenient(AccountStatus.self, forKey: .status, default: .active)
        excludeFromStats = try container.decodeIfPresent(Bool.self, forKey: .excludeFromStats) ?? false
        bankDataProviderConnectionId = try container.decodeIfPresent(String.self, forKey: .bankDataProviderConnectionId)
        bankProviderType = try container.decodeIfPresent(BankProviderType.self, forKey: .bankProviderType)
        needsRelink = try container.decodeIfPresent(Bool.self, forKey: .needsRelink)
        logoDomain = try container.decodeIfPresent(String.self, forKey: .logoDomain)
        logoInitials = try container.decodeIfPresent(String.self, forKey: .logoInitials)
        logoColor = try container.decodeIfPresent(String.self, forKey: .logoColor)
        share = try? container.decodeIfPresent(AccountShare.self, forKey: .share)
    }

    public var isArchived: Bool { status == .archived }

    /// Manually created accounts. Only these accept new non-planned transactions and a
    /// directly edited current balance.
    public var isSystem: Bool { type == .system }

    /// Shared with the user by someone else.
    public var isSharedWithMe: Bool { share.map { !$0.isOwner } ?? false }

    /// Counts toward the net worth summary.
    public var countsTowardNetWorth: Bool { status == .active && !excludeFromStats }
}

/// Present on accounts shared through households or direct shares.
public struct AccountShare: Sendable, Hashable, Decodable {
    public struct Owner: Sendable, Hashable, Decodable {
        public let id: Int
        public let username: String
        public let avatar: String?
    }

    public let isOwner: Bool
    public let owner: Owner?
    public let permission: String?
    public let accessSource: String?
}

/// `GET /account-group`. Roots have `parentGroupId == nil`; child groups appear both in the
/// flat list and nested under their parent.
public struct AccountGroup: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let parentGroupId: String?
    public let accounts: [Account]
    public let childGroups: [AccountGroup]

    public init(id: String, name: String, parentGroupId: String? = nil, accounts: [Account] = [], childGroups: [AccountGroup] = []) {
        self.id = id
        self.name = name
        self.parentGroupId = parentGroupId
        self.accounts = accounts
        self.childGroups = childGroups
    }

    private enum CodingKeys: String, CodingKey { case id, name, parentGroupId, accounts, childGroups }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        parentGroupId = try container.decodeIfPresent(String.self, forKey: .parentGroupId)
        accounts = try container.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        childGroups = try container.decodeIfPresent([AccountGroup].self, forKey: .childGroups) ?? []
    }

    public var isRoot: Bool { parentGroupId == nil }

    /// This group's accounts followed by every nested group's, depth first.
    public var allAccounts: [Account] {
        accounts + childGroups.flatMap(\.allAccounts)
    }

    /// The root groups of a flat `GET /account-group` list.
    public static func roots(of groups: [AccountGroup]) -> [AccountGroup] {
        groups.filter(\.isRoot)
    }
}

/// `GET /accounts/:id/transaction-count`.
struct TransactionCountResponse: Decodable {
    let transactionCount: Int
}
