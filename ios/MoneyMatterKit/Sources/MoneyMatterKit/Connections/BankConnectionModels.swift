import Foundation

// MARK: - Providers and connections

/// `GET /bank-data-providers`: one bank data provider the server supports.
public struct BankProviderInfo: Sendable, Hashable, Decodable, Identifiable {
    public let type: BankProviderType
    public let name: String
    public let description: String?
    public let logoUrl: String?
    public let documentationUrl: String?

    public var id: String { type.rawValue }

    public init(type: BankProviderType, name: String, description: String? = nil, logoUrl: String? = nil, documentationUrl: String? = nil) {
        self.type = type
        self.name = name
        self.description = description
        self.logoUrl = logoUrl
        self.documentationUrl = documentationUrl
    }
}

/// `GET /bank-data-providers/connections`: one row of the connections list.
public struct BankConnectionSummary: Sendable, Hashable, Decodable, Identifiable {
    public let id: String
    public let providerType: BankProviderType
    public let providerName: String
    public let isActive: Bool
    public let lastSyncAt: Date?
    public let accountsCount: Int
    public let createdAt: Date?
    public let bankName: String?

    private enum CodingKeys: String, CodingKey {
        case id, providerType, providerName, isActive, lastSyncAt, accountsCount, createdAt, bankName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.e1DecodeID(forKey: .id)
        providerType = try container.decodeLenient(BankProviderType.self, forKey: .providerType, default: .unknown)
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName) ?? ""
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        lastSyncAt = container.e1DecodeDate(forKey: .lastSyncAt)
        accountsCount = try container.decodeIfPresent(Int.self, forKey: .accountsCount) ?? 0
        createdAt = container.e1DecodeDate(forKey: .createdAt)
        bankName = try container.decodeIfPresent(String.self, forKey: .bankName)
    }
}

/// `GET /bank-data-providers/connections/:id`.
public struct BankConnectionDetail: Sendable, Hashable, Decodable, Identifiable {
    public struct Account: Sendable, Hashable, Decodable, Identifiable {
        public struct CurrencyFallback: Sendable, Hashable, Decodable {
            public let providerCurrency: String
            public let assignedCurrency: String
        }

        public let id: String
        public let name: String
        public let externalId: String
        public let currentBalance: Decimal
        public let currencyCode: String
        public let type: String?
        public let currencyFallback: CurrencyFallback?

        private enum CodingKeys: String, CodingKey {
            case id, name, externalId, currentBalance, currencyCode, type, currencyFallback
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.e1DecodeID(forKey: .id)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            externalId = try container.decodeIfPresent(String.self, forKey: .externalId) ?? ""
            currentBalance = try container.decodeIfPresent(Decimal.self, forKey: .currentBalance) ?? 0
            currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? ""
            type = try container.decodeIfPresent(String.self, forKey: .type)
            currencyFallback = try? container.decodeIfPresent(CurrencyFallback.self, forKey: .currencyFallback)
        }
    }

    public struct Consent: Sendable, Hashable, Decodable {
        public let validFrom: Date?
        public let validUntil: Date?
        public let daysRemaining: Int?
        public let isExpired: Bool
        public let isExpiringSoon: Bool

        private enum CodingKeys: String, CodingKey {
            case validFrom, validUntil, daysRemaining, isExpired, isExpiringSoon
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            validFrom = container.e1DecodeDate(forKey: .validFrom)
            validUntil = container.e1DecodeDate(forKey: .validUntil)
            daysRemaining = try container.decodeIfPresent(Int.self, forKey: .daysRemaining)
            isExpired = try container.decodeIfPresent(Bool.self, forKey: .isExpired) ?? false
            isExpiringSoon = try container.decodeIfPresent(Bool.self, forKey: .isExpiringSoon) ?? false
        }
    }

    public struct Provider: Sendable, Hashable, Decodable {
        public let name: String?
        public let description: String?
    }

