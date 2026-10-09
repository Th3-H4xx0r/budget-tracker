import Foundation

/// The pivot's column (time bucket) size.
public enum InsightsPivotGranularity: String, LenientEnum, CaseIterable {
    case yearly
    case quarterly
    case monthly
    case weekly
    case unknown

    public static var allCases: [InsightsPivotGranularity] { [.yearly, .quarterly, .monthly, .weekly] }
}

/// What each pivot row groups by.
public enum InsightsPivotRowDimension: String, LenientEnum, CaseIterable {
    case category
    case subcategory
    case payee
    case tag
    case unknown

    public static var allCases: [InsightsPivotRowDimension] { [.category, .subcategory, .payee, .tag] }
}

public enum InsightsPivotMeasure: String, LenientEnum, CaseIterable {
    case expense
    case income
    case unknown

    public static var allCases: [InsightsPivotMeasure] { [.expense, .income] }
}

/// One time bucket, i.e. one column of `GET /stats/pivot`.
public struct InsightsPivotColumn: Sendable, Hashable, Identifiable, Decodable {
    /// `2025`, `2025-Q1`, `2025-03`, or the week's Monday.
    public let key: String
    public let periodStart: CalendarDate
    public let periodEnd: CalendarDate
    /// The server's English label; the app formats its own from `periodStart`.
    public let label: String

    public var id: String { key }

    public init(key: String, periodStart: CalendarDate, periodEnd: CalendarDate, label: String) {
        self.key = key
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.label = label
    }
}

/// One row of `GET /stats/pivot`. Amounts are decimals in the base currency.
public struct InsightsPivotRow: Sendable, Hashable, Identifiable, Decodable {
    public enum Kind: String, LenientEnum {
        case flat
        case parent
        case child
        case unknown
    }

    /// A category, payee, or tag id, or `uncategorized` / `unassigned` / `untagged`.
    public let id: String
    public let label: String
    public let color: String?
    public let parentId: String?
    public let kind: Kind
    /// Column key to amount.
    public let values: [String: Decimal]
    public let total: Decimal

    public init(
        id: String,
        label: String,
        color: String? = nil,
        parentId: String? = nil,
        kind: Kind = .flat,
        values: [String: Decimal],
        total: Decimal
    ) {
        self.id = id
        self.label = label
        self.color = color
        self.parentId = parentId
        self.kind = kind
        self.values = values
        self.total = total
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, color, parentId, kind, values, total
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? ""
        color = try? container.decodeIfPresent(String.self, forKey: .color)
        parentId = try? container.decodeIfPresent(String.self, forKey: .parentId)
        kind = try container.decodeLenient(Kind.self, forKey: .kind, default: .flat)
        values = (try? container.decodeIfPresent([String: Decimal].self, forKey: .values)) ?? [:]
        total = (try? container.decodeIfPresent(Decimal.self, forKey: .total)) ?? 0
    }

    public func value(for column: InsightsPivotColumn) -> Decimal {
        values[column.key] ?? 0
    }
}

/// `GET /stats/pivot`: a cross-tab of a row dimension against time buckets.
public struct InsightsPivotReport: Sendable, Hashable, Decodable {
    public let columns: [InsightsPivotColumn]
    public let rows: [InsightsPivotRow]
    public let columnTotals: [String: Decimal]
    public let grandTotal: Decimal
    public let currencyCode: String

    public init(
        columns: [InsightsPivotColumn],
        rows: [InsightsPivotRow],
        columnTotals: [String: Decimal],
        grandTotal: Decimal,
        currencyCode: String
    ) {
        self.columns = columns
        self.rows = rows
        self.columnTotals = columnTotals
        self.grandTotal = grandTotal
        self.currencyCode = currencyCode
    }

    private enum CodingKeys: String, CodingKey {
        case columns, rows, columnTotals, grandTotal, currencyCode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columns = try container.decodeIfPresent([InsightsPivotColumn].self, forKey: .columns) ?? []
        rows = try container.decodeIfPresent([InsightsPivotRow].self, forKey: .rows) ?? []
        columnTotals = (try? container.decodeIfPresent([String: Decimal].self, forKey: .columnTotals)) ?? [:]
        grandTotal = (try? container.decodeIfPresent(Decimal.self, forKey: .grandTotal)) ?? 0
        currencyCode = (try? container.decodeIfPresent(String.self, forKey: .currencyCode)) ?? ""
    }

    /// True when no row has any amount.
    public var isEmpty: Bool { rows.allSatisfy { $0.total == 0 } }

