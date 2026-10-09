import Foundation

/// A binary body downloaded from the API, such as a backup zip.
public struct SettingsUploadDownload: Sendable {
    public let data: Data
    /// From `Content-Disposition`, when the server sends one.
    public let filename: String?

    public init(data: Data, filename: String?) {
        self.data = data
        self.filename = filename
    }
}

extension APIClient {
    /// Sends `endpoint` and returns the raw body instead of decoding JSON. Binary routes still
    /// answer errors with the JSON envelope, which is mapped to `APIError` like any other call.
    public func settingsDownload<Response>(
        _ endpoint: Endpoint<Response>,
        accept: String
    ) async throws -> SettingsUploadDownload {
        var (request, _) = try makeRequest(for: endpoint)
        request.setValue(accept, forHTTPHeaderField: "Accept")

        let session = URLSession(configuration: sessionConfiguration)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.network(error)
        } catch is CancellationError {
            throw APIError.network(URLError(.cancelled))
        } catch {
            throw APIError.network(URLError(.unknown))
        }

        guard let http = urlResponse as? HTTPURLResponse else {
            throw APIError.decoding("The response wasn't HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(statusCode: http.statusCode, data: data)
        }
        let disposition = http.value(forHTTPHeaderField: "Content-Disposition")
        return SettingsUploadDownload(data: data, filename: SettingsUploadFilename.parse(contentDisposition: disposition))
    }
}

/// Reads the filename out of a `Content-Disposition` header.
public enum SettingsUploadFilename {
    public static func parse(contentDisposition header: String?) -> String? {
        guard let header else { return nil }
        for part in header.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("filename*=") {
                let value = trimmed.dropFirst("filename*=".count)
                let encoded = value.split(separator: "'", omittingEmptySubsequences: false).last.map(String.init) ?? String(value)
                if let decoded = encoded.removingPercentEncoding, !decoded.isEmpty { return sanitized(decoded) }
            }
        }
        for part in header.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("filename=") {
                let value = trimmed.dropFirst("filename=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !value.isEmpty { return sanitized(value) }
            }
        }
        return nil
    }

    /// Keeps only the last path component, so a header can't point the file outside its folder.
    private static func sanitized(_ name: String) -> String? {
        let last = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? name
        return last.isEmpty || last == "." || last == ".." ? nil : last
    }
}