    public let id: String
    public let providerType: BankProviderType
    public let providerName: String
    public let isActive: Bool
    public let lastSyncAt: Date?
    public let createdAt: Date?
    public let provider: Provider?
    public let accounts: [Account]
    public let consent: Consent?
    public let deactivationReason: String?

    private enum CodingKeys: String, CodingKey {
        case id, providerType, providerName, isActive, lastSyncAt, createdAt, provider, accounts, consent, deactivationReason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.e1DecodeID(forKey: .id)
        providerType = try container.decodeLenient(BankProviderType.self, forKey: .providerType, default: .unknown)
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName) ?? ""
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        lastSyncAt = container.e1DecodeDate(forKey: .lastSyncAt)
        createdAt = container.e1DecodeDate(forKey: .createdAt)
        provider = try? container.decodeIfPresent(Provider.self, forKey: .provider)
        accounts = try container.decodeLossyArrayIfPresent([Account].self, forKey: .accounts) ?? []
        consent = try? container.decodeIfPresent(Consent.self, forKey: .consent)
        deactivationReason = try container.decodeIfPresent(String.self, forKey: .deactivationReason)
    }

    /// Inactive, or its bank consent ran out: the person has to reconnect before syncing.
    public var needsReconnect: Bool {
        !isActive || consent?.isExpired == true
    }
}

/// `GET /bank-data-providers/connections/:id/available-accounts`: an account at the bank.
public struct BankAvailableAccount: Sendable, Hashable, Decodable, Identifiable {
    /// ISO 4217 "no currency": the provider didn't report one, so the person picks it.
    public static let noCurrencyCode = "XXX"

    public let externalId: String
    public let name: String
    public let type: String?
    public let balance: Decimal
    public let currency: String

    public var id: String { externalId }
    public var needsCurrencyChoice: Bool { currency == Self.noCurrencyCode }

    private enum CodingKeys: String, CodingKey {
        case externalId, name, type, balance, currency
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        externalId = try container.e1DecodeID(forKey: .externalId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type)
        balance = try container.decodeIfPresent(Decimal.self, forKey: .balance) ?? 0
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? Self.noCurrencyCode
    }
}

/// `POST /bank-data-providers/:type/connect`.
public struct BankConnectResult: Sendable, Hashable, Decodable {
    public let connectionId: String
    /// Set for consent-based providers (Enable Banking): open it to finish connecting.
    public let authUrl: String?
    public let message: String?

    private enum CodingKeys: String, CodingKey { case connectionId, authUrl, message }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connectionId = try container.e1DecodeID(forKey: .connectionId)
        authUrl = try container.decodeIfPresent(String.self, forKey: .authUrl)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

/// `POST /bank-data-providers/connections/:id/reauthorize`.
public struct BankReauthorizeResult: Sendable, Hashable, Decodable {
    public let authUrl: String?
    public let message: String?
}

/// A reply that carries only a server message.
public struct BankMessageResult: Sendable, Hashable, Decodable {
    public let message: String?
}

// MARK: - Enable Banking

/// One bank (ASPSP) from `POST /bank-data-providers/enablebanking/banks`.
public struct EnableBankingBank: Sendable, Hashable, Decodable, Identifiable {
    public let name: String
    public let country: String
    public let bic: String?
    public let logo: String?
    public let beta: Bool
    /// Seconds; passed back on connect as `maxConsentValidity`.
    public let maximumConsentValidity: Int?

    public var id: String { "\(country)-\(name)" }

    private enum CodingKeys: String, CodingKey {
        case name, country, bic, logo, beta
        case maximumConsentValidity = "maximum_consent_validity"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        bic = try container.decodeIfPresent(String.self, forKey: .bic)
        logo = try container.decodeIfPresent(String.self, forKey: .logo)
        beta = try container.decodeIfPresent(Bool.self, forKey: .beta) ?? false
        maximumConsentValidity = try? container.decodeIfPresent(Int.self, forKey: .maximumConsentValidity)
    }
}

/// What the bank consent redirect to `https://<server>/bank-callback` carried, read the way
/// the web callback page reads it.
public enum EnableBankingCallbackResult: Sendable, Equatable {
    case authorized(code: String, state: String)
    case denied(message: String?)
    case missingParameters

