import Foundation

// MARK: - Import endpoints

extension Endpoints {
    // CSV

    public static func dataCSVParse(fileContent: String, delimiter: String? = nil) -> Endpoint<DataCSVParseResult> {
        Endpoint(.post, "/import/csv/parse", body: DataCSVParseRequest(fileContent: fileContent, delimiter: delimiter))
    }

    public static func dataCSVUniqueValues(_ request: DataCSVImportRequest) -> Endpoint<DataCSVUniqueValues> {
        Endpoint(.post, "/import/csv/extract-unique-values", body: request)
    }

    public static func dataCSVDetectDuplicates(_ request: DataCSVImportRequest) -> Endpoint<DataImportDuplicatesResponse> {
        Endpoint(.post, "/import/csv/detect-duplicates", body: request)
    }

    public static func dataCSVExecute(_ request: DataCSVImportRequest) -> Endpoint<DataImportJobRef> {
        Endpoint(.post, "/import/csv/execute", body: request)
    }

    public static func dataCSVStatus(jobId: String) -> Endpoint<DataImportProgress> {
        Endpoint(.get, "/import/csv/execute/status/\(jobId)")
    }

    // YNAB, Wallet (text files), OFX, MS Money (binary uploads)

    /// `POST /import/<ynab|budget-bakers-wallet>/parse`.
    public static func dataProviderParse(_ kind: DataProviderKind, fileContent: String) -> Endpoint<DataProviderParseResponse> {
        Endpoint(.post, "\(kind.path)/parse", body: DataFileContentRequest(fileContent: fileContent))
    }

    public static func dataProviderDetectDuplicates(_ kind: DataProviderKind, request: DataProviderImportRequest) -> Endpoint<DataImportDuplicatesResponse> {
        Endpoint(.post, "\(kind.path)/detect-duplicates", body: request)
    }

    public static func dataProviderExecute(_ kind: DataProviderKind, request: DataProviderImportRequest) -> Endpoint<DataImportJobRef> {
        Endpoint(.post, "\(kind.path)/execute", body: request)
    }

    public static func dataYnabExecute(_ request: DataYnabExecuteRequest) -> Endpoint<DataImportJobRef> {
        Endpoint(.post, "/import/ynab/execute", body: request)
    }

    public static func dataProviderStatus(_ kind: DataProviderKind, jobId: String) -> Endpoint<DataImportProgress> {
        Endpoint(.get, "\(kind.path)/status/\(jobId)")
    }

    /// Keeps an OFX or MS Money upload alive on the server while the user works through the
    /// steps (idle expiry is 30 minutes).
    public static func dataRefreshUploadLease(_ kind: DataProviderKind, uploadId: String) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/resource-leases/refresh", body: DataLeaseRefreshRequest(type: "\(kind.rawValue)-upload", id: uploadId))
    }

    // Statement parser (text source)

    public static func dataStatementEstimateCost(_ request: DataStatementFileRequest) -> Endpoint<DataStatementCostEstimate> {
        Endpoint(.post, "/import/text-source/estimate-cost", body: request)
    }

    public static func dataStatementExtract(_ request: DataStatementFileRequest) -> Endpoint<DataStatementExtraction> {
        Endpoint(.post, "/import/text-source/extract", body: request)
    }

    public static func dataStatementDetectDuplicates(_ request: DataStatementImportRequest) -> Endpoint<DataImportDuplicatesResponse> {
        var body = request
        body.skipIndices = nil
        return Endpoint(.post, "/import/text-source/detect-duplicates", body: body)
    }

    public static func dataStatementExecute(_ request: DataStatementImportRequest) -> Endpoint<DataImportJobRef> {
        var body = request
        body.skipIndices = request.skipIndices ?? []
        return Endpoint(.post, "/import/text-source/execute", body: body)
    }

    public static func dataStatementStatus(jobId: String) -> Endpoint<DataImportProgress> {
        Endpoint(.get, "/import/text-source/execute/status/\(jobId)")
    }

    // History

    public static func dataImportBatches(limit: Int = 30, offset: Int = 0) -> Endpoint<DataImportBatchPage> {
        var query = QueryBuilder()
        query.add("limit", min(max(limit, 1), 100))
        query.add("offset", max(offset, 0))
        return Endpoint(.get, "/import/batches-history", query: query.items)
    }

    public static func dataDeleteImportBatch(batchId: String, deleteLinkedTransfers: Bool) -> Endpoint<DataImportBatchDeleteResult> {
        Endpoint(.delete, "/import/batch/\(batchId)", body: DataBatchDeleteRequest(deleteLinkedTransfers: deleteLinkedTransfers))
    }

    public static func dataImportBatchDeleteStatus() -> Endpoint<DataImportBatchDeleteStatus> {
        Endpoint(.get, "/import/batch-delete/status")
    }

    // Export

    /// `POST /user/data-export`. The reply is the zip itself; send it with
    /// `APIClient.dataDownload(_:)`.
    public static func dataExport(_ request: DataExportRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/user/data-export", body: request)
    }
}

