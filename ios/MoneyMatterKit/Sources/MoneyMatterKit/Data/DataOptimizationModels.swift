import Foundation

// MARK: - Transfer suggestions

/// One possible counterpart for an expense: an income on another account.
public struct DataTransferMatch: Sendable, Hashable, Decodable, Identifiable {
    public let transaction: Transaction
    /// 0...100.
    public let confidence: Int

    public var id: String { transaction.id }

    private enum CodingKeys: String, CodingKey { case transaction, confidence }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transaction = try container.decode(Transaction.self, forKey: .transaction)
        let raw = try container.decodeIfPresent(Decimal.self, forKey: .confidence) ?? 0
        confidence = NSDecimalNumber(decimal: raw).intValue
    }
}

/// An expense with its likely transfer counterparts, best match first.
public struct DataTransferSuggestion: Sendable, Hashable, Decodable, Identifiable {
    public let expense: Transaction
    public let matches: [DataTransferMatch]

    public var id: String { expense.id }

    private enum CodingKeys: String, CodingKey { case expense, matches }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expense = try container.decode(Transaction.self, forKey: .expense)
        matches = try container.decodeLossyArrayIfPresent([DataTransferMatch].self, forKey: .matches) ?? []
    }
}

/// `POST /transactions/transfer-recommendations/bulk-scan`.
public struct DataTransferScanPage: Sendable, Decodable {
    public let total: Int
    public let items: [DataTransferSuggestion]
}

public struct DataTransferScanRequest: Sendable, Encodable {
    public var from: Date
    public var to: Date
    public var limit: Int
    public var offset: Int
    public var includeOutOfWallet: Bool

    public init(from: Date, to: Date, limit: Int = 20, offset: Int = 0, includeOutOfWallet: Bool = false) {
        self.from = from
        self.to = to
        self.limit = limit
        self.offset = offset
        self.includeOutOfWallet = includeOutOfWallet
    }
}

struct DataTransferLinkRequest: Sendable, Encodable {
    let ids: [[String]]
}

public struct DataTransferDismissRequest: Sendable, Encodable {
    public let expenseTransactionId: String
    public let incomeTransactionId: String
}

// MARK: - AI categorization

public enum DataAICategorizationState: String, LenientEnum {
    case idle, queued, processing, completed, failed, unknown

    public var isActive: Bool { self == .queued || self == .processing }
}

/// `GET /user/ai/categorization/status`. Reads `idle` when nothing runs; a finished
/// status is reported once, then it's `idle` again.
public struct DataAICategorizationStatus: Sendable, Hashable, Decodable {
    public let status: DataAICategorizationState
    public let processedCount: Int
    public let totalCount: Int
    public let failedCount: Int
    public let skippedCount: Int
    public let errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case status, processedCount, totalCount, failedCount, skippedCount, errorMessage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeLenient(DataAICategorizationState.self, forKey: .status, default: .idle)
        processedCount = try container.decodeIfPresent(Int.self, forKey: .processedCount) ?? 0
        totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount) ?? 0
        failedCount = try container.decodeIfPresent(Int.self, forKey: .failedCount) ?? 0
        skippedCount = try container.decodeIfPresent(Int.self, forKey: .skippedCount) ?? 0
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }

    /// Transactions that got a category: processed minus failed and skipped.
    public var categorizedCount: Int { max(0, processedCount - failedCount - skippedCount) }

    public var fraction: Double? {
        guard totalCount > 0 else { return nil }
        return min(1, Double(processedCount) / Double(totalCount))
    }
}

/// `POST /user/ai/categorization/trigger`.
public struct DataAICategorizationTriggerResult: Sendable, Decodable {
    public let enqueued: Bool
    public let totalCount: Int
}

struct DataAICategorizationTriggerRequest: Sendable, Encodable {
    let transactionIds: [String]?
}

/// `GET /user/ai/categorization/candidates`: `totalCount` only on the first page.
public struct DataAICategorizationCandidates: Sendable, Decodable {
    public let items: [Transaction]
    public let totalCount: Int?
}

public enum DataAICategorizationTrigger: String, LenientEnum {
    case manual, `import`, sync, unknown
}

/// One past run, identified by its `categorizedAt` stamp.
public struct DataAICategorizationRun: Sendable, Hashable, Identifiable, Decodable {
    public let categorizedAt: Date
    public let categorizedAtRaw: String
    public let transactionCount: Int
    public let trigger: DataAICategorizationTrigger?

    public var id: String { categorizedAtRaw }