    public init(callbackURL: URL) {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let value = items.first(where: { $0.name == name })?.value, !value.isEmpty else { return nil }
            return value
        }
        if let error = value("error") {
            self = .denied(message: value("error_description") ?? error)
        } else if let code = value("code"), let state = value("state") {
            self = .authorized(code: code, state: state)
        } else {
            self = .missingParameters
        }
    }
}

// MARK: - Sync status

public enum BankSyncState: String, LenientEnum, CaseIterable {
    case idle
    case queued
    case syncing
    case completed
    case failed
    case unknown
}

/// `GET /bank-data-providers/sync/status`.
public struct BankSyncStatus: Sendable, Hashable, Decodable {
    public struct AccountStatus: Sendable, Hashable, Decodable, Identifiable {
        public let accountId: String
        public let accountName: String
        public let providerType: BankProviderType
        public let status: BankSyncState
        public let startedAt: Date?
        public let completedAt: Date?
        public let error: String?

        public var id: String { accountId }

        private enum CodingKeys: String, CodingKey {
            case accountId, accountName, providerType, status, startedAt, completedAt, error
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accountId = try container.e1DecodeID(forKey: .accountId)
            accountName = try container.decodeIfPresent(String.self, forKey: .accountName) ?? ""
            providerType = try container.decodeLenient(BankProviderType.self, forKey: .providerType, default: .unknown)
            status = try container.decodeLenient(BankSyncState.self, forKey: .status, default: .unknown)
            startedAt = container.e1DecodeDate(forKey: .startedAt)
            completedAt = container.e1DecodeDate(forKey: .completedAt)
            error = try container.decodeIfPresent(String.self, forKey: .error)
        }
    }

    public struct ConnectionNeedingReauth: Sendable, Hashable, Decodable, Identifiable {
        public let connectionId: String
        public let providerType: BankProviderType
        public let providerName: String
        public let bankName: String?
        public let accountsCount: Int

        public var id: String { connectionId }

        private enum CodingKeys: String, CodingKey {
            case connectionId, providerType, providerName, bankName, accountsCount
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            connectionId = try container.e1DecodeID(forKey: .connectionId)
            providerType = try container.decodeLenient(BankProviderType.self, forKey: .providerType, default: .unknown)
            providerName = try container.decodeIfPresent(String.self, forKey: .providerName) ?? ""
            bankName = try container.decodeIfPresent(String.self, forKey: .bankName)
            accountsCount = try container.decodeIfPresent(Int.self, forKey: .accountsCount) ?? 0
        }
    }

    public struct ConnectionStatus: Sendable, Hashable, Decodable, Identifiable {
        public let connectionId: String
        public let isActive: Bool
        public let consentExpired: Bool
        public let consentExpiringSoon: Bool
        public let daysRemaining: Int?

        public var id: String { connectionId }

        private enum CodingKeys: String, CodingKey {
            case connectionId, isActive, consentExpired, consentExpiringSoon, daysRemaining
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            connectionId = try container.e1DecodeID(forKey: .connectionId)
            isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
            consentExpired = try container.decodeIfPresent(Bool.self, forKey: .consentExpired) ?? false
            consentExpiringSoon = try container.decodeIfPresent(Bool.self, forKey: .consentExpiringSoon) ?? false
            daysRemaining = try container.decodeIfPresent(Int.self, forKey: .daysRemaining)
        }
    }

    public struct Summary: Sendable, Hashable, Decodable {
        public let total: Int
        public let syncing: Int
        public let queued: Int
        public let completed: Int
        public let failed: Int
        public let idle: Int

