import Foundation

/// The app languages the server supports (`SUPPORTED_LOCALES`).
public enum SettingsLocale: Sendable, Hashable, CaseIterable {
    case english, ukrainian, spanish, indonesian, russian

    public init?(code: String) {
        guard let match = Self.allCases.first(where: { $0.code == code }) else { return nil }
        self = match
    }

    public var code: String {
        switch self {
        case .english: "en"
        case .ukrainian: "uk"
        case .spanish: "es"
        case .indonesian: "id"
        case .russian: "ru"
        }
    }

    /// The language's own name, shown untranslated.
    public var nativeName: String {
        switch self {
        case .english: "English"
        case .ukrainian: "Українська"
        case .spanish: "Español"
        case .indonesian: "Bahasa"
        case .russian: "Русский"
        }
    }

    /// Translated by the community rather than the maintainers.
    public var isCommunityTranslated: Bool {
        switch self {
        case .spanish, .indonesian, .russian: true
        case .english, .ukrainian: false
        }
    }
}

/// How fiat amounts render their currency: `symbol` disambiguates (CA$, A$), `narrowSymbol`
/// is what locals use but collapses every dollar to `$`.
public enum SettingsCurrencyDisplay: String, Sendable, Hashable, Codable, CaseIterable {
    case symbol
    case narrowSymbol
}

/// Optional transaction form fields the user can turn on (`TRANSACTION_OPTIONAL_FIELDS`).
public enum SettingsTransactionOptionalField: String, Sendable, Hashable, Codable, CaseIterable {
    case externalUrl
    case externalReference
    case location
    case originalAmount
}

/// Which asset sections the account list shows.
public struct SettingsSidebarSections: Sendable, Hashable, Codable {
    public var portfolios: Bool
    public var ventures: Bool
    public var vehicles: Bool
    public var loans: Bool

    public init(portfolios: Bool = true, ventures: Bool = true, vehicles: Bool = true, loans: Bool = true) {
        self.portfolios = portfolios
        self.ventures = ventures
        self.vehicles = vehicles
        self.loans = loans
    }

    private enum CodingKeys: String, CodingKey { case portfolios, ventures, vehicles, loans }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        portfolios = (try? container.decodeIfPresent(Bool.self, forKey: .portfolios)) ?? true
        ventures = (try? container.decodeIfPresent(Bool.self, forKey: .ventures)) ?? true
        vehicles = (try? container.decodeIfPresent(Bool.self, forKey: .vehicles)) ?? true
        loans = (try? container.decodeIfPresent(Bool.self, forKey: .loans)) ?? true
    }
}

/// `GET /user/settings`: the preference slices the app settings screens edit. Missing keys
/// take the web defaults.
public struct SettingsUserPreferences: Sendable, Hashable, Decodable {
    public var localeCode: String?
    public var includeCreditLimitInStats: Bool
    public var matchTransfersWithManualAccounts: Bool
    public var savingsCategoryIds: [String]
    public var hideZeroBalances: Bool
    public var currencyDisplay: SettingsCurrencyDisplay
    public var sidebarSections: SettingsSidebarSections
    public var defaultAccountId: String?
    public var showArchivedInDropdowns: Bool
    public var hideUpcomingTransactions: Bool
    public var optionalTransactionFields: [SettingsTransactionOptionalField]
    public var mapPicker: Bool

    public var locale: SettingsLocale? { localeCode.flatMap(SettingsLocale.init(code:)) }

    public init(
        localeCode: String? = nil,
        includeCreditLimitInStats: Bool = false,
        matchTransfersWithManualAccounts: Bool = false,
        savingsCategoryIds: [String] = [],
        hideZeroBalances: Bool = false,
        currencyDisplay: SettingsCurrencyDisplay = .symbol,
        sidebarSections: SettingsSidebarSections = SettingsSidebarSections(),
        defaultAccountId: String? = nil,
        showArchivedInDropdowns: Bool = false,
        hideUpcomingTransactions: Bool = false,
        optionalTransactionFields: [SettingsTransactionOptionalField] = [],
        mapPicker: Bool = false
    ) {
        self.localeCode = localeCode
        self.includeCreditLimitInStats = includeCreditLimitInStats
        self.matchTransfersWithManualAccounts = matchTransfersWithManualAccounts
        self.savingsCategoryIds = savingsCategoryIds
        self.hideZeroBalances = hideZeroBalances
        self.currencyDisplay = currencyDisplay
        self.sidebarSections = sidebarSections
        self.defaultAccountId = defaultAccountId
        self.showArchivedInDropdowns = showArchivedInDropdowns
        self.hideUpcomingTransactions = hideUpcomingTransactions
        self.optionalTransactionFields = optionalTransactionFields
        self.mapPicker = mapPicker
    }

