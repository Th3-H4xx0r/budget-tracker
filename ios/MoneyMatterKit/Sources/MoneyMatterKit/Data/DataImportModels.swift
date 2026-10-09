import Foundation

// MARK: - Shared import types

/// `ImportSource` on the backend; tags each import batch.
public enum DataImportSource: String, LenientEnum {
    case csv
    case ynab
    case statementParser = "statement-parser"
    case budgetBakersWallet = "budget-bakers-wallet"
    case msMoney = "ms-money"
    case ofx
    case unknown
}

/// `queued | running | completed | failed` for every import job.
public enum DataImportJobStatus: String, LenientEnum {
    case queued, running, completed, failed, unknown

    public var isFinished: Bool { self == .completed || self == .failed }
}

/// `{jobId}` returned by every `execute` route.
public struct DataImportJobRef: Sendable, Hashable, Decodable {
    public let jobId: String
}

/// One row-level or file-level failure in an import summary.
public struct DataImportRowError: Sendable, Hashable, Decodable {
    public let rowIndex: Int?
    public let error: String
    public let code: String?

    private enum CodingKeys: String, CodingKey { case rowIndex, transactionIndex, error, code }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rowIndex = try container.decodeIfPresent(Int.self, forKey: .rowIndex)
            ?? container.decodeIfPresent(Int.self, forKey: .transactionIndex)
        error = try container.decodeIfPresent(String.self, forKey: .error) ?? ""
        code = try container.decodeIfPresent(String.self, forKey: .code)
    }
}

/// How an import moved one account's balance.
public struct DataImportBalanceChange: Sendable, Hashable, Decodable, Identifiable {
    public let accountId: String
    public let accountName: String
    public let balanceAfter: Decimal
    public let balanceBefore: Decimal?
    public let delta: Decimal?
    public let isNewAccount: Bool
    public let movedCount: Int

    public var id: String { accountId }

    private enum CodingKeys: String, CodingKey {
        case accountId, accountName, balanceAfter, balanceBefore, delta, isNewAccount, movedCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try container.decode(String.self, forKey: .accountId)
        accountName = try container.decodeIfPresent(String.self, forKey: .accountName) ?? ""
        balanceAfter = try container.decodeIfPresent(Decimal.self, forKey: .balanceAfter) ?? 0
        balanceBefore = try container.decodeIfPresent(Decimal.self, forKey: .balanceBefore)
        delta = try container.decodeIfPresent(Decimal.self, forKey: .delta)
        isNewAccount = try container.decodeIfPresent(Bool.self, forKey: .isNewAccount) ?? false
        movedCount = try container.decodeIfPresent(Int.self, forKey: .movedCount) ?? 0
    }
}

/// The finished-job summary. Every source reports a different set of counters, so the
/// numeric fields are kept by name (`imported`, `transactionsImported`, `accountsCreated`, ...).
public struct DataImportSummary: Sendable, Hashable, Decodable {
    public let counts: [String: Int]
    public let errors: [DataImportRowError]
    public let batchId: String?
    public let newTransactionIds: [String]
    public let accountBalanceChanges: [DataImportBalanceChange]

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyDataKey.self)
        var counts: [String: Int] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(Int.self, forKey: key) { counts[key.stringValue] = value }
        }
        self.counts = counts
        errors = (try? container.decodeIfPresent([DataImportRowError].self, forKey: AnyDataKey("errors"))) ?? []
        batchId = try? container.decodeIfPresent(String.self, forKey: AnyDataKey("batchId"))
        newTransactionIds = (try? container.decodeIfPresent([String].self, forKey: AnyDataKey("newTransactionIds"))) ?? []
        accountBalanceChanges = (try? container.decodeIfPresent(
            [DataImportBalanceChange].self, forKey: AnyDataKey("accountBalanceChanges")
        )) ?? []
    }

    /// Transactions created, whichever counter the source uses.
    public var importedCount: Int { counts["imported"] ?? counts["transactionsImported"] ?? 0 }
}