struct DataCSVParseRequest: Sendable, Encodable {
    let fileContent: String
    let delimiter: String?
}

struct DataFileContentRequest: Sendable, Encodable {
    let fileContent: String
}

struct DataLeaseRefreshRequest: Sendable, Encodable {
    let type: String
    let id: String
}

// MARK: - Raw transport

extension APIClient {
    /// Uploads a file as the raw `application/octet-stream` body (OFX and MS Money), with the
    /// same auth and error mapping as `send`.
    public func dataUploadFile(
        _ kind: DataProviderKind,
        fileData: Data,
        password: String? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) async throws -> DataProviderParseResponse {
        let endpoint = Endpoint<DataProviderParseResponse>(.post, "\(kind.path)/upload")
        var (request, _) = try makeRequest(for: endpoint)
        request.httpBody = fileData
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if kind == .ofx {
            request.setValue(timeZoneIdentifier, forHTTPHeaderField: "X-Timezone")
        }
        if let password, !password.isEmpty {
            request.setValue(password, forHTTPHeaderField: "x-file-password")
        }
        let (data, _) = try await Self.dataPerform(request)
        do {
            return try endpoint.decodeBody(data, JSONCoding.makeDecoder())
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Sends a JSON request whose success reply is a file rather than an envelope.
    public func dataDownload(_ request: DataExportRequest) async throws -> DataExportFile {
        var (urlRequest, _) = try makeRequest(for: Endpoints.dataExport(request))
        urlRequest.setValue("application/zip, application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 300
        let (data, response) = try await Self.dataPerform(urlRequest)
        return DataExportFile(
            data: data,
            filename: DataExportFile.filename(fromContentDisposition: response.value(forHTTPHeaderField: "Content-Disposition")),
            totalRows: DataExportFile.totalRows(fromHeader: response.value(forHTTPHeaderField: "X-Total-Rows"))
        )
    }

    private static func dataPerform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataSession.data(for: request)
        } catch let error as URLError {
            throw APIError.network(error)
        } catch {
            throw APIError.network(URLError(.cancelled))
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("The response wasn't HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw mapError(statusCode: http.statusCode, data: data)
        }
        return (data, http)
    }

    private static let dataSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 300
        return makeURLSession(configuration: configuration)
    }()
}

// MARK: - AI category suggestions

/// `POST /import/ai-map-categories`: source category name to a category id, or `null`
/// when AI found no good match.
public struct DataAICategoryMappings: Sendable, Decodable {
    public let mappings: [String: String?]

    /// Only the names AI matched.
    public var matched: [String: String] { mappings.compactMapValues { $0 } }
}

struct DataAIMapCategoriesRequest: Sendable, Encodable {
    let sourceCategories: [String]
}

extension Endpoints {
    public static func dataAIMapCategories(_ sourceCategories: [String]) -> Endpoint<DataAICategoryMappings> {
        Endpoint(.post, "/import/ai-map-categories", body: DataAIMapCategoriesRequest(sourceCategories: Array(sourceCategories.prefix(1000))))
    }
}