    private enum CodingKeys: String, CodingKey {
        case locale, includeCreditLimitInStats, matchTransfersWithManualAccounts, savingsCategoryIds
        case hideZeroBalances, currencyDisplay, sidebarSections, accounts, ui
    }

    private struct Accounts: Decodable {
        let defaultAccountId: String?
        let showArchivedInDropdowns: Bool?
    }

    private struct UI: Decodable {
        struct TransactionsList: Decodable { let hideUpcoming: Bool? }
        struct TransactionForm: Decodable {
            let optionalFields: [String]?
            let mapPicker: Bool?
        }

        let transactionsList: TransactionsList?
        let transactionForm: TransactionForm?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localeCode = try? container.decodeIfPresent(String.self, forKey: .locale)
        includeCreditLimitInStats = (try? container.decodeIfPresent(Bool.self, forKey: .includeCreditLimitInStats)) ?? false
        matchTransfersWithManualAccounts = (try? container.decodeIfPresent(Bool.self, forKey: .matchTransfersWithManualAccounts)) ?? false
        savingsCategoryIds = (try? container.decodeIfPresent([String].self, forKey: .savingsCategoryIds)) ?? []
        hideZeroBalances = (try? container.decodeIfPresent(Bool.self, forKey: .hideZeroBalances)) ?? false
        let display = try? container.decodeIfPresent(String.self, forKey: .currencyDisplay)
        currencyDisplay = display.flatMap(SettingsCurrencyDisplay.init(rawValue:)) ?? .symbol
        sidebarSections = (try? container.decodeIfPresent(SettingsSidebarSections.self, forKey: .sidebarSections))
            ?? SettingsSidebarSections()
        let accounts = try? container.decodeIfPresent(Accounts.self, forKey: .accounts)
        defaultAccountId = accounts?.defaultAccountId
        showArchivedInDropdowns = accounts?.showArchivedInDropdowns ?? false
        let ui = try? container.decodeIfPresent(UI.self, forKey: .ui)
        hideUpcomingTransactions = ui?.transactionsList?.hideUpcoming ?? false
        optionalTransactionFields = (ui?.transactionForm?.optionalFields ?? [])
            .compactMap(SettingsTransactionOptionalField.init(rawValue:))
        mapPicker = ui?.transactionForm?.mapPicker ?? false
    }
}

/// `PATCH /user/settings` body. Only set keys are sent; the server deep-merges them, so a
/// slice update never overwrites concurrent changes to other slices. Arrays replace wholesale.
public struct SettingsPreferencesPatch: Encodable, Sendable, Hashable {
    public var localeCode: String?
    public var includeCreditLimitInStats: Bool?
    public var matchTransfersWithManualAccounts: Bool?
    public var savingsCategoryIds: [String]?
    public var hideZeroBalances: Bool?
    public var currencyDisplay: SettingsCurrencyDisplay?
    public var sidebarSections: SettingsSidebarSections?
    /// `.clear` sends `null`, which removes the default account.
    public var defaultAccountId: FieldUpdate<String>
    public var showArchivedInDropdowns: Bool?
    public var hideUpcomingTransactions: Bool?
    public var optionalTransactionFields: [SettingsTransactionOptionalField]?
    public var mapPicker: Bool?

