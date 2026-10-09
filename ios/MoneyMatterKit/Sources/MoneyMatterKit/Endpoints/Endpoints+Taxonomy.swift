import Foundation

extension Endpoints {
    /// `GET /categories`: the flat list; build the tree with `CategoryTree.build(from:)`.
    public static func categories() -> Endpoint<[Category]> {
        Endpoint(.get, "/categories")
    }

    /// `GET /tags`.
    public static func tags() -> Endpoint<[Tag]> {
        Endpoint(.get, "/tags")
    }

    /// `GET /payees/lookup`: every payee's id, name, and logo, unpaginated.
    public static func payeesLookup() -> Endpoint<[PayeeLookup]> {
        Endpoint(.get, "/payees/lookup")
    }

    /// `GET /payees?q=`: a search forces the server's limit to 20.
    public static func searchPayees(query: String?, limit: Int? = nil, offset: Int? = nil) -> Endpoint<[Payee]> {
        var builder = QueryBuilder()
        builder.add("q", query?.trimmingCharacters(in: .whitespacesAndNewlines))
        builder.add("limit", limit)
        builder.add("offset", offset)
        return Endpoint(.get, "/payees", query: builder.items)
    }
}