    private enum CodingKeys: String, CodingKey { case categorizedAt, transactionCount, trigger }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categorizedAtRaw = try container.decode(String.self, forKey: .categorizedAt)
        categorizedAt = APIDateFormat.parseTimestamp(categorizedAtRaw) ?? .distantPast
        transactionCount = try container.decodeIfPresent(Int.self, forKey: .transactionCount) ?? 0
        trigger = try container.decodeIfPresent(DataAICategorizationTrigger.self, forKey: .trigger)
    }
}

public struct DataAICategorizationHistory: Sendable, Decodable {
    public let items: [DataAICategorizationRun]
    public let totalCount: Int?
}

/// The `categorization` entry of `GET /user/settings/ai/features`.
public struct DataAIFeatureStatus: Sendable, Hashable, Decodable {
    public let feature: String
    public let isConfigured: Bool
    public let modelName: String?
    public let usingUserKey: Bool
    public let endpointName: String?

    private enum CodingKeys: String, CodingKey { case feature, isConfigured, modelName, usingUserKey, endpointName }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        feature = try container.decode(String.self, forKey: .feature)
        isConfigured = try container.decodeIfPresent(Bool.self, forKey: .isConfigured) ?? false
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        usingUserKey = try container.decodeIfPresent(Bool.self, forKey: .usingUserKey) ?? false
        endpointName = try container.decodeIfPresent(String.self, forKey: .endpointName)
    }
}

struct DataAIFeaturesResponse: Sendable, Decodable {
    let features: [DataAIFeatureStatus]
}

// MARK: - Endpoints

extension Endpoints {
    /// `POST /transactions/transfer-recommendations/bulk-scan`: paged, synchronous.
    public static func dataTransferScan(_ request: DataTransferScanRequest) -> Endpoint<DataTransferScanPage> {
        Endpoint(.post, "/transactions/transfer-recommendations/bulk-scan", body: request)
    }

    /// `PUT /transactions/link` with `[expenseId, incomeId]` pairs.
    public static func dataLinkTransfer(expenseId: String, incomeId: String) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/transactions/link", body: DataTransferLinkRequest(ids: [[expenseId, incomeId]]))
    }

    /// `POST /transactions/transfer-recommendations/dismiss`: 204; the pair stops appearing.
    public static func dataDismissTransfer(expenseId: String, incomeId: String) -> Endpoint<EmptyResponse> {
        Endpoint(
            .post,
            "/transactions/transfer-recommendations/dismiss",
            body: DataTransferDismissRequest(expenseTransactionId: expenseId, incomeTransactionId: incomeId)
        )
    }

    public static func dataAICategorizationStatus() -> Endpoint<DataAICategorizationStatus> {
        Endpoint(.get, "/user/ai/categorization/status")
    }

    /// Omit `transactionIds` to run over every candidate.
    public static func dataTriggerAICategorization(transactionIds: [String]? = nil) -> Endpoint<DataAICategorizationTriggerResult> {
        let ids = transactionIds.flatMap { $0.isEmpty ? nil : $0 }
        return Endpoint(.post, "/user/ai/categorization/trigger", body: DataAICategorizationTriggerRequest(transactionIds: ids))
    }

    public static func dataAICategorizationCandidates(limit: Int = 30, offset: Int = 0) -> Endpoint<DataAICategorizationCandidates> {
        var query = QueryBuilder()
        query.add("limit", min(max(limit, 1), 100))
        query.add("offset", max(offset, 0))
        return Endpoint(.get, "/user/ai/categorization/candidates", query: query.items)
    }

    public static func dataAICategorizationHistory(limit: Int = 20, offset: Int = 0) -> Endpoint<DataAICategorizationHistory> {
        var query = QueryBuilder()
        query.add("limit", min(max(limit, 1), 100))
        query.add("offset", max(offset, 0))
        return Endpoint(.get, "/user/ai/categorization/history", query: query.items)
    }

    /// The transactions one AI run categorized.
    public static func dataAICategorizationRunTransactions(categorizedAt: String, limit: Int = 30, offset: Int = 0) -> Endpoint<[Transaction]> {
        var query = QueryBuilder()
        query.add("categorizationSource", "ai")
        query.add("categorizedAt", categorizedAt)
        query.add("limit", limit)
        query.add("offset", offset)
        query.addFlag("includeSplits", true)
        query.addFlag("includeTags", true)
        return Endpoint(.get, "/transactions", query: query.items)
    }

    /// The `categorization` feature's AI setup, or `nil` when it isn't listed.
    public static func dataAICategorizationFeature() -> Endpoint<DataAIFeatureStatus?> {
        Endpoint<DataAIFeaturesResponse>(.get, "/user/settings/ai/features")
            .map { $0.features.first { $0.feature == "categorization" } }
    }
}
