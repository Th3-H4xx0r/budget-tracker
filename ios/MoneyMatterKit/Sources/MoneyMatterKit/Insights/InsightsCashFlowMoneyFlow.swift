// The cash flow report's money flow: where the period's income came from, where it went,
// and what was saved. A port of the web `build-money-flow.ts`.
import Foundation

/// One node of the money flow.
public struct CashFlowMoneyFlowNode: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// A category (or a destination portfolio, deal, or savings category).
        case regular
        /// Everything folded below the top N.
        case other
        /// Net savings not accounted for by any destination.
        case keptAsCash
        /// Spending and saving beyond the period's income.
        case deficit
    }

    public let id: String
    public let kind: Kind
    public let name: String
    /// `#rrggbb`, when known.
    public let color: String?
    public let parentName: String?
    public let value: Decimal
    /// 0...1 of the node's column.
    public let share: Double
    /// Nodes folded into an `.other` node, largest first.
    public let children: [CashFlowMoneyFlowNode]

    public init(
        id: String,
        kind: Kind = .regular,
        name: String,
        color: String? = nil,
        parentName: String? = nil,
        value: Decimal,
        share: Double,
        children: [CashFlowMoneyFlowNode] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.color = color
        self.parentName = parentName
        self.value = value
        self.share = share
        self.children = children
    }

    func withShare(_ share: Double) -> CashFlowMoneyFlowNode {
        CashFlowMoneyFlowNode(
            id: id, kind: kind, name: name, color: color, parentName: parentName,
            value: value, share: share, children: children
        )
    }
}

/// Where invested money went: a portfolio or a venture deal. Only positive amounts count.
public struct CashFlowMoneyFlowDestination: Sendable, Hashable {
    public let id: String
    public let name: String
    public let color: String?
    public let value: Decimal

    public init(id: String, name: String, color: String? = nil, value: Decimal) {
        self.id = id
        self.name = name
        self.color = color
        self.value = value
    }
}

public struct CashFlowMoneyFlow: Sendable, Hashable {
    public let income: Decimal
    public let expenses: Decimal
    public let net: Decimal
    /// Net savings, or the invested and saved-to-category amount when that is larger.
    public let savings: Decimal
    /// The shortfall covered from outside the period's income.
    public let deficit: Decimal
    /// Income sources plus, when the period needed more than it earned, a deficit node.
    public let sources: [CashFlowMoneyFlowNode]
    public let expenseNodes: [CashFlowMoneyFlowNode]
    public let savingsNodes: [CashFlowMoneyFlowNode]

    public var isEmpty: Bool { income == 0 && expenses == 0 && savings == 0 }
}

public enum CashFlowMoneyFlowBuilder {
    /// Nodes below this share of their column fold into "other" even within the top N.
    static let minShare = 0.01

    /// - Parameters:
    ///   - sourceLevel: The category depth income rolls up to (1 = root categories).
    ///   - expenseLevel: The category depth spending rolls up to.
    ///   - topN: How many nodes each column keeps before folding the rest into "other".
    ///   - savingsCategoryIds: Categories whose spend is saving, not expense (subcategories inherit).
    public static func build(
        data: [CategorySpendingByType],
        categories: [Category],
        destinations: [CashFlowMoneyFlowDestination] = [],
        sourceLevel: Int = 2,
        expenseLevel: Int = 1,
        topN: Int = 8,
        savingsCategoryIds: Set<String> = []
    ) -> CashFlowMoneyFlow {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var spend: [CategorySpendingByType] = []
        var savedByCategory: [String: Decimal] = [:]
        for entry in data {
            guard let target = ancestorChain(entry.id, byID: byID).first(where: savingsCategoryIds.contains) else {
                spend.append(entry)
                continue
            }
            let saved = entry.expense - entry.income
            if saved > 0 { savedByCategory[target, default: 0] += saved }
        }

        var sources = rollUp(spend, pick: \.income, level: sourceLevel, topN: topN, byID: byID)
        let expenseNodes = rollUp(spend, pick: \.expense, level: expenseLevel, topN: topN, byID: byID)
        let income = sources.reduce(Decimal.zero) { $0 + $1.value }
        let expenses = expenseNodes.reduce(Decimal.zero) { $0 + $1.value }
        let net = income - expenses

        let destinationNodes: [(id: String, name: String, color: String?, value: Decimal)] =
            (destinations.filter { $0.value > 0 }.map { ($0.id, $0.name, $0.color, $0.value) }
                + savedByCategory.map { id, value in (id, byID[id]?.name ?? id, byID[id]?.color, value) })
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name }
        let destinationsTotal = destinationNodes.reduce(Decimal.zero) { $0 + $1.value }
        let savings = max(net, destinationsTotal, 0)
        let deficit = max(0, expenses + savings - income)