        public static let empty = Summary(total: 0, syncing: 0, queued: 0, completed: 0, failed: 0, idle: 0)

        public init(total: Int, syncing: Int, queued: Int, completed: Int, failed: Int, idle: Int) {
            self.total = total
            self.syncing = syncing
            self.queued = queued
            self.completed = completed
            self.failed = failed
            self.idle = idle
        }

        private enum CodingKeys: String, CodingKey { case total, syncing, queued, completed, failed, idle }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
            syncing = try container.decodeIfPresent(Int.self, forKey: .syncing) ?? 0
            queued = try container.decodeIfPresent(Int.self, forKey: .queued) ?? 0
            completed = try container.decodeIfPresent(Int.self, forKey: .completed) ?? 0
            failed = try container.decodeIfPresent(Int.self, forKey: .failed) ?? 0
            idle = try container.decodeIfPresent(Int.self, forKey: .idle) ?? 0
        }
    }

    /// Milliseconds since 1970 on the wire.
    public let lastSyncAt: Date?
    public let accounts: [AccountStatus]
    public let connectionsNeedingReauth: [ConnectionNeedingReauth]
    public let connectionStatuses: [ConnectionStatus]
    public let summary: Summary

    /// Some account is queued or syncing right now.
    public var isInProgress: Bool { summary.syncing + summary.queued > 0 }

    public func status(forAccountID id: String) -> AccountStatus? {
        accounts.first { $0.accountId == id }
    }

    public func connectionStatus(forConnectionID id: String) -> ConnectionStatus? {
        connectionStatuses.first { $0.connectionId == id }
    }

    private enum CodingKeys: String, CodingKey {
        case lastSyncAt, accounts, connectionsNeedingReauth, connectionStatuses, summary
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let millis = try? container.decodeIfPresent(Double.self, forKey: .lastSyncAt) {
            lastSyncAt = Date(timeIntervalSince1970: millis / 1000)
        } else {
            lastSyncAt = container.e1DecodeDate(forKey: .lastSyncAt)
        }
        accounts = try container.decodeLossyArrayIfPresent([AccountStatus].self, forKey: .accounts) ?? []
        connectionsNeedingReauth = try container.decodeLossyArrayIfPresent(
            [ConnectionNeedingReauth].self, forKey: .connectionsNeedingReauth
        ) ?? []
        connectionStatuses = try container.decodeLossyArrayIfPresent([ConnectionStatus].self, forKey: .connectionStatuses) ?? []
        summary = (try? container.decodeIfPresent(Summary.self, forKey: .summary)) ?? .empty
    }
}

/// `POST /bank-data-providers/sync/trigger`.
public struct BankSyncTriggerResult: Sendable, Hashable, Decodable {
    public let totalAccounts: Int?
    public let queuedAccounts: Int?
}

/// `GET /bank-data-providers/sync/check`: runs an auto-sync when the last one is old enough.
public struct BankSyncCheckResult: Sendable, Hashable, Decodable {
    public let syncTriggered: Bool
    public let message: String?
    public let totalAccounts: Int?
    public let queuedAccounts: Int?

    private enum CodingKeys: String, CodingKey { case syncTriggered, message, totalAccounts, queuedAccounts }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncTriggered = try container.decodeIfPresent(Bool.self, forKey: .syncTriggered) ?? false
        message = try container.decodeIfPresent(String.self, forKey: .message)
        totalAccounts = try container.decodeIfPresent(Int.self, forKey: .totalAccounts)
        queuedAccounts = try container.decodeIfPresent(Int.self, forKey: .queuedAccounts)
    }
}

// MARK: - Requests

/// One credential value: most are strings, Enable Banking also sends a number.
public enum BankCredentialValue: Sendable, Hashable, Encodable {
    case string(String)
    case int(Int)

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        }
    }
}

public typealias BankCredentials = [String: BankCredentialValue]