/// Progress of an import job, from `GET /import/<source>/status/:jobId`.
public struct DataImportProgress: Sendable, Hashable, Decodable {
    public let jobId: String
    public let status: DataImportJobStatus
    public let processedCount: Int
    public let totalCount: Int
    public let summary: DataImportSummary?
    public let error: String?

    private enum CodingKeys: String, CodingKey { case jobId, status, processedCount, totalCount, summary, error }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decodeIfPresent(String.self, forKey: .jobId) ?? ""
        status = try container.decodeLenient(DataImportJobStatus.self, forKey: .status, default: .unknown)
        processedCount = try container.decodeIfPresent(Int.self, forKey: .processedCount) ?? 0
        totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount) ?? 0
        summary = try container.decodeIfPresent(DataImportSummary.self, forKey: .summary)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    /// 0...1, or `nil` before the job knows its size.
    public var fraction: Double? {
        guard totalCount > 0 else { return nil }
        return min(1, Double(processedCount) / Double(totalCount))
    }
}

struct AnyDataKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// A row the import would create that looks like an existing transaction.
/// `detect-duplicates` sends amounts as integer cents; `amount` here is the decimal.
public struct DataImportDuplicate: Sendable, Hashable, Decodable, Identifiable {
    public let rowIndex: Int
    public let importedDate: String
    public let importedAmount: Decimal
    public let importedDescription: String
    public let existingTransactionId: String
    public let existingDate: String
    public let existingAmount: Decimal
    public let existingNote: String
    public let matchType: String?
    public let confidence: Int?

    public var id: Int { rowIndex }

    private enum CodingKeys: String, CodingKey {
        case rowIndex, transactionIndex, importedTransaction, extractedTransaction, existingTransaction, matchType, confidence
    }

    private struct Imported: Decodable {
        let date: String?
        let amount: Decimal?
        let description: String?
        let note: String?
    }

    private struct Existing: Decodable {
        let id: String
        let date: String?
        let amount: Decimal?
        let note: String?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let extracted = try container.decodeIfPresent(Imported.self, forKey: .extractedTransaction)
        let imported = try container.decodeIfPresent(Imported.self, forKey: .importedTransaction) ?? extracted
        let existing = try container.decode(Existing.self, forKey: .existingTransaction)
        rowIndex = try container.decodeIfPresent(Int.self, forKey: .rowIndex)
            ?? container.decode(Int.self, forKey: .transactionIndex)
        importedDate = imported?.date ?? ""
        // Statement-parser rows carry the extracted decimal; every other source sends cents.
        let rawImported = imported?.amount ?? 0
        importedAmount = extracted != nil ? rawImported : rawImported / 100
        importedDescription = imported?.description ?? imported?.note ?? ""
        existingTransactionId = existing.id
        existingDate = existing.date ?? ""
        existingAmount = (existing.amount ?? 0) / 100
        existingNote = existing.note ?? ""
        matchType = try container.decodeIfPresent(String.self, forKey: .matchType)
        confidence = try container.decodeIfPresent(Int.self, forKey: .confidence)
    }
}

/// `{duplicates}` from every `detect-duplicates` route.
public struct DataImportDuplicatesResponse: Sendable, Decodable {
    public let duplicates: [DataImportDuplicate]
    public let invalidRowCount: Int
    public let validRowCount: Int?

    private enum CodingKeys: String, CodingKey { case duplicates, invalidRows, validRows }

    private struct Ignored: Decodable {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duplicates = try container.decodeLossyArrayIfPresent([DataImportDuplicate].self, forKey: .duplicates) ?? []
        invalidRowCount = (try? container.decodeIfPresent([Ignored].self, forKey: .invalidRows))?.count ?? 0
        validRowCount = (try? container.decodeIfPresent([Ignored].self, forKey: .validRows))?.count
    }
}

// MARK: - Mappings (request bodies)

/// Where a source account's rows go. `create-new` carries the fields each source needs:
/// CSV takes only `currentBalance`, Wallet and MS Money add `currencyCode`, OFX adds `name`.
public enum DataImportAccountMapping: Sendable, Hashable, Encodable {
    case createNew(name: String? = nil, currencyCode: String? = nil, currentBalance: Decimal? = nil)
    case linkExisting(accountId: String)
    case skip

