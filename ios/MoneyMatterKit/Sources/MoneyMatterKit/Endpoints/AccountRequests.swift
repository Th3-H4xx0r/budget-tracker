import Foundation

/// `POST /accounts` body.
public struct AccountCreateRequest: Encodable, Sendable, Hashable {
    public var name: String
    public var currencyCode: String
    public var accountCategory: AccountCategory
    public var initialBalance: Decimal?
    /// Credit cards only.
    public var creditLimit: Decimal?

    public init(
        name: String,
        currencyCode: String,
        accountCategory: AccountCategory = .general,
        initialBalance: Decimal? = nil,
        creditLimit: Decimal? = nil
    ) {
        self.name = name
        self.currencyCode = currencyCode
        self.accountCategory = accountCategory
        self.initialBalance = initialBalance
        self.creditLimit = creditLimit
    }
}

/// `PUT /accounts/:id` body. Nil fields are left unchanged.
public struct AccountUpdateRequest: Encodable, Sendable, Hashable {
    public var name: String?
    public var accountCategory: AccountCategory?
    public var creditLimit: Decimal?
    public var status: AccountStatus?
    public var excludeFromStats: Bool?
    /// System accounts only.
    public var currentBalance: Decimal?

    public init(
        name: String? = nil,
        accountCategory: AccountCategory? = nil,
        creditLimit: Decimal? = nil,
        status: AccountStatus? = nil,
        excludeFromStats: Bool? = nil,
        currentBalance: Decimal? = nil
    ) {
        self.name = name
        self.accountCategory = accountCategory
        self.creditLimit = creditLimit
        self.status = status
        self.excludeFromStats = excludeFromStats
        self.currentBalance = currentBalance
    }
}
