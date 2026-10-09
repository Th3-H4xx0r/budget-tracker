import Foundation

/// `GET /transaction-groups` row: a named bundle of transactions shown together.
public struct OrgTxGroup: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let note: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let transactionCount: Int?
    /// Earliest transaction time, as the server's raw aggregate string.
    public let dateFrom: String?
    /// Latest transaction time, as the server's raw aggregate string.
    public let dateTo: String?
    /// Present on `GET /transaction-groups/:id` and with `includeTransactions`.
    public let transactions: [Transaction]?

    public init(
        id: String,
        name: String,
        note: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        transactionCount: Int? = nil,
        dateFrom: String? = nil,
        dateTo: String? = nil,
        transactions: [Transaction]? = nil
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.transactionCount = transactionCount
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.transactions = transactions
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, note, createdAt, updatedAt, transactionCount, dateFrom, dateTo, transactions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note)
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(Date.self, forKey: .updatedAt)
        if let count = try? container.decodeIfPresent(Int.self, forKey: .transactionCount) {
            transactionCount = count
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .transactionCount) {
            transactionCount = Int(text)
        } else {
            transactionCount = nil
        }
        dateFrom = try? container.decodeIfPresent(String.self, forKey: .dateFrom)
        dateTo = try? container.decodeIfPresent(String.self, forKey: .dateTo)
        transactions = try container.decodeLossyArrayIfPresent([Transaction].self, forKey: .transactions)
    }

    /// The number of transactions, from the count or the loaded list.
    public var count: Int { transactionCount ?? transactions?.count ?? 0 }

    /// `dateFrom` parsed, accepting ISO timestamps and Postgres `YYYY-MM-DD HH:MM:SS+00` strings.
    public var startDate: Date? { OrgTxGroup.parseAggregateDate(dateFrom) }
    public var endDate: Date? { OrgTxGroup.parseAggregateDate(dateTo) }

    static func parseAggregateDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        // Aggregates come back as raw Postgres text ("2026-08-01 10:00:00+00"), so normalize to
        // ISO-8601 before parsing; a lenient parse of the raw form yields the wrong instant.
        var normalized = raw.replacingOccurrences(of: " ", with: "T")
        if normalized.hasSuffix("+00") { normalized = String(normalized.dropLast(3)) + "Z" }
        if !normalized.hasSuffix("Z"), !normalized.contains("+") { normalized += "Z" }
        if let date = APIDateFormat.parseTimestamp(normalized) { return date }
        return try? Date(normalized, strategy: .iso8601)
    }
}

/// `DELETE /transaction-groups/:id/transactions` result. A group left with fewer than two
/// transactions is dissolved, and `group` is nil.
public struct OrgTxGroupRemoval: Sendable, Hashable, Decodable {
    public let group: OrgTxGroup?
    public let dissolved: Bool

    private enum CodingKeys: String, CodingKey { case group, dissolved }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        group = try container.decodeIfPresent(OrgTxGroup.self, forKey: .group)
        dissolved = try container.decodeIfPresent(Bool.self, forKey: .dissolved) ?? false
    }
}

/// `POST /transaction-groups` body. The server needs 2 to 50 transactions.
public struct OrgTxGroupCreateRequest: Encodable, Sendable, Hashable {
    public var name: String
    public var note: String?
    public var transactionIds: [String]

    public init(name: String, note: String?, transactionIds: [String]) {
        self.name = name
        self.note = note
        self.transactionIds = transactionIds
    }

    private enum CodingKeys: String, CodingKey { case name, note, transactionIds }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let note, !note.isEmpty {
            try container.encode(note, forKey: .note)
        } else {
            try container.encodeNil(forKey: .note)
        }
        try container.encode(transactionIds, forKey: .transactionIds)
    }
}

/// `PUT /transaction-groups/:id` body. An empty note clears it with `null`.
public struct OrgTxGroupUpdateRequest: Encodable, Sendable, Hashable {
    public var name: String?
    public var note: FieldUpdate<String>

    public init(name: String? = nil, note: FieldUpdate<String> = .unchanged) {
        self.name = name
        self.note = note
    }

    private enum CodingKeys: String, CodingKey { case name, note }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        switch note {
        case .unchanged:
            break
        case .clear:
            try container.encodeNil(forKey: .note)
        case .set(let value):
            try container.encode(value, forKey: .note)
        }
    }
}

private struct OrgTxGroupIDsBody: Encodable, Sendable {
    let transactionIds: [String]
}

private struct OrgTxGroupRemoveBody: Encodable, Sendable {
    let transactionIds: [String]
    let force: Bool?
}

/// Server-side caps from the transaction group controllers.
public enum OrgTxGroupLimits {
    public static let minTransactions = 2
    public static let maxTransactions = 50
    public static let maxNameLength = 100
    public static let maxNoteLength = 500
}

extension Endpoints {
    /// `GET /transaction-groups`, with counts and date ranges.
    public static func orgTxGroups(includeTransactions: Bool = false) -> Endpoint<[OrgTxGroup]> {
        var builder = QueryBuilder()
        builder.addFlag("includeTransactions", includeTransactions)
        return Endpoint(.get, "/transaction-groups", query: builder.items)
    }

    /// `GET /transaction-groups/:id`, with its transactions.
    public static func orgTxGroup(id: String) -> Endpoint<OrgTxGroup> {
        Endpoint(.get, "/transaction-groups/\(id)")
    }

    /// `POST /transaction-groups`. 409 when a transaction already belongs to a group.
    public static func orgCreateTxGroup(_ request: OrgTxGroupCreateRequest) -> Endpoint<OrgTxGroup> {
        Endpoint(.post, "/transaction-groups", body: request)
    }

    /// `PUT /transaction-groups/:id`.
    public static func orgUpdateTxGroup(id: String, _ request: OrgTxGroupUpdateRequest) -> Endpoint<OrgTxGroup> {
        Endpoint(.put, "/transaction-groups/\(id)", body: request)
    }

    /// `DELETE /transaction-groups/:id`: ungroups the transactions; they aren't deleted.
    public static func orgDeleteTxGroup(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/transaction-groups/\(id)")
    }

    /// `POST /transaction-groups/:id/transactions`.
    public static func orgAddTransactionsToTxGroup(groupId: String, transactionIds: [String]) -> Endpoint<OrgTxGroup> {
        Endpoint(.post, "/transaction-groups/\(groupId)/transactions", body: OrgTxGroupIDsBody(transactionIds: transactionIds))
    }

    /// `DELETE /transaction-groups/:id/transactions`. Without `force`, a removal that would
    /// leave fewer than two transactions fails with 409; with it, the group dissolves.
    public static func orgRemoveTransactionsFromTxGroup(
        groupId: String,
        transactionIds: [String],
        force: Bool = false
    ) -> Endpoint<OrgTxGroupRemoval> {
        Endpoint(
            .delete,
            "/transaction-groups/\(groupId)/transactions",
            body: OrgTxGroupRemoveBody(transactionIds: transactionIds, force: force ? true : nil)
        )
    }
}