    private enum CodingKeys: String, CodingKey { case action, name, currencyCode, currentBalance, accountId }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .createNew(let name, let currencyCode, let currentBalance):
            try container.encode("create-new", forKey: .action)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(currencyCode, forKey: .currencyCode)
            if let currentBalance {
                try container.encode(currentBalance, forKey: .currentBalance)
            } else {
                try container.encodeNil(forKey: .currentBalance)
            }
        case .linkExisting(let accountId):
            try container.encode("link-existing", forKey: .action)
            try container.encode(accountId, forKey: .accountId)
        case .skip:
            try container.encode("skip", forKey: .action)
        }
    }
}

/// Where a source category's rows go.
public enum DataImportCategoryMapping: Sendable, Hashable, Encodable {
    case createNew
    case linkExisting(categoryId: String)

    private enum CodingKeys: String, CodingKey { case action, categoryId }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .createNew:
            try container.encode("create-new", forKey: .action)
        case .linkExisting(let categoryId):
            try container.encode("link-existing", forKey: .action)
            try container.encode(categoryId, forKey: .categoryId)
        }
    }
}

/// YNAB's mapping: every account is created with a currency, or skipped.
public struct DataYnabAccountMapping: Sendable, Hashable, Encodable {
    public var currencyCode: String
    public var skip: Bool?

    public init(currencyCode: String, skip: Bool? = nil) {
        self.currencyCode = currencyCode
        self.skip = skip
    }
}

// MARK: - CSV

/// `POST /import/csv/parse`.
public struct DataCSVParseResult: Sendable, Decodable {
    public let headers: [String]
    public let preview: [[String: String]]
    public let detectedDelimiter: String
    public let totalRows: Int
}

public enum DataCSVDateFieldOrder: String, Sendable, Hashable, Codable, CaseIterable {
    case dayFirst = "day-first"
    case monthFirst = "month-first"
}

/// `ColumnMappingConfig`: which CSV column feeds each field.
public struct DataCSVColumnMapping: Sendable, Hashable, Encodable {
    public enum CategoryOption: Sendable, Hashable {
        case mapColumn(String)
        case createNew(column: String)
        case existing(categoryId: String)
    }

    public enum CurrencyOption: Sendable, Hashable {
        case column(String)
        case existing(currencyCode: String)
    }

    public enum TransactionTypeOption: Sendable, Hashable {
        case amountSign
        case column(String, incomeValues: [String], expenseValues: [String])
    }

    public enum AccountOption: Sendable, Hashable {
        case column(String)
        case existing(accountId: String)
    }

    public var date: String
    public var dateFieldOrder: DataCSVDateFieldOrder
    public var amount: String
    public var description: String?
    public var payee: String?
    public var tagsColumn: String?
    public var category: CategoryOption
    public var currency: CurrencyOption
    public var transactionType: TransactionTypeOption
    public var account: AccountOption

    public init(
        date: String,
        dateFieldOrder: DataCSVDateFieldOrder,
        amount: String,
        description: String? = nil,
        payee: String? = nil,
        tagsColumn: String? = nil,
        category: CategoryOption,
        currency: CurrencyOption,
        transactionType: TransactionTypeOption,
        account: AccountOption
    ) {
        self.date = date
        self.dateFieldOrder = dateFieldOrder
        self.amount = amount
        self.description = description
        self.payee = payee
        self.tagsColumn = tagsColumn
        self.category = category
        self.currency = currency
        self.transactionType = transactionType
        self.account = account
    }

    private enum CodingKeys: String, CodingKey {
        case date, dateFieldOrder, amount, description, payee, tags, category, currency, transactionType, account
    }

