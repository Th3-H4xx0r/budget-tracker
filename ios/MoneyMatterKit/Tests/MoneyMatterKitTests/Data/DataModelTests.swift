import Foundation
import Testing
@testable import MoneyMatterKit

private func decodeData<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try JSONCoding.makeDecoder().decode(Value.self, from: Data(json.utf8))
}

private func decodeEnvelope<Value>(_ endpoint: Endpoint<Value>, _ json: String) throws -> Value {
    try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
}

/// Encodes a request body to a JSON object for field-by-field assertions.
private func encodedObject(_ value: any Encodable) throws -> [String: Any] {
    let data = try JSONCoding.makeEncoder().encode(value)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private let transactionJSON = #"{"id":"t1","amount":12.5,"time":"2026-10-01T10:00:00.000Z","accountId":"a1","currencyCode":"EUR","transactionType":"expense"}"#
private let incomeJSON = #"{"id":"t2","amount":12.5,"time":"2026-10-02T10:00:00.000Z","accountId":"a2","currencyCode":"EUR","transactionType":"income"}"#

@Suite("Data import models")
struct DataImportModelTests {
    @Test func decodesProgressWithSummaryCounters() throws {
        let json = #"""
        {"status":"success","response":{"jobId":"j1","status":"completed","processedCount":10,"totalCount":10,
         "summary":{"imported":8,"skipped":2,"accountsCreated":1,"categoriesCreated":0,"batchId":"b1",
          "newTransactionIds":["x"],"errors":[{"rowIndex":3,"error":"Bad date"},{"rowIndex":null,"error":"Desync","code":"account-balance-desync"}],
          "accountBalanceChanges":[{"accountId":"a1","accountName":"Main","balanceAfter":120.5,"movedCount":8,"historicalCount":0,"isNewAccount":false,"balanceBefore":100,"delta":20.5}]}}}
        """#
        let progress = try decodeEnvelope(Endpoints.dataCSVStatus(jobId: "j1"), json)
        #expect(progress.status == .completed)
        #expect(progress.fraction == 1)
        let summary = try #require(progress.summary)
        #expect(summary.importedCount == 8)
        #expect(summary.counts["skipped"] == 2)
        #expect(summary.batchId == "b1")
        #expect(summary.errors.count == 2)
        #expect(summary.errors[1].rowIndex == nil)
        #expect(summary.errors[1].code == "account-balance-desync")
        #expect(summary.accountBalanceChanges.first?.delta == Decimal(string: "20.5"))
    }

    @Test func decodesFailedAndUnknownStatus() throws {
        let failed = try decodeData(DataImportProgress.self, #"{"jobId":"j","status":"failed","processedCount":0,"totalCount":0,"error":"Boom"}"#)
        #expect(failed.status == .failed)
        #expect(failed.error == "Boom")
        #expect(failed.fraction == nil)
        let odd = try decodeData(DataImportProgress.self, #"{"jobId":"j","status":"paused","processedCount":1,"totalCount":4}"#)
        #expect(odd.status == .unknown)
        #expect(odd.status.isFinished == false)
    }

    @Test func duplicateAmountsConvertFromCents() throws {
        let json = #"""
        {"duplicates":[{"rowIndex":4,"importedTransaction":{"rowIndex":4,"date":"2026-10-01T00:00:00.000Z","amount":1250,"description":"Coffee","accountName":"Main","currencyCode":"EUR","transactionType":"expense"},
          "existingTransaction":{"id":"e1","date":"2026-10-01T00:00:00.000Z","amount":1250,"note":"Coffee shop","accountId":"a1"},"matchType":"exact","confidence":95}],
         "validRows":[{},{}],"invalidRows":[{"rowIndex":1,"errors":["x"],"rawData":{}}]}
        """#
        let response = try decodeData(DataImportDuplicatesResponse.self, json)
        let duplicate = try #require(response.duplicates.first)
        #expect(duplicate.rowIndex == 4)
        #expect(duplicate.importedAmount == Decimal(string: "12.5"))
        #expect(duplicate.existingAmount == Decimal(string: "12.5"))
        #expect(duplicate.importedDescription == "Coffee")
        #expect(duplicate.confidence == 95)
        #expect(response.validRowCount == 2)
        #expect(response.invalidRowCount == 1)
    }

    @Test func statementDuplicateKeepsExtractedDecimal() throws {
        let json = #"""
        {"duplicates":[{"transactionIndex":2,"extractedTransaction":{"date":"2026-10-01","description":"Rent","amount":800,"type":"expense"},
          "existingTransaction":{"id":"e1","date":"2026-10-01T00:00:00.000Z","amount":80000,"note":"Rent"}}]}
        """#
        let duplicate = try #require(try decodeData(DataImportDuplicatesResponse.self, json).duplicates.first)
        #expect(duplicate.rowIndex == 2)
        #expect(duplicate.importedAmount == 800)
        #expect(duplicate.existingAmount == 800)
    }

    @Test func decodesProviderParseResultsAcrossSources() throws {
        let ofx = #"""
        {"status":"success","response":{"uploadId":"u1","result":{"accounts":[{"sourceAccountKey":"k1","maskedDisplayName":"••1234","suggestedLocalName":"Checking 1234","statementType":"bank","accountType":"CHECKING","currency":"USD","transactionCount":3,"netImportedAmount":"-12.30"}],
          "transactions":[{},{},{}],"warnings":[{"code":"fitid-missing","message":"Missing ids","count":2}],"dateRange":{"from":"2026-09-01","to":"2026-09-30"},"formatVersion":"220","financialInstitutionName":null},
          "lease":{"expiresAt":"2026-10-09T10:00:00.000Z"}}}
        """#
        let parsed = try decodeEnvelope(Endpoints.dataProviderParse(.ofx, fileContent: ""), ofx)
        #expect(parsed.uploadId == "u1")
        let account = try #require(parsed.result.accounts.first)
        #expect(account.key == "k1")
        #expect(account.displayName == "Checking 1234")
        #expect(account.netAmount == Decimal(string: "-12.30"))
        #expect(parsed.result.transactionCount == 3)
        #expect(parsed.result.warnings.first?.count == 2)

        let money = #"""
        {"result":{"accounts":[{"originalName":"Brokerage","currency":"USD","accountType":5,"transactionCount":1,"netImportedAmount":10},{"originalName":"Cash","currency":"USD","accountType":2,"transactionCount":4,"netImportedAmount":-3.5}],
          "categories":[{"fullName":"Auto:Gas","name":"Gas","groupName":"Auto","transactionCount":2}],"payees":[],"transactions":[],"transfers":[{}],"warnings":[],"dateRange":null,"baseCurrency":"USD","encryption":"new-sha1"}}
        """#
        let moneyParsed = try decodeData(DataProviderParseResponse.self, money)
        #expect(moneyParsed.result.accounts.map(\.isImportable) == [false, true])
        #expect(moneyParsed.result.categories.first?.name == "Auto:Gas")
        #expect(moneyParsed.result.transferCount == 1)
        #expect(moneyParsed.result.baseCurrency == "USD")

        let ynab = #"{"result":{"accounts":[{"originalName":"Checking","detectedCurrency":null,"startingBalance":100,"transactionCount":2}],"categories":[],"transactions":[],"transfers":[],"warnings":[{"code":"currency-undetected","message":"No currency"}],"dateRange":null}}"#
        let ynabParsed = try decodeData(DataProviderParseResponse.self, ynab)
        #expect(ynabParsed.result.accounts.first?.currency == nil)
        #expect(ynabParsed.result.accounts.first?.startingBalance == 100)
        #expect(ynabParsed.result.warnings.first?.count == nil)
    }

    @Test func decodesStatementEstimateSuccessAndFailure() throws {
        let success = try decodeData(DataStatementCostEstimate.self, #"{"estimatedInputTokens":42000,"estimatedOutputTokens":3000,"estimatedCostUsd":0.0123,"modelId":"m","modelName":"Model","usingUserKey":false,"textExtraction":{"success":true,"characterCount":100,"pageCount":2},"fileType":"pdf"}"#)
        #expect(success.success)
        #expect(success.estimatedInputTokens == 42000)
        #expect(success.usingUserKey == false)
        #expect(success.textExtraction?.pageCount == 2)

        let failure = try decodeData(DataStatementCostEstimate.self, #"{"success":false,"textExtraction":{"success":false,"characterCount":0,"pageCount":1,"errorCode":"PASSWORD_REQUIRED"},"fileType":"pdf","suggestion":"Enter the password","error":{"code":"X","message":"Locked"}}"#)
        #expect(failure.success == false)
        #expect(failure.textExtraction?.errorCode == "PASSWORD_REQUIRED")
        #expect(failure.errorMessage == "Locked")
        #expect(failure.suggestion == "Enter the password")
    }

    @Test func decodesStatementExtraction() throws {
        let json = #"{"transactions":[{"date":"2026-09-02","description":"Salary","amount":2500,"type":"income","confidence":0.9}],"metadata":{"bankName":"Bank","statementPeriod":{"from":"2026-09-01","to":"2026-09-30"},"currencyCode":"EUR"},"pageCount":1,"fileType":"pdf","tokenCount":{"input":1,"output":1},"droppedRowCount":0}"#
        let extraction = try decodeData(DataStatementExtraction.self, json)
        #expect(extraction.transactions.first?.isIncome == true)
        #expect(extraction.metadata?.statementPeriod?.to == "2026-09-30")
    }

    @Test func decodesHistoryAndDeleteResults() throws {
        let page = try decodeData(DataImportBatchPage.self, #"{"items":[{"batchId":"b1","source":"ms-money","importedAt":"2026-10-01T10:00:00.000Z","transactionCount":12,"accountIds":["a1"]},{"batchId":"b2","source":"future-source","importedAt":"2026-10-01T10:00:00Z","transactionCount":1,"accountIds":[]}],"totalCount":null}"#)
        #expect(page.items.map(\.source) == [.msMoney, .unknown])
        #expect(page.totalCount == nil)

        let inline = try decodeData(DataImportBatchDeleteResult.self, #"{"deletedCount":3,"deletedIds":["a","b","c"]}"#)
        #expect(inline.deletedCount == 3)
        #expect(inline.jobId == nil)
        let queued = try decodeData(DataImportBatchDeleteResult.self, #"{"jobId":"j1"}"#)
        #expect(queued.jobId == "j1")

        let idle = try decodeData(DataImportBatchDeleteStatus.self, #"{"state":"idle"}"#)
        #expect(idle.isActive == false)
        let running = try decodeData(DataImportBatchDeleteStatus.self, #"{"state":"running","jobId":"j1"}"#)
        #expect(running.isActive)
        let failed = try decodeData(DataImportBatchDeleteStatus.self, #"{"state":"failed","jobId":"j1","error":"Nope"}"#)
        #expect(failed.state == .failed)
        #expect(failed.error == "Nope")
    }

    @Test func decodesCSVParseAndUniqueValues() throws {
        let parse = try decodeEnvelope(Endpoints.dataCSVParse(fileContent: "a"), #"{"status":"success","response":{"headers":["Date","Amount"],"preview":[{"Date":"01/02/2026","Amount":"-3"}],"detectedDelimiter":",","totalRows":1}}"#)
        #expect(parse.headers == ["Date", "Amount"])
        #expect(parse.preview.first?["Amount"] == "-3")
        let values = try decodeData(DataCSVUniqueValues.self, #"{"sourceAccounts":[{"name":"Card","currency":"EUR"}],"sourceCategories":["Food"],"sourceTags":[]}"#)
        #expect(values.sourceAccounts.first?.currency == "EUR")
        #expect(values.currencyMismatchWarning == nil)
    }
}

@Suite("Data import requests")
struct DataImportRequestTests {
    @Test func encodesAccountMappingVariants() throws {
        let csv = try encodedObject(DataImportAccountMapping.createNew())
        #expect(csv["action"] as? String == "create-new")
        #expect(csv["currentBalance"] is NSNull)
        #expect(csv["name"] == nil)

        let ofx = try encodedObject(DataImportAccountMapping.createNew(name: "Checking", currencyCode: "USD", currentBalance: Decimal(string: "10.5")))
        #expect(ofx["name"] as? String == "Checking")
        #expect(ofx["currencyCode"] as? String == "USD")
        #expect((ofx["currentBalance"] as? NSNumber)?.doubleValue == 10.5)

        let link = try encodedObject(DataImportAccountMapping.linkExisting(accountId: "a1"))
        #expect(link["action"] as? String == "link-existing")
        #expect(link["accountId"] as? String == "a1")
        #expect(try encodedObject(DataImportAccountMapping.skip)["action"] as? String == "skip")
    }

    @Test func encodesCSVColumnMapping() throws {
        let mapping = DataCSVColumnMapping(
            date: "Date",
            dateFieldOrder: .monthFirst,
            amount: "Amount",
            description: "Memo",
            tagsColumn: "Tags",
            category: .mapColumn("Category"),
            currency: .existing(currencyCode: "EUR"),
            transactionType: .column("Type", incomeValues: ["IN"], expenseValues: ["OUT"]),
            account: .existing(accountId: "a1")
        )
        let object = try encodedObject(mapping)
        #expect(object["dateFieldOrder"] as? String == "month-first")
        #expect(object["payee"] == nil)
        #expect((object["tags"] as? [String: Any])?["option"] as? String == "map-data-source-column")
        #expect((object["category"] as? [String: Any])?["option"] as? String == "map-data-source-column")
        #expect((object["category"] as? [String: Any])?["columnName"] as? String == "Category")
        #expect((object["currency"] as? [String: Any])?["currencyCode"] as? String == "EUR")
        let type = try #require(object["transactionType"] as? [String: Any])
        #expect(type["option"] as? String == "data-source-column")
        #expect(type["incomeValues"] as? [String] == ["IN"])
        #expect((object["account"] as? [String: Any])?["option"] as? String == "existing-account")

        let signed = DataCSVColumnMapping(
            date: "D", dateFieldOrder: .dayFirst, amount: "A",
            category: .existing(categoryId: "c1"), currency: .column("Cur"),
            transactionType: .amountSign, account: .column("Acc")
        )
        let signedObject = try encodedObject(signed)
        #expect(signedObject["tags"] == nil)
        #expect((signedObject["transactionType"] as? [String: Any])?["option"] as? String == "amount-sign")
        #expect((signedObject["category"] as? [String: Any])?["categoryId"] as? String == "c1")
    }

    @Test func encodesProviderRequestByUploadKind() throws {
        let binary = DataProviderImportRequest(
            uploadId: "u1",
            accountMapping: ["k": .skip],
            categoryMapping: ["Auto:Gas": .linkExisting(categoryId: "c1"), "Food": .createNew],
            skipDuplicateIndices: [1, 2],
            recalculateBalance: true,
            includeVoidedTransactions: false
        )
        let object = try encodedObject(binary)
        #expect(object["uploadId"] as? String == "u1")
        #expect(object["fileContent"] == nil)
        #expect(object["skipDuplicateIndices"] as? [Int] == [1, 2])
        let categories = try #require(object["categoryMapping"] as? [String: [String: Any]])
        #expect(categories["Auto:Gas"]?["categoryId"] as? String == "c1")
        #expect(categories["Food"]?["action"] as? String == "create-new")

        let ynab = try encodedObject(DataYnabExecuteRequest(fileContent: "csv", accountMapping: ["Checking": DataYnabAccountMapping(currencyCode: "USD")]))
        let account = try #require((ynab["accountMapping"] as? [String: [String: Any]])?["Checking"])
        #expect(account["currencyCode"] as? String == "USD")
        #expect(account["skip"] == nil)
    }

    @Test func statementRoutesShapeSkipIndices() throws {
        let transaction = DataExtractedTransaction(date: "2026-09-01", description: "Rent", amount: 800, type: "expense")
        let request = DataStatementImportRequest(accountId: "a1", transactions: [transaction], skipIndices: [0])
        let detect = try encodedObject(try #require(Endpoints.dataStatementDetectDuplicates(request).body))
        #expect(detect["skipIndices"] == nil)
        let execute = try encodedObject(try #require(Endpoints.dataStatementExecute(
            DataStatementImportRequest(accountId: "a1", transactions: [transaction])
        ).body))
        #expect(execute["skipIndices"] as? [Int] == [])
        #expect(Endpoints.dataStatementExecute(request).path == "/import/text-source/execute")
    }

    @Test func providerPathsAndCapabilities() {
        #expect(Endpoints.dataProviderStatus(.budgetBakersWallet, jobId: "j").path == "/import/budget-bakers-wallet/status/j")
        #expect(Endpoints.dataProviderExecute(.msMoney, request: DataProviderImportRequest(accountMapping: [:])).path == "/import/ms-money/execute")
        #expect(DataProviderKind.ofx.uploadsBinary)
        #expect(!DataProviderKind.ynab.hasDuplicateDetection)
        #expect(DataProviderKind.budgetBakersWallet.hasCategoryMapping)
        #expect(!DataProviderKind.ofx.hasCategoryMapping)
        let lease = Endpoints.dataRefreshUploadLease(.ofx, uploadId: "u1")
        #expect(lease.path == "/resource-leases/refresh")
    }

    @Test func historyQueryClampsLimit() throws {
        let endpoint = Endpoints.dataImportBatches(limit: 500, offset: -1)
        #expect(endpoint.queryItems.first { $0.name == "limit" }?.value == "100")
        #expect(endpoint.queryItems.first { $0.name == "offset" }?.value == "0")
        let delete = try encodedObject(try #require(Endpoints.dataDeleteImportBatch(batchId: "b1", deleteLinkedTransfers: true).body))
        #expect(delete["deleteLinkedTransfers"] as? Bool == true)
    }
}

@Suite("Data export")
struct DataExportTests {
    @Test func encodesExportRequest() throws {
        let request = DataExportRequest(
            format: .xlsx,
            groups: [.transactions, .budgets],
            dateRange: DataExportDateRange(from: CalendarDate(year: 2026, month: 1, day: 5), to: nil),
            accountIds: []
        )
        let object = try encodedObject(request)
        #expect(object["format"] as? String == "xlsx")
        #expect(object["groups"] as? [String] == ["transactions", "budgets"])
        #expect((object["dateRange"] as? [String: Any])?["from"] as? String == "2026-01-05")
        #expect((object["dateRange"] as? [String: Any])?["to"] == nil)
        #expect(object["accountIds"] == nil)
    }

    @Test func parsesDownloadHeaders() {
        #expect(DataExportFile.filename(fromContentDisposition: #"attachment; filename="moneymatter-export-2026-10-09.zip""#) == "moneymatter-export-2026-10-09.zip")
        #expect(DataExportFile.filename(fromContentDisposition: nil) == DataExportFile.defaultFilename)
        #expect(DataExportFile.filename(fromContentDisposition: "attachment; filename=../evil.zip") == ".._evil.zip")
        #expect(DataExportFile.totalRows(fromHeader: "42") == 42)
        #expect(DataExportFile.totalRows(fromHeader: "42xyz") == nil)
        #expect(DataExportFile.totalRows(fromHeader: nil) == nil)
    }
}

@Suite("Data optimizations")
struct DataOptimizationTests {
    @Test func decodesTransferScanPage() throws {
        let json = #"{"status":"success","response":{"total":1,"items":[{"expense":\#(transactionJSON),"matches":[{"transaction":\#(incomeJSON),"confidence":87}]}]}}"#
        let page = try decodeEnvelope(Endpoints.dataTransferScan(DataTransferScanRequest(from: .now, to: .now)), json)
        #expect(page.total == 1)
        let suggestion = try #require(page.items.first)
        #expect(suggestion.expense.id == "t1")
        #expect(suggestion.matches.first?.confidence == 87)
        #expect(suggestion.matches.first?.transaction.id == "t2")
    }

    @Test func encodesTransferWrites() throws {
        let scan = try encodedObject(DataTransferScanRequest(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 86_399), limit: 20, offset: 40))
        #expect(scan["from"] as? String == "1970-01-01T00:00:00.000Z")
        #expect(scan["offset"] as? Int == 40)
        #expect(scan["includeOutOfWallet"] as? Bool == false)

        let link = Endpoints.dataLinkTransfer(expenseId: "e", incomeId: "i")
        #expect(link.method == .put)
        #expect(try encodedObject(try #require(link.body))["ids"] as? [[String]] == [["e", "i"]])

        let dismiss = try encodedObject(try #require(Endpoints.dataDismissTransfer(expenseId: "e", incomeId: "i").body))
        #expect(dismiss["expenseTransactionId"] as? String == "e")
        #expect(dismiss["incomeTransactionId"] as? String == "i")
        // 204 with an empty body.
        _ = try Endpoints.dataDismissTransfer(expenseId: "e", incomeId: "i").decodeBody(Data(), JSONCoding.makeDecoder())
    }

    @Test func decodesCategorizationStatus() throws {
        let idle = try decodeData(DataAICategorizationStatus.self, #"{"status":"idle"}"#)
        #expect(idle.status == .idle)
        #expect(!idle.status.isActive)
        let running = try decodeData(DataAICategorizationStatus.self, #"{"status":"processing","processedCount":40,"totalCount":100,"failedCount":2,"skippedCount":3}"#)
        #expect(running.status.isActive)
        #expect(running.categorizedCount == 35)
        #expect(running.fraction == 0.4)
        let odd = try decodeData(DataAICategorizationStatus.self, #"{"status":"exploded"}"#)
        #expect(odd.status == .unknown)
    }

    @Test func triggerOmitsEmptyIds() throws {
        let all = try encodedObject(try #require(Endpoints.dataTriggerAICategorization().body))
        #expect(all["transactionIds"] == nil)
        let empty = try encodedObject(try #require(Endpoints.dataTriggerAICategorization(transactionIds: []).body))
        #expect(empty["transactionIds"] == nil)
        let some = try encodedObject(try #require(Endpoints.dataTriggerAICategorization(transactionIds: ["t1"]).body))
        #expect(some["transactionIds"] as? [String] == ["t1"])
        let result = try decodeData(DataAICategorizationTriggerResult.self, #"{"enqueued":true,"totalCount":12}"#)
        #expect(result.enqueued)
    }

    @Test func decodesCandidatesHistoryAndFeature() throws {
        let candidates = try decodeData(DataAICategorizationCandidates.self, #"{"items":[\#(transactionJSON)],"totalCount":1}"#)
        #expect(candidates.items.count == 1)
        let history = try decodeData(DataAICategorizationHistory.self, #"{"items":[{"categorizedAt":"2026-10-01T10:00:00.123Z","transactionCount":5,"trigger":"import"},{"categorizedAt":"2026-09-01T10:00:00.000Z","transactionCount":1,"trigger":null}],"totalCount":null}"#)
        #expect(history.items.first?.trigger == .import)
        #expect(history.items.first?.categorizedAtRaw == "2026-10-01T10:00:00.123Z")
        #expect(history.items.last?.trigger == nil)

        let features = #"{"status":"success","response":{"features":[{"feature":"statement_parsing","isConfigured":true,"modelId":"a","modelName":"A","usingUserKey":true},{"feature":"categorization","isConfigured":true,"modelId":"b","modelName":"B","usingUserKey":false}]}}"#
        let feature = try decodeEnvelope(Endpoints.dataAICategorizationFeature(), features)
        #expect(feature?.modelName == "B")
        #expect(feature?.usingUserKey == false)

        let run = Endpoints.dataAICategorizationRunTransactions(categorizedAt: "2026-10-01T10:00:00.123Z")
        #expect(run.queryItems.contains { $0.name == "categorizationSource" && $0.value == "ai" })
        #expect(run.queryItems.contains { $0.name == "categorizedAt" && $0.value == "2026-10-01T10:00:00.123Z" })
    }
}

/// `GET /user/settings/ai/features` as `getFeaturesStatus` builds it. `isConfigured` is
/// `!!config` (an explicit per-feature pick); a feature without one still resolves a model
/// through the user's key, endpoint, or the server key, and the web treats any resolved
/// `categorization` entry as set up.
@Suite("Data AI categorization readiness")
struct DataAICategorizationReadinessTests {
    private func categorization(_ entry: String) throws -> DataAIFeatureStatus {
        let json = """
        {"status":"success","response":{"features":[
          \(entry),
          {"feature":"statement_parsing","isConfigured":false,"modelId":"google/gemini-3.6-flash","modelName":"Gemini 3.6 Flash","usingUserKey":true},
          {"feature":"investment_transactions_parsing","isConfigured":false,"modelId":"google/gemini-3.6-flash","modelName":"Gemini 3.6 Flash","usingUserKey":true},
          {"feature":"recurring_detection","isConfigured":false,"modelId":"google/gemini-3.5-flash-lite","modelName":"Gemini 3.5 Flash Lite","usingUserKey":true}
        ]}}
        """
        return try #require(try decodeEnvelope(Endpoints.dataAICategorizationFeature(), json))
    }

    @Test("A saved provider key with no per-feature pick runs on the feature's default model")
    func savedKeyOnDefaultModelIsReady() throws {
        let status = try categorization(
            #"{"feature":"categorization","isConfigured":false,"modelId":"google/gemma-4-31b-it","modelName":"Gemma 4 31B","usingUserKey":true}"#
        )
        #expect(status.modelName == "Gemma 4 31B")
        #expect(status.usingUserKey)
        #expect(status.isReadyToCategorize)
    }

    @Test("A saved custom endpoint with no per-feature pick serves categorization")
    func fallbackEndpointIsReady() throws {
        let status = try categorization(
            #"{"feature":"categorization","isConfigured":false,"modelId":"custom/llama3.1:8b","modelName":"llama3.1:8b","usingUserKey":true,"customEndpointId":"0b8f6a8e-2d0a-4a51-9c1e-6a2f3d1b9e77","endpointName":"Home Ollama"}"#
        )
        #expect(status.endpointName == "Home Ollama")
        #expect(status.isReadyToCategorize)
    }

    @Test("The server key serves the default model without any user setup")
    func serverKeyDefaultIsReady() throws {
        let status = try categorization(
            #"{"feature":"categorization","isConfigured":false,"modelId":"google/gemma-4-31b-it","modelName":"Gemma 4 31B","usingUserKey":false}"#
        )
        #expect(!status.usingUserKey)
        #expect(status.isReadyToCategorize)
    }

    @Test("An explicit per-feature pick is ready")
    func explicitPickIsReady() throws {
        let status = try categorization(
            #"{"feature":"categorization","isConfigured":true,"modelId":"openai/gpt-5.4-nano","modelName":"GPT-5.4 Nano","usingUserKey":true}"#
        )
        #expect(status.isReadyToCategorize)
    }
}

@Suite("Data AI category mapping")
struct DataAICategoryMappingTests {
    @Test func decodesMatchesAndNulls() throws {
        let json = #"{"status":"success","response":{"mappings":{"Food":"c1","Misc":null}}}"#
        let result = try Endpoints.dataAIMapCategories(["Food", "Misc"]).decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
        #expect(result.matched == ["Food": "c1"])
        #expect(result.mappings.count == 2)
    }
}