/// Credential payloads, keyed the way each provider's backend validator expects them.
public enum BankProviderCredentials {
    public static func monobank(token: String) -> BankCredentials {
        ["apiToken": .string(token)]
    }

    public static func lunchFlow(apiKey: String) -> BankCredentials {
        ["apiKey": .string(apiKey)]
    }

    public static func walutomat(apiKey: String, privateKey: String) -> BankCredentials {
        ["apiKey": .string(apiKey), "privateKey": .string(privateKey)]
    }

    public static func simpleFIN(setupToken: String) -> BankCredentials {
        ["setupToken": .string(setupToken)]
    }

    public static func enableBanking(appId: String, privateKey: String, bank: EnableBankingBank) -> BankCredentials {
        var credentials: BankCredentials = [
            "appId": .string(appId),
            "privateKey": .string(privateKey),
            "bankName": .string(bank.name),
            "bankCountry": .string(bank.country),
        ]
        if let validity = bank.maximumConsentValidity {
            credentials["maxConsentValidity"] = .int(validity)
        }
        return credentials
    }

    /// The "Update credentials" reconnect payload: one key (plus Walutomat's private key),
    /// re-keyed per provider.
    public static func reconnect(providerType: BankProviderType, apiKey: String, privateKey: String? = nil) -> BankCredentials {
        switch providerType {
        case .monobank: monobank(token: apiKey)
        case .simplefin: simpleFIN(setupToken: apiKey)
        case .walutomat: walutomat(apiKey: apiKey, privateKey: privateKey ?? "")
        default: lunchFlow(apiKey: apiKey)
        }
    }
}

public struct BankConnectRequest: Sendable, Hashable, Encodable {
    public let credentials: BankCredentials
    public let providerName: String?

    public init(credentials: BankCredentials, providerName: String? = nil) {
        self.credentials = credentials
        self.providerName = providerName
    }
}

public struct BankConnectionUpdateRequest: Sendable, Hashable, Encodable {
    public let providerName: String?
    public let credentials: BankCredentials?

    public init(providerName: String? = nil, credentials: BankCredentials? = nil) {
        self.providerName = providerName
        self.credentials = credentials
    }
}

public struct BankSyncSelectedAccountsRequest: Sendable, Hashable, Encodable {
    public let accountExternalIds: [String]
    /// externalId → currency, for accounts listed with `XXX`.
    public let currencyOverrides: [String: String]?

    public init(accountExternalIds: [String], currencyOverrides: [String: String]? = nil) {
        self.accountExternalIds = accountExternalIds
        self.currencyOverrides = (currencyOverrides?.isEmpty ?? true) ? nil : currencyOverrides
    }
}

public struct EnableBankingCredentialsRequest: Sendable, Hashable, Encodable {
    public let appId: String
    public let privateKey: String

    public init(appId: String, privateKey: String) {
        self.appId = appId
        self.privateKey = privateKey
    }
}

public struct EnableBankingOAuthCallbackRequest: Sendable, Hashable, Encodable {
    public let connectionId: String
    public let code: String
    public let state: String

    public init(connectionId: String, code: String, state: String) {
        self.connectionId = connectionId
        self.code = code
        self.state = state
    }
}

// MARK: - Decoding helpers

extension KeyedDecodingContainer {
    /// A string id that some routes send as a number.
    func e1DecodeID(forKey key: Key) throws -> String {
        if let string = try? decode(String.self, forKey: key) { return string }
        if let number = try? decode(Int.self, forKey: key) { return String(number) }
        return try decode(String.self, forKey: key)
    }

    func e1DecodeIDIfPresent(forKey key: Key) -> String? {
        if let string = try? decodeIfPresent(String.self, forKey: key) { return string }
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return String(number) }
        return nil
    }

    /// A timestamp that's `nil` when missing, null, or unparseable.
    func e1DecodeDate(forKey key: Key) -> Date? {
        guard let string = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return APIDateFormat.parseTimestamp(string)
    }
}