    private enum OptionKeys: String, CodingKey {
        case option, columnName, categoryId, currencyCode, accountId, incomeValues, expenseValues
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(dateFieldOrder, forKey: .dateFieldOrder)
        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(payee, forKey: .payee)
        if let tagsColumn {
            var tags = container.nestedContainer(keyedBy: OptionKeys.self, forKey: .tags)
            try tags.encode("map-data-source-column", forKey: .option)
            try tags.encode(tagsColumn, forKey: .columnName)
        }

        var category = container.nestedContainer(keyedBy: OptionKeys.self, forKey: .category)
        switch self.category {
        case .mapColumn(let column):
            try category.encode("map-data-source-column", forKey: .option)
            try category.encode(column, forKey: .columnName)
        case .createNew(let column):
            try category.encode("create-new-categories", forKey: .option)
            try category.encode(column, forKey: .columnName)
        case .existing(let categoryId):
            try category.encode("existing-category", forKey: .option)
            try category.encode(categoryId, forKey: .categoryId)
        }

        var currency = container.nestedContainer(keyedBy: OptionKeys.self, forKey: .currency)
        switch self.currency {
        case .column(let column):
            try currency.encode("data-source-column", forKey: .option)
            try currency.encode(column, forKey: .columnName)
        case .existing(let code):
            try currency.encode("existing-currency", forKey: .option)
            try currency.encode(code, forKey: .currencyCode)
        }

        var type = container.nestedContainer(keyedBy: OptionKeys.self, forKey: .transactionType)
        switch transactionType {
        case .amountSign:
            try type.encode("amount-sign", forKey: .option)
        case .column(let column, let incomeValues, let expenseValues):
            try type.encode("data-source-column", forKey: .option)
            try type.encode(column, forKey: .columnName)
            try type.encode(incomeValues, forKey: .incomeValues)
            try type.encode(expenseValues, forKey: .expenseValues)
        }

        var account = container.nestedContainer(keyedBy: OptionKeys.self, forKey: .account)
        switch self.account {
        case .column(let column):
            try account.encode("data-source-column", forKey: .option)
            try account.encode(column, forKey: .columnName)
        case .existing(let accountId):
            try account.encode("existing-account", forKey: .option)
            try account.encode(accountId, forKey: .accountId)
        }
    }
}

/// `POST /import/csv/extract-unique-values`.
public struct DataCSVUniqueValues: Sendable, Decodable {
    public struct SourceAccount: Sendable, Hashable, Decodable {
        public let name: String
        public let currency: String
    }

    public let sourceAccounts: [SourceAccount]
    public let sourceCategories: [String]
    public let sourceTags: [String]
    public let currencyMismatchWarning: String?

    private enum CodingKeys: String, CodingKey { case sourceAccounts, sourceCategories, sourceTags, currencyMismatchWarning }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceAccounts = try container.decodeIfPresent([SourceAccount].self, forKey: .sourceAccounts) ?? []
        sourceCategories = try container.decodeIfPresent([String].self, forKey: .sourceCategories) ?? []
        sourceTags = try container.decodeIfPresent([String].self, forKey: .sourceTags) ?? []
        currencyMismatchWarning = try container.decodeIfPresent(String.self, forKey: .currencyMismatchWarning)
    }
}

/// The CSV body shared by `extract-unique-values`, `detect-duplicates`, and `execute`.
public struct DataCSVImportRequest: Sendable, Encodable {
    public var fileContent: String
    public var delimiter: String
    public var columnMapping: DataCSVColumnMapping
    public var accountMapping: [String: DataImportAccountMapping]?
    public var categoryMapping: [String: DataImportCategoryMapping]?
    public var tagMapping: [String: DataCSVTagMapping]?
    public var skipDuplicateIndices: [Int]?
    public var recalculateBalance: Bool?
    public var timezone: String?

    public init(
        fileContent: String,
        delimiter: String,
        columnMapping: DataCSVColumnMapping,
        accountMapping: [String: DataImportAccountMapping]? = nil,
        categoryMapping: [String: DataImportCategoryMapping]? = nil,
        tagMapping: [String: DataCSVTagMapping]? = nil,
        skipDuplicateIndices: [Int]? = nil,
        recalculateBalance: Bool? = nil,
        timezone: String? = nil
    ) {
        self.fileContent = fileContent
        self.delimiter = delimiter
        self.columnMapping = columnMapping
        self.accountMapping = accountMapping
        self.categoryMapping = categoryMapping
        self.tagMapping = tagMapping
        self.skipDuplicateIndices = skipDuplicateIndices
        self.recalculateBalance = recalculateBalance
        self.timezone = timezone
    }
}

