import Foundation

/// The upload body for `POST /transactions/:id/attachments`: raw bytes, not JSON. The server
/// reads the name from `X-Filename` (percent-encoded) and sniffs the type from the bytes.
public struct TransactionAttachmentUpload: Sendable, Hashable {
    public static let filenameHeader = "X-Filename"

    public let transactionId: String
    public let filename: String
    public let data: Data

    public init(transactionId: String, filename: String, data: Data) {
        self.transactionId = transactionId
        self.filename = filename
        self.data = data
    }

    public var path: String { "/transactions/\(transactionId)/attachments" }

    /// `filename` with every character outside the unreserved set percent-encoded, matching
    /// the web client's `encodeURIComponent`.
    public var encodedFilename: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return filename.addingPercentEncoding(withAllowedCharacters: allowed) ?? "attachment"
    }
}

extension APIClient {
    /// Uploads one attachment. `APIClient.send` only encodes JSON bodies, so this builds the
    /// request from the same base (URL, bearer token, language headers) and swaps in raw bytes.
    public func uploadTransactionAttachment(_ upload: TransactionAttachmentUpload) async throws -> TransactionAttachment {
        let endpoint = Endpoint<TransactionAttachment>(.post, upload.path)
        var (request, _) = try makeRequest(for: endpoint)
        request.httpBody = upload.data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(upload.encodedFilename, forHTTPHeaderField: TransactionAttachmentUpload.filenameHeader)
        let data = try await perform(request)
        do {
            return try endpoint.decodeBody(data, JSONCoding.makeDecoder())
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Downloads an attachment's bytes from `GET /attachments/:id/file`.
    public func downloadTransactionAttachment(id: String) async throws -> Data {
        let endpoint = Endpoint<EmptyResponse>(.get, "/attachments/\(id)/file")
        var (request, _) = try makeRequest(for: endpoint)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.network(error)
        } catch {
            throw APIError.network(URLError(.unknown))
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("The response wasn't HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(statusCode: http.statusCode, data: data)
        }
        return data
    }
}
