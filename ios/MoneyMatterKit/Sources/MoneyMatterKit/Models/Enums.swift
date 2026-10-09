import Foundation

// Mirrors of the backend enums in `packages/shared/src/types/enums.ts`.

public enum TransactionType: String, LenientEnum, CaseIterable {
    case income
    case expense
    case unknown

    /// The opposite direction, e.g. for the second leg of a transfer.
    public var flipped: TransactionType {
        switch self {
        case .income: .expense
        case .expense: .income
        case .unknown: .unknown
        }
    }
}

public enum PaymentType: String, LenientEnum, CaseIterable {
    case bankTransfer
    case voucher
    case webPayment
    case cash
    case mobilePayment
    case creditCard
    case debitCard
    case unknown
}

public enum TransferNature: String, LenientEnum, CaseIterable {
    case notTransfer = "not_transfer"
    case betweenUserAccounts = "transfer_between_user_accounts"
    case outOfWallet = "transfer_out_wallet"
    case toPortfolio = "transfer_to_portfolio"
    case toVenture = "transfer_to_venture"
    case toLoan = "transfer_to_loan"
    case unknown

    /// Two linked legs sharing a `transferId`. A loan payment behaves like a normal transfer.
    public var isTwoLegTransfer: Bool {
        self == .betweenUserAccounts || self == .toLoan
    }

    /// Every known nature except out-of-wallet transfers: the set the Home "latest
    /// records" list asks for.
    public static var latestRecordsNatures: [TransferNature] {
        [.notTransfer, .betweenUserAccounts, .toPortfolio, .toVenture, .toLoan]
    }
}

public enum ReviewStatus: String, LenientEnum, CaseIterable {
    case notRequired = "not_required"
    case unreviewed
    case reviewed
    case fraud
    case unknown
}

/// The three review tabs, and the `status` param of `GET /transactions/review`.
public enum ReviewListStatus: String, Sendable, Hashable, CaseIterable, Identifiable {
    case unreviewed
    case reviewed
    case fraud

    public var id: String { rawValue }
}

/// The `action` of `PUT /transactions/review`. "Check later" keeps the row unreviewed and
/// stamps `reviewDeferredAt`.
public enum ReviewAction: String, Sendable, Hashable, Codable, CaseIterable {
    case reviewed
    case checkLater = "check_later"
    case fraud
    case unreviewed
}

public enum AccountType: String, LenientEnum, CaseIterable {
    case system
    case monobank
    case enableBanking = "enable-banking"
    case lunchflow
    case walutomat
    case simplefin
    case unknown
}

public enum BankProviderType: String, LenientEnum, CaseIterable {
    case monobank
    case enableBanking = "enable-banking"
    case lunchflow
    case walutomat
    case simplefin
    case unknown
}

public enum AccountCategory: String, LenientEnum, CaseIterable {
    case general
    case cash
    case currentAccount = "current-account"
    case creditCard = "credit-card"
    case saving
    case bonus
    case insurance
    case investment
    case loan
    case overdraft
    case crypto
    case vehicle
    case unknown

    /// Categories `POST /accounts` accepts. Loans and vehicles have their own creation flows.
    public static var creatable: [AccountCategory] {
        allCases.filter { $0 != .loan && $0 != .vehicle && $0 != .unknown }
    }
}

public enum AccountStatus: String, LenientEnum, CaseIterable {
    case active
    case archived
    case unknown
}

public enum CategoryType: String, LenientEnum, CaseIterable {
    case custom
    /// Seeded categories that can't be edited or deleted.
    case `internal`
    case unknown
}

public enum UserRole: String, LenientEnum, CaseIterable {
    case admin
    case common
    case demo
    case unknown
}

public enum SubscriptionType: String, LenientEnum, CaseIterable {
    case subscription
    case bill
    case installment
    case unknown
}

public enum SubscriptionFrequency: String, LenientEnum, CaseIterable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case semiAnnual = "semi_annual"
    case annual
    case unknown
}

public enum SubscriptionPeriodStatus: String, LenientEnum, CaseIterable {
    case upcoming
    case paid
    case overdue
    case skipped
    case unknown
}

public enum OAuthProvider: String, Sendable, Hashable, CaseIterable {
    case google
    case github
}

public enum SortOrder: String, Sendable, Hashable {
    case ascending = "ASC"
    case descending = "DESC"
}

/// `all|exclude|only` filters on the transactions list.
public enum InclusionFilter: String, Sendable, Hashable {
    case all
    case exclude
    case only
}