public enum DataCSVTagMapping: String, Sendable, Hashable, Encodable {
    case createNew = "create-new"
    case skip

    private enum CodingKeys: String, CodingKey { case action }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .action)
    }
}

// MARK: - Provider parse results (YNAB, OFX, MS Money, Wallet)

/// A source account as each provider's parser reports it, normalized for the mapping step.
public struct DataSourceAccount: Sendable, Hashable, Identifiable, Decodable {
    /// The mapping key: `sourceAccountKey` for OFX, `originalName` for the others.
    public let key: String
    public let displayName: String
    public let currency: String?
    public let transactionCount: Int
    public let netAmount: Decimal?
    public let startingBalance: Decimal?
    /// MS Money's numeric account type; investment (5) and loan (6) aren't importable.
    public let msMoneyAccountType: Int?

    public var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case sourceAccountKey, maskedDisplayName, suggestedLocalName, originalName, currency, detectedCurrency
        case transactionCount, netImportedAmount, startingBalance, accountType
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let ofxKey = try container.decodeIfPresent(String.self, forKey: .sourceAccountKey) {
            key = ofxKey
            displayName = try container.decodeIfPresent(String.self, forKey: .suggestedLocalName)
                ?? container.decodeIfPresent(String.self, forKey: .maskedDisplayName) ?? ofxKey
            msMoneyAccountType = nil
        } else {
            key = try container.decode(String.self, forKey: .originalName)
            displayName = key
            msMoneyAccountType = try? container.decodeIfPresent(Int.self, forKey: .accountType)
        }
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
            ?? container.decodeIfPresent(String.self, forKey: .detectedCurrency)
        transactionCount = try container.decodeIfPresent(Int.self, forKey: .transactionCount) ?? 0
        if let text = try? container.decodeIfPresent(String.self, forKey: .netImportedAmount) {
            netAmount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        } else {
            netAmount = try? container.decodeIfPresent(Decimal.self, forKey: .netImportedAmount)
        }
        startingBalance = try container.decodeIfPresent(Decimal.self, forKey: .startingBalance)
    }

    public var isImportable: Bool {
        guard let msMoneyAccountType else { return true }
        return msMoneyAccountType <= 4
    }
}

/// A source category, normalized: Wallet's `name`, YNAB/MS Money's `fullName`.
public struct DataSourceCategory: Sendable, Hashable, Identifiable, Decodable {
    public let name: String
    public let transactionCount: Int

    public var id: String { name }

    private enum CodingKeys: String, CodingKey { case name, fullName, transactionCount }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .fullName)
            ?? container.decode(String.self, forKey: .name)
        transactionCount = try container.decodeIfPresent(Int.self, forKey: .transactionCount) ?? 0
    }
}

public struct DataImportWarning: Sendable, Hashable, Decodable {
    public let code: String
    public let message: String
    public let count: Int?
}

public struct DataImportDateRange: Sendable, Hashable, Decodable {
    public let from: String
    public let to: String
}

/// The parse result every provider shares enough of for the review and mapping steps.
public struct DataProviderParseResult: Sendable, Decodable {
    public let accounts: [DataSourceAccount]
    public let categories: [DataSourceCategory]
    public let transactionCount: Int
    public let transferCount: Int
    public let warnings: [DataImportWarning]
    public let dateRange: DataImportDateRange?
    public let baseCurrency: String?

    private enum CodingKeys: String, CodingKey {
        case accounts, categories, transactions, transfers, warnings, dateRange, baseCurrency, detectedBaseCurrency
    }

