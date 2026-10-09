import Foundation

/// `GET /categories` row. The list is flat; `CategoryTree` builds the hierarchy.
public struct Category: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    /// `#rrggbb`.
    public let color: String
    /// A Fluent icon name such as `food-20-filled`, or nil.
    public let icon: String?
    /// Stable key of a seeded default category, e.g. `food`.
    public let key: String?
    public let parentId: String?
    public let type: CategoryType
    public let userId: Int?

    public init(
        id: String,
        name: String,
        color: String = "#8e8e93",
        icon: String? = nil,
        key: String? = nil,
        parentId: String? = nil,
        type: CategoryType = .custom,
        userId: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.key = key
        self.parentId = parentId
        self.type = type
        self.userId = userId
    }

    private enum CodingKeys: String, CodingKey { case id, name, color, icon, key, parentId, type, userId }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#8e8e93"
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        type = try container.decodeLenient(CategoryType.self, forKey: .type, default: .custom)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId)
    }
}

/// A category with its subcategories.
public struct CategoryNode: Sendable, Hashable, Identifiable {
    public let category: Category
    public let children: [CategoryNode]

    public var id: String { category.id }

    public init(category: Category, children: [CategoryNode] = []) {
        self.category = category
        self.children = children
    }
}

/// A category paired with its depth in the tree, for indented pickers.
public struct FlattenedCategory: Sendable, Hashable, Identifiable {
    public let category: Category
    public let depth: Int

    public var id: String { category.id }
}

/// Builds the hierarchy from the flat `GET /categories` list, matching the web client:
/// input order is kept, and internal categories sort after the others at the root.
public enum CategoryTree {
    public static func build(from categories: [Category]) -> [CategoryNode] {
        let knownIDs = Set(categories.map(\.id))
        var childrenByParent: [String: [Category]] = [:]
        var roots: [Category] = []
        for category in categories {
            if let parentId = category.parentId, parentId != category.id, knownIDs.contains(parentId) {
                childrenByParent[parentId, default: []].append(category)
            } else {
                // A missing parent makes the category a root rather than dropping it.
                roots.append(category)
            }
        }

        var visited = Set<String>()
        func makeNode(_ category: Category) -> CategoryNode {
            visited.insert(category.id)
            let children = (childrenByParent[category.id] ?? [])
                .filter { !visited.contains($0.id) }
                .map(makeNode)
            return CategoryNode(category: category, children: children)
        }

        let orderedRoots = roots.filter { $0.type != .internal } + roots.filter { $0.type == .internal }
        var result = orderedRoots.map(makeNode)

        // Categories whose parent chain loops are never reached from a root; keep them visible.
        for category in categories where !visited.contains(category.id) {
            result.append(makeNode(category))
        }
        return result
    }

    /// Depth-first list of every node, for pickers that indent by depth.
    public static func flatten(_ nodes: [CategoryNode], depth: Int = 0) -> [FlattenedCategory] {
        nodes.flatMap { node in
            [FlattenedCategory(category: node.category, depth: depth)] + flatten(node.children, depth: depth + 1)
        }
    }

    /// The chain from the root down to `id`, e.g. `[Food, Restaurants]`. Empty when unknown.
    public static func path(to id: String, in categories: [Category]) -> [Category] {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var chain: [Category] = []
        var seen = Set<String>()
        var cursor = byID[id]
        while let category = cursor, !seen.contains(category.id) {
            seen.insert(category.id)
            chain.insert(category, at: 0)
            cursor = category.parentId.flatMap { byID[$0] }
        }
        return chain
    }
}
