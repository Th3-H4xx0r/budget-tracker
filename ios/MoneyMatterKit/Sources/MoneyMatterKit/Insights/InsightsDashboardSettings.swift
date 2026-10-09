import Foundation

// MARK: - Config values

/// Any JSON value. A widget's `config` is an open object on the server, so keys this app
/// doesn't know (spike thresholds, web-only toggles) must survive a save untouched.
public enum DashboardConfigValue: Sendable, Hashable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([DashboardConfigValue])
    case object([String: DashboardConfigValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([DashboardConfigValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: DashboardConfigValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// The strings of an array value; non-string elements are skipped.
    public var stringArray: [String]? {
        guard case .array(let values) = self else { return nil }
        return values.compactMap { value in
            if case .string(let string) = value { return string }
            return nil
        }
    }
}

// MARK: - Widgets

/// The widgets the web dashboard registry knows (`components/widgets/widget-registry.ts`).
public enum DashboardWidgetKind: String, Sendable, CaseIterable, Identifiable {
    case balanceTrend = "balance-trend"
    case spendingCategories = "spending-categories"
    case latestRecords = "latest-records"
    case categorySpendingTracker = "category-spending-tracker"
    case cashFlow = "cash-flow"
    case netWorth = "net-worth"
    case creditUtilization = "credit-utilization"
    case plannedOverview = "planned-overview"
    case subscriptionsOverview = "subscriptions-overview"

    public var id: String { rawValue }

    public var defaultColSpan: Int {
        switch self {
        case .balanceTrend, .spendingCategories: 2
        default: 1
        }
    }

    public var defaultRowSpan: Int { 1 }

    /// Whether the widget follows the dashboard's month selector.
    public var needsPeriod: Bool {
        switch self {
        case .balanceTrend, .spendingCategories, .categorySpendingTracker, .cashFlow, .netWorth: true
        case .latestRecords, .creditUtilization, .plannedOverview, .subscriptionsOverview: false
        }
    }
}

/// One entry of `dashboard.widgets` in user settings. `colSpan`/`rowSpan` size the widget on
/// the web grid; the app keeps them so a save from the phone doesn't reshape the web layout.
public struct DashboardWidgetConfig: Sendable, Hashable, Codable, Identifiable {
    public var widgetId: String
    public var colSpan: Int
    public var rowSpan: Int?
    public var config: [String: DashboardConfigValue]?

    public var id: String { widgetId }
    public var kind: DashboardWidgetKind? { DashboardWidgetKind(rawValue: widgetId) }

    public init(widgetId: String, colSpan: Int, rowSpan: Int? = nil, config: [String: DashboardConfigValue]? = nil) {
        self.widgetId = widgetId
        self.colSpan = colSpan
        self.rowSpan = rowSpan
        self.config = config
    }

    /// A newly added widget at its registry default size.
    public init(kind: DashboardWidgetKind) {
        self.init(widgetId: kind.rawValue, colSpan: kind.defaultColSpan, rowSpan: kind.defaultRowSpan)
    }

    private enum CodingKeys: String, CodingKey {
        case widgetId, colSpan, rowSpan, config
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widgetId = try container.decode(String.self, forKey: .widgetId)
        colSpan = (try? container.decodeIfPresent(Int.self, forKey: .colSpan)) ?? 1
        rowSpan = try? container.decodeIfPresent(Int.self, forKey: .rowSpan)
        config = try? container.decodeIfPresent([String: DashboardConfigValue].self, forKey: .config)
    }

    /// Pending planned transactions count unless the widget opted out; a missing key is `true`.
    public var includePlanned: Bool {
        config?["includePlanned"] != .bool(false)
    }

    /// The category spending tracker's picked categories, in display order.
    public var selectedCategoryIds: [String] {
        config?["selectedCategoryIds"]?.stringArray ?? []
    }

    /// Shallow-merges `values` over the existing config, like the web's `saveWidgetConfigDirect`.
    public func mergingConfig(_ values: [String: DashboardConfigValue]) -> DashboardWidgetConfig {
        var copy = self
        copy.config = (config ?? [:]).merging(values) { _, new in new }
        return copy
    }
}

public enum DashboardLayout {
    /// The web's `DEFAULT_DASHBOARD_LAYOUT`, used while the user has never saved a layout.
    public static let defaultWidgets: [DashboardWidgetConfig] = [
        DashboardWidgetConfig(widgetId: DashboardWidgetKind.balanceTrend.rawValue, colSpan: 2),
        DashboardWidgetConfig(widgetId: DashboardWidgetKind.latestRecords.rawValue, colSpan: 1, rowSpan: 2),
        DashboardWidgetConfig(widgetId: DashboardWidgetKind.subscriptionsOverview.rawValue, colSpan: 1),
        DashboardWidgetConfig(widgetId: DashboardWidgetKind.spendingCategories.rawValue, colSpan: 1),
    ]

    /// The widgets to show: the saved list when it has entries, else the default layout. Unknown
    /// ids and repeats are dropped, as the web dashboard does.
    public static func resolve(saved: [DashboardWidgetConfig]?) -> [DashboardWidgetConfig] {
        let layout = (saved?.isEmpty == false ? saved : nil) ?? defaultWidgets
        var seen = Set<String>()
        return layout.filter { widget in
            widget.kind != nil && seen.insert(widget.widgetId).inserted
        }
    }

    /// Registry widgets that aren't in `widgets`, in registry order.
    public static func hiddenKinds(in widgets: [DashboardWidgetConfig]) -> [DashboardWidgetKind] {
        let shown = Set(widgets.map(\.widgetId))
        return DashboardWidgetKind.allCases.filter { !shown.contains($0.rawValue) }
    }
}

// MARK: - Settings slice

/// The dashboard-related slice of `GET /user/settings`; other keys are ignored.
public struct DashboardUserSettings: Sendable, Hashable, Decodable {
    /// `nil` when the user never saved a layout.
    public let widgets: [DashboardWidgetConfig]?
    /// Whether a manual credit account's balance already includes its credit limit.
    public let includeCreditLimitInStats: Bool

    public init(widgets: [DashboardWidgetConfig]?, includeCreditLimitInStats: Bool = false) {
        self.widgets = widgets
        self.includeCreditLimitInStats = includeCreditLimitInStats
    }

    private enum CodingKeys: String, CodingKey {
        case dashboard, includeCreditLimitInStats
    }

    private struct Dashboard: Decodable {
        let widgets: [DashboardWidgetConfig]?

        private enum CodingKeys: String, CodingKey {
            case widgets
        }

        /// Skips malformed entries instead of failing the whole layout.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard var list = try? container.nestedUnkeyedContainer(forKey: .widgets) else {
                widgets = nil
                return
            }
            var items: [DashboardWidgetConfig] = []
            while !list.isAtEnd {
                if let item = try? list.decode(DashboardWidgetConfig.self) {
                    items.append(item)
                } else {
                    _ = try? list.decode(DashboardConfigValue.self)
                }
            }
            widgets = items
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widgets = (try? container.decodeIfPresent(Dashboard.self, forKey: .dashboard))?.widgets
        includeCreditLimitInStats = (try? container.decodeIfPresent(Bool.self, forKey: .includeCreditLimitInStats)) ?? false
    }
}

/// `PATCH /user/settings` body that replaces the widget list. The server deep-merges objects
/// but replaces arrays wholesale, so the list is always the full desired layout.
struct DashboardSettingsPatch: Encodable, Sendable {
    struct Dashboard: Encodable, Sendable {
        let widgets: [DashboardWidgetConfig]
    }

    let dashboard: Dashboard
}

// MARK: - Planned summary

/// One account's pending planned transactions from `GET /transactions/planned-summary`.
public struct DashboardPlannedSummaryEntry: Sendable, Hashable, Decodable {
    public let accountId: String
    public let currencyCode: String
    public let plannedDelta: Decimal
    /// Income minus expenses, in the base currency.
    public let refPlannedDelta: Decimal
    public let count: Int
    /// The furthest-out plan on the account.
    public let latestTime: Date?

    public init(
        accountId: String,
        currencyCode: String = "",
        plannedDelta: Decimal = 0,
        refPlannedDelta: Decimal,
        count: Int,
        latestTime: Date?
    ) {
        self.accountId = accountId
        self.currencyCode = currencyCode
        self.plannedDelta = plannedDelta
        self.refPlannedDelta = refPlannedDelta
        self.count = count
        self.latestTime = latestTime
    }

    private enum CodingKeys: String, CodingKey {
        case accountId, currencyCode, plannedDelta, refPlannedDelta, count, latestTime
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try container.decode(String.self, forKey: .accountId)
        currencyCode = (try? container.decodeIfPresent(String.self, forKey: .currencyCode)) ?? ""
        plannedDelta = (try? container.decodeIfPresent(Decimal.self, forKey: .plannedDelta)) ?? 0
        refPlannedDelta = (try? container.decodeIfPresent(Decimal.self, forKey: .refPlannedDelta)) ?? 0
        count = (try? container.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        latestTime = try? container.decodeIfPresent(Date.self, forKey: .latestTime)
    }
}

/// The planned summary summed over a set of accounts (the web's `aggregatePlannedSummary`).
public struct DashboardPlannedAggregate: Sendable, Hashable {
    public let refPlannedDelta: Decimal
    public let count: Int
    public let latestTime: Date?

    public init(entries: [DashboardPlannedSummaryEntry], accountIDs: some Sequence<String>) {
        let scope = Set(accountIDs)
        var delta = Decimal.zero
        var count = 0
        var latest: Date?
        for entry in entries where scope.contains(entry.accountId) {
            delta += entry.refPlannedDelta
            count += entry.count
            if let time = entry.latestTime, latest.map({ time > $0 }) ?? true {
                latest = time
            }
        }
        refPlannedDelta = delta
        self.count = count
        latestTime = latest
    }

    /// The accounts a projected total covers: not archived, and not loans or vehicles, whose
    /// balances are derived.
    public static func projectedAccounts(_ accounts: [Account]) -> [Account] {
        accounts.filter { account in
            account.status != .archived && account.accountCategory != .loan && account.accountCategory != .vehicle
        }
    }
}

// MARK: - Credit utilization

public enum DashboardCreditMath {
    public static let mediumThreshold = 40
    public static let highThreshold = 70

    /// The used part of a credit line, never negative. A balance that includes the limit means
    /// "available" credit; otherwise a negative balance is the debt.
    public static func creditUsed(balance: Decimal, creditLimit: Decimal, balanceIncludesCreditLimit: Bool) -> Decimal {
        max(balanceIncludesCreditLimit ? creditLimit - balance : -balance, 0)
    }

    /// Whole-percent utilization, capped at 100.
    public static func utilization(used: Decimal, limit: Decimal) -> Int {
        guard limit > 0 else { return 0 }
        var ratio = used / limit * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &ratio, 0, .plain)
        return min(NSDecimalNumber(decimal: rounded).intValue, 100)
    }
}

/// One credit account on the credit utilization widget.
public struct DashboardCreditLine: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let currencyCode: String
    public let used: Decimal
    public let limit: Decimal
    public let utilization: Int
    /// `used` and `limit` in the base currency, for the total.
    public let refUsed: Decimal
    public let refLimit: Decimal

    public init(
        id: String,
        name: String,
        currencyCode: String,
        used: Decimal,
        limit: Decimal,
        utilization: Int,
        refUsed: Decimal,
        refLimit: Decimal
    ) {
        self.id = id
        self.name = name
        self.currencyCode = currencyCode
        self.used = used
        self.limit = limit
        self.utilization = utilization
        self.refUsed = refUsed
        self.refLimit = refLimit
    }

    /// Active, counted accounts with a credit limit, highest utilization first. Bank-synced
    /// balances always include the limit; a manual one does when the user opted in.
    public static func lines(accounts: [Account], includeCreditLimitInStats: Bool) -> [DashboardCreditLine] {
        accounts
            .filter { $0.status == .active && !$0.excludeFromStats && $0.creditLimit > 0 }
            .map { account in
                let includesLimit = account.type != .system || includeCreditLimitInStats
                let used = DashboardCreditMath.creditUsed(
                    balance: account.currentBalance,
                    creditLimit: account.creditLimit,
                    balanceIncludesCreditLimit: includesLimit
                )
                return DashboardCreditLine(
                    id: account.id,
                    name: account.name,
                    currencyCode: account.currencyCode,
                    used: used,
                    limit: account.creditLimit,
                    utilization: DashboardCreditMath.utilization(used: used, limit: account.creditLimit),
                    refUsed: DashboardCreditMath.creditUsed(
                        balance: account.refCurrentBalance,
                        creditLimit: account.refCreditLimit,
                        balanceIncludesCreditLimit: includesLimit
                    ),
                    refLimit: account.refCreditLimit
                )
            }
            .sorted { $0.utilization > $1.utilization }
    }
}

// MARK: - Endpoints

extension Endpoints {
    /// `GET /user/settings`, decoding only the dashboard slice.
    public static func dashboardSettings() -> Endpoint<DashboardUserSettings> {
        Endpoint(.get, "/user/settings")
    }

    /// `PATCH /user/settings` with the full widget list; returns the merged settings.
    public static func saveDashboardWidgets(_ widgets: [DashboardWidgetConfig]) -> Endpoint<DashboardUserSettings> {
        Endpoint(.patch, "/user/settings", body: DashboardSettingsPatch(dashboard: .init(widgets: widgets)))
    }

    /// `GET /transactions/planned-summary`: pending planned transactions per account.
    public static func dashboardPlannedSummary() -> Endpoint<[DashboardPlannedSummaryEntry]> {
        Endpoint(.get, "/transactions/planned-summary")
    }
}