    /// Top-level rows (flat and parent rows) sorted by total, largest first, each followed by its
    /// children when `expanded` contains its id.
    public func visibleRows(expanded: Set<String>) -> [InsightsPivotRow] {
        let children = Dictionary(grouping: rows.filter { $0.parentId != nil }, by: { $0.parentId ?? "" })
        let top = rows.filter { $0.parentId == nil }.sorted { abs($0.total) > abs($1.total) }
        return top.flatMap { row -> [InsightsPivotRow] in
            guard expanded.contains(row.id), let kids = children[row.id] else { return [row] }
            return [row] + kids.sorted { abs($0.total) > abs($1.total) }
        }
    }

    public func columnTotal(for column: InsightsPivotColumn) -> Decimal {
        columnTotals[column.key] ?? 0
    }
}

// MARK: - Saved views

/// The configuration a saved pivot view pins (`savedPivotViews[].config` in user settings).
public struct InsightsSavedPivotViewConfig: Sendable, Hashable, Codable {
    public var rowDimension: InsightsPivotRowDimension
    public var granularity: InsightsPivotGranularity
    public var measure: InsightsPivotMeasure
    public var from: CalendarDate
    public var to: CalendarDate
    public var accountIds: [String]?
    public var categoryIds: [String]?
    public var payeeIds: [String]?
    public var heatmap: Bool
    public var showDelta: Bool

    public init(
        rowDimension: InsightsPivotRowDimension,
        granularity: InsightsPivotGranularity,
        measure: InsightsPivotMeasure,
        from: CalendarDate,
        to: CalendarDate,
        accountIds: [String]? = nil,
        categoryIds: [String]? = nil,
        payeeIds: [String]? = nil,
        heatmap: Bool = false,
        showDelta: Bool = false
    ) {
        self.rowDimension = rowDimension
        self.granularity = granularity
        self.measure = measure
        self.from = from
        self.to = to
        self.accountIds = accountIds
        self.categoryIds = categoryIds
        self.payeeIds = payeeIds
        self.heatmap = heatmap
        self.showDelta = showDelta
    }
}

public struct InsightsSavedPivotView: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public var name: String
    public var config: InsightsSavedPivotViewConfig

    public init(id: String = UUID().uuidString.lowercased(), name: String, config: InsightsSavedPivotViewConfig) {
        self.id = id
        self.name = name
        self.config = config
    }
}

/// The saved-views slice of `GET /user/settings`. Views that fail to decode are skipped.
public struct InsightsSavedPivotViews: Sendable, Hashable, Decodable {
    public let views: [InsightsSavedPivotView]

    private enum CodingKeys: String, CodingKey {
        case savedPivotViews
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var items: [InsightsSavedPivotView] = []
        if var list = try? container.nestedUnkeyedContainer(forKey: .savedPivotViews) {
            while !list.isAtEnd {
                if let view = try? list.decode(InsightsSavedPivotView.self) {
                    items.append(view)
                } else {
                    _ = try? list.decode(DashboardConfigValue.self)
                }
            }
        }
        views = items
    }
}

/// `PATCH /user/settings` body replacing the saved views; arrays are replaced wholesale.
struct InsightsSavedPivotViewsPatch: Encodable, Sendable {
    let savedPivotViews: [InsightsSavedPivotView]
}

extension Endpoints {
    /// `GET /stats/pivot`. Empty filter lists are not sent.
    public static func pivotReport(
        from: CalendarDate,
        to: CalendarDate,
        granularity: InsightsPivotGranularity,
        rowDimension: InsightsPivotRowDimension,
        measure: InsightsPivotMeasure,
        accountIds: [String] = [],
        categoryIds: [String] = [],
        payeeIds: [String] = []
    ) -> Endpoint<InsightsPivotReport> {
        var query = QueryBuilder()
        query.add("from", day: from)
        query.add("to", day: to)
        query.add("granularity", granularity == .unknown ? InsightsPivotGranularity.monthly.rawValue : granularity.rawValue)
        query.add("rowDimension", rowDimension == .unknown ? InsightsPivotRowDimension.category.rawValue : rowDimension.rawValue)
        query.add("measure", measure == .unknown ? InsightsPivotMeasure.expense.rawValue : measure.rawValue)
        query.add("accountIds", list: accountIds)
        query.add("categoryIds", list: categoryIds)
        query.add("payeeIds", list: payeeIds)
        return Endpoint(.get, "/stats/pivot", query: query.items)
    }

    /// `GET /user/settings`, decoding only the saved pivot views.
    public static func savedPivotViews() -> Endpoint<InsightsSavedPivotViews> {
        Endpoint(.get, "/user/settings")
    }

    /// `PATCH /user/settings` with the full saved-views list.
    public static func saveSavedPivotViews(_ views: [InsightsSavedPivotView]) -> Endpoint<InsightsSavedPivotViews> {
        Endpoint(.patch, "/user/settings", body: InsightsSavedPivotViewsPatch(savedPivotViews: views))
    }
}