    public init(
        localeCode: String? = nil,
        includeCreditLimitInStats: Bool? = nil,
        matchTransfersWithManualAccounts: Bool? = nil,
        savingsCategoryIds: [String]? = nil,
        hideZeroBalances: Bool? = nil,
        currencyDisplay: SettingsCurrencyDisplay? = nil,
        sidebarSections: SettingsSidebarSections? = nil,
        defaultAccountId: FieldUpdate<String> = .unchanged,
        showArchivedInDropdowns: Bool? = nil,
        hideUpcomingTransactions: Bool? = nil,
        optionalTransactionFields: [SettingsTransactionOptionalField]? = nil,
        mapPicker: Bool? = nil
    ) {
        self.localeCode = localeCode
        self.includeCreditLimitInStats = includeCreditLimitInStats
        self.matchTransfersWithManualAccounts = matchTransfersWithManualAccounts
        self.savingsCategoryIds = savingsCategoryIds
        self.hideZeroBalances = hideZeroBalances
        self.currencyDisplay = currencyDisplay
        self.sidebarSections = sidebarSections
        self.defaultAccountId = defaultAccountId
        self.showArchivedInDropdowns = showArchivedInDropdowns
        self.hideUpcomingTransactions = hideUpcomingTransactions
        self.optionalTransactionFields = optionalTransactionFields
        self.mapPicker = mapPicker
    }

    private enum CodingKeys: String, CodingKey {
        case locale, includeCreditLimitInStats, matchTransfersWithManualAccounts, savingsCategoryIds
        case hideZeroBalances, currencyDisplay, sidebarSections, accounts, ui
    }

    private enum AccountsKeys: String, CodingKey { case defaultAccountId, showArchivedInDropdowns }
    private enum UIKeys: String, CodingKey { case transactionsList, transactionForm }
    private enum TransactionsListKeys: String, CodingKey { case hideUpcoming }
    private enum TransactionFormKeys: String, CodingKey { case optionalFields, mapPicker }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(localeCode, forKey: .locale)
        try container.encodeIfPresent(includeCreditLimitInStats, forKey: .includeCreditLimitInStats)
        try container.encodeIfPresent(matchTransfersWithManualAccounts, forKey: .matchTransfersWithManualAccounts)
        try container.encodeIfPresent(savingsCategoryIds, forKey: .savingsCategoryIds)
        try container.encodeIfPresent(hideZeroBalances, forKey: .hideZeroBalances)
        try container.encodeIfPresent(currencyDisplay, forKey: .currencyDisplay)
        try container.encodeIfPresent(sidebarSections, forKey: .sidebarSections)

        if defaultAccountId != .unchanged || showArchivedInDropdowns != nil {
            var accounts = container.nestedContainer(keyedBy: AccountsKeys.self, forKey: .accounts)
            switch defaultAccountId {
            case .unchanged: break
            case .clear: try accounts.encodeNil(forKey: .defaultAccountId)
            case .set(let id): try accounts.encode(id, forKey: .defaultAccountId)
            }
            try accounts.encodeIfPresent(showArchivedInDropdowns, forKey: .showArchivedInDropdowns)
        }

        if hideUpcomingTransactions != nil || optionalTransactionFields != nil || mapPicker != nil {
            var ui = container.nestedContainer(keyedBy: UIKeys.self, forKey: .ui)
            if let hideUpcomingTransactions {
                var list = ui.nestedContainer(keyedBy: TransactionsListKeys.self, forKey: .transactionsList)
                try list.encode(hideUpcomingTransactions, forKey: .hideUpcoming)
            }
            if optionalTransactionFields != nil || mapPicker != nil {
                var form = ui.nestedContainer(keyedBy: TransactionFormKeys.self, forKey: .transactionForm)
                try form.encodeIfPresent(optionalTransactionFields, forKey: .optionalFields)
                try form.encodeIfPresent(mapPicker, forKey: .mapPicker)
            }
        }
    }
}

extension Endpoints {
    /// `GET /user/settings`.
    public static func settingsPreferences() -> Endpoint<SettingsUserPreferences> {
        Endpoint(.get, "/user/settings")
    }

    /// `PATCH /user/settings`: returns the merged settings.
    public static func updateSettingsPreferences(_ patch: SettingsPreferencesPatch) -> Endpoint<SettingsUserPreferences> {
        Endpoint(.patch, "/user/settings", body: patch)
    }
}