        if deficit > 0 {
            sources.append(CashFlowMoneyFlowNode(id: "deficit", kind: .deficit, name: "", value: deficit, share: 0))
            let column = income + deficit
            sources = sources.map { $0.withShare(ratio($0.value, column)) }
        }

        var savingsNodes = destinationNodes.map {
            CashFlowMoneyFlowNode(id: $0.id, name: $0.name, color: $0.color, value: $0.value, share: ratio($0.value, savings))
        }
        let cash = savings - destinationsTotal
        if cash > 0 {
            savingsNodes.append(
                CashFlowMoneyFlowNode(id: "cash", kind: .keptAsCash, name: "", value: cash, share: ratio(cash, savings))
            )
        }

        return CashFlowMoneyFlow(
            income: income,
            expenses: expenses,
            net: net,
            savings: savings,
            deficit: deficit,
            sources: sources,
            expenseNodes: expenseNodes,
            savingsNodes: savingsNodes
        )
    }

    /// Category ids from the root down to `id` itself.
    static func ancestorChain(_ id: String, byID: [String: Category]) -> [String] {
        var chain: [String] = []
        var current = byID[id]
        while let category = current, chain.count < 32 {
            chain.insert(category.id, at: 0)
            current = category.parentId.flatMap { byID[$0] }
        }
        return chain
    }

    private static func rollUp(
        _ data: [CategorySpendingByType],
        pick: KeyPath<CategorySpendingByType, Decimal>,
        level: Int,
        topN: Int,
        byID: [String: Category]
    ) -> [CashFlowMoneyFlowNode] {
        let dataByID = Dictionary(data.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var totals: [String: Decimal] = [:]
        for entry in data {
            let amount = entry[keyPath: pick]
            guard amount > 0 else { continue }
            let chain = ancestorChain(entry.id, byID: byID)
            let target = chain.isEmpty ? entry.id : chain[min(max(level, 1), chain.count) - 1]
            totals[target, default: 0] += amount
        }
        let total = totals.values.reduce(Decimal.zero, +)
        guard total > 0 else { return [] }

        let nodes = totals.map { id, value -> CashFlowMoneyFlowNode in
            let category = byID[id]
            let parent = category?.parentId.flatMap { byID[$0] }
            return CashFlowMoneyFlowNode(
                id: id,
                name: category?.name ?? dataByID[id]?.name ?? id,
                color: category?.color ?? dataByID[id]?.color,
                parentName: parent?.name,
                value: value,
                share: ratio(value, total)
            )
        }
        .sorted { $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name }

        let kept = nodes.prefix(max(topN, 0)).filter { $0.share >= minShare }
        if nodes.count - kept.count <= 1 { return nodes }
        let rest = Array(nodes.dropFirst(kept.count))
        let restValue = rest.reduce(Decimal.zero) { $0 + $1.value }
        return kept + [
            CashFlowMoneyFlowNode(id: "other", kind: .other, name: "", value: restValue, share: ratio(restValue, total), children: rest)
        ]
    }

    private static func ratio(_ value: Decimal, _ total: Decimal) -> Double {
        guard total != 0 else { return 0 }
        return NSDecimalNumber(decimal: value / total).doubleValue
    }
}

/// The savings-category slice of `GET /user/settings`; other keys are ignored.
public struct CashFlowSavingsSettings: Sendable, Hashable, Decodable {
    public let savingsCategoryIds: [String]

    public init(savingsCategoryIds: [String]) {
        self.savingsCategoryIds = savingsCategoryIds
    }

    private enum CodingKeys: String, CodingKey { case savingsCategoryIds }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        savingsCategoryIds = (try? container.decodeIfPresent([String].self, forKey: .savingsCategoryIds)) ?? []
    }
}

extension Endpoints {
    /// `GET /user/settings`, decoding only `savingsCategoryIds`.
    public static func cashFlowSavingsSettings() -> Endpoint<CashFlowSavingsSettings> {
        Endpoint(.get, "/user/settings")
    }
}