    private struct Counted: Decodable {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decodeLossyArrayIfPresent([DataSourceAccount].self, forKey: .accounts) ?? []
        categories = try container.decodeLossyArrayIfPresent([DataSourceCategory].self, forKey: .categories) ?? []
        transactionCount = (try? container.decodeIfPresent([Counted].self, forKey: .transactions))?.count ?? 0
        transferCount = (try? container.decodeIfPresent([Counted].self, forKey: .transfers))?.count ?? 0
        warnings = try container.decodeLossyArrayIfPresent([DataImportWarning].self, forKey: .warnings) ?? []
        dateRange = try? container.decodeIfPresent(DataImportDateRange.self, forKey: .dateRange)
        baseCurrency = try container.decodeIfPresent(String.self, forKey: .baseCurrency)
            ?? container.decodeIfPresent(String.self, forKey: .detectedBaseCurrency)
    }
}

/// `{result}` from YNAB and Wallet parse; `{uploadId, result}` from OFX and MS Money upload.
public struct DataProviderParseResponse: Sendable, Decodable {
    public let uploadId: String?
    public let result: DataProviderParseResult
}

/// Body for provider `detect-duplicates` and `execute`. Text sources send `fileContent`,
/// binary sources send the `uploadId` from the upload step.
public struct DataProviderImportRequest: Sendable, Encodable {
    public var fileContent: String?
    public var uploadId: String?
    public var accountMapping: [String: DataImportAccountMapping]
    public var categoryMapping: [String: DataImportCategoryMapping]?
    public var skipDuplicateIndices: [Int]?
    public var recalculateBalance: Bool?
    public var includeVoidedTransactions: Bool?

    public init(
        fileContent: String? = nil,
        uploadId: String? = nil,
        accountMapping: [String: DataImportAccountMapping],
        categoryMapping: [String: DataImportCategoryMapping]? = nil,
        skipDuplicateIndices: [Int]? = nil,
        recalculateBalance: Bool? = nil,
        includeVoidedTransactions: Bool? = nil
    ) {
        self.fileContent = fileContent
        self.uploadId = uploadId
        self.accountMapping = accountMapping
        self.categoryMapping = categoryMapping
        self.skipDuplicateIndices = skipDuplicateIndices
        self.recalculateBalance = recalculateBalance
        self.includeVoidedTransactions = includeVoidedTransactions
    }
}

public struct DataYnabExecuteRequest: Sendable, Encodable {
    public var fileContent: String
    public var accountMapping: [String: DataYnabAccountMapping]

    public init(fileContent: String, accountMapping: [String: DataYnabAccountMapping]) {
        self.fileContent = fileContent
        self.accountMapping = accountMapping
    }
}

/// The four provider importers. Each has the same route shape under `/import/<path>`.
public enum DataProviderKind: String, Sendable, Hashable, CaseIterable {
    case ynab
    case ofx
    case msMoney = "ms-money"
    case budgetBakersWallet = "budget-bakers-wallet"

    /// Binary files are uploaded raw once; text files are re-sent as `fileContent`.
    public var uploadsBinary: Bool { self == .ofx || self == .msMoney }
    public var hasDuplicateDetection: Bool { self != .ynab }
    public var hasCategoryMapping: Bool { self == .msMoney || self == .budgetBakersWallet }
    public var path: String { "/import/\(rawValue)" }
}

// MARK: - Statement parser (text source)

public struct DataStatementTextExtraction: Sendable, Hashable, Decodable {
    public let success: Bool
    public let characterCount: Int
    public let pageCount: Int
    public let error: String?
    public let errorCode: String?
}

/// `POST /import/text-source/estimate-cost`: either an estimate or `{success:false, ...}`.
public struct DataStatementCostEstimate: Sendable, Decodable {
    public let success: Bool
    public let estimatedInputTokens: Int?
    public let estimatedOutputTokens: Int?
    public let estimatedCostUsd: Decimal?
    public let modelName: String?
    public let usingUserKey: Bool?
    public let textExtraction: DataStatementTextExtraction?
    public let fileType: String?
    public let suggestion: String?
    public let errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case success, estimatedInputTokens, estimatedOutputTokens, estimatedCostUsd, modelName, usingUserKey
        case textExtraction, fileType, suggestion, error
    }

    private struct ErrorBody: Decodable { let message: String? }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
        estimatedInputTokens = try container.decodeIfPresent(Int.self, forKey: .estimatedInputTokens)
        estimatedOutputTokens = try container.decodeIfPresent(Int.self, forKey: .estimatedOutputTokens)
        estimatedCostUsd = try container.decodeIfPresent(Decimal.self, forKey: .estimatedCostUsd)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        usingUserKey = try container.decodeIfPresent(Bool.self, forKey: .usingUserKey)
        textExtraction = try? container.decodeIfPresent(DataStatementTextExtraction.self, forKey: .textExtraction)
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType)
        suggestion = try container.decodeIfPresent(String.self, forKey: .suggestion)
        errorMessage = (try? container.decodeIfPresent(ErrorBody.self, forKey: .error))?.message
    }
}

/// One AI-extracted row. Sent back verbatim to `detect-duplicates` and `execute`.
public struct DataExtractedTransaction: Sendable, Hashable, Codable {
    public var date: String
    public var description: String
    public var merchant: String?
    public var amount: Decimal
    public var type: String
    public var balance: Decimal?
    public var confidence: Decimal?

    public var isIncome: Bool { type == "income" }
}

public struct DataStatementMetadata: Sendable, Hashable, Decodable {
    public struct Period: Sendable, Hashable, Decodable {
        public let from: String
        public let to: String
    }

    public let bankName: String?
    public let accountNumberLast4: String?
    public let statementPeriod: Period?
    public let currencyCode: String?
}

/// `POST /import/text-source/extract`.
public struct DataStatementExtraction: Sendable, Decodable {
    public let transactions: [DataExtractedTransaction]
    public let metadata: DataStatementMetadata?
    public let pageCount: Int?
    public let droppedRowCount: Int?
}

public struct DataStatementFileRequest: Sendable, Encodable {
    public var fileBase64: String
    public var password: String?

    public init(fileBase64: String, password: String? = nil) {
        self.fileBase64 = fileBase64
        self.password = password
    }
}

public struct DataStatementImportRequest: Sendable, Encodable {
    public var accountId: String
    public var transactions: [DataExtractedTransaction]
    public var skipIndices: [Int]?

    public init(accountId: String, transactions: [DataExtractedTransaction], skipIndices: [Int]? = nil) {
        self.accountId = accountId
        self.transactions = transactions
        self.skipIndices = skipIndices
    }
}

// MARK: - History

/// One past import, from `GET /import/batches-history`.
public struct DataImportBatch: Sendable, Hashable, Identifiable, Decodable {
    public let batchId: String
    public let source: DataImportSource
    public let importedAt: Date
    public let transactionCount: Int
    public let accountIds: [String]

    public var id: String { batchId }
}

public struct DataImportBatchPage: Sendable, Decodable {
    public let items: [DataImportBatch]
    public let totalCount: Int?
}

/// `DELETE /import/batch/:id` deletes small batches inline and queues big ones.
public struct DataImportBatchDeleteResult: Sendable, Decodable {
    public let deletedCount: Int?
    public let jobId: String?
}

/// `GET /import/batch-delete/status`: the caller's background delete, if any.
public struct DataImportBatchDeleteStatus: Sendable, Decodable {
    public let state: DataImportJobStatus
    public let jobId: String?
    public let deletedCount: Int?
    public let error: String?

    private enum CodingKeys: String, CodingKey { case state, jobId, deletedCount, error }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent(String.self, forKey: .state) ?? "idle"
        state = raw == "idle" ? .unknown : (DataImportJobStatus(rawValue: raw) ?? .unknown)
        jobId = try container.decodeIfPresent(String.self, forKey: .jobId)
        deletedCount = try container.decodeIfPresent(Int.self, forKey: .deletedCount)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    public var isActive: Bool { state == .queued || state == .running }
}

struct DataBatchDeleteRequest: Encodable, Sendable {
    let deleteLinkedTransfers: Bool
}
