import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// How a route wraps its body.
public enum ResponseFormat: Sendable {
    /// App routes: `{status, response}`.
    case envelope
    /// better-auth routes under `/auth/*`: the bare JSON value.
    case bare
    /// Routes whose wrapping isn't pinned down yet; the body is inspected.
    case envelopeOrBare
}

/// One typed API call: everything `APIClient` needs to build the request and decode
/// the reply. Build them with the factories on `Endpoints`.
public struct Endpoint<Response: Sendable>: Sendable {
    public let method: HTTPMethod
    /// Relative to `/api/v1`, with a leading slash.
    public let path: String
    public let queryItems: [URLQueryItem]
    public let body: (any Encodable & Sendable)?
    public let format: ResponseFormat
    let decodeBody: @Sendable (Data, JSONDecoder) throws -> Response

    /// better-auth routes, which get the `Origin` header on writes.
    public var isAuthRoute: Bool { path.hasPrefix("/auth/") }

    public var sendsOrigin: Bool { isAuthRoute && method != .get }

    init(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem],
        body: (any Encodable & Sendable)?,
        format: ResponseFormat,
        decodeBody: @escaping @Sendable (Data, JSONDecoder) throws -> Response
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
        self.format = format
        self.decodeBody = decodeBody
    }

    /// Transforms the decoded value, e.g. to unwrap `{transactionCount}` into an `Int`.
    public func map<NewResponse: Sendable>(
        _ transform: @escaping @Sendable (Response) throws -> NewResponse
    ) -> Endpoint<NewResponse> {
        let decode = decodeBody
        return Endpoint<NewResponse>(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body,
            format: format,
            decodeBody: { data, decoder in try transform(decode(data, decoder)) }
        )
    }
}

extension Endpoint where Response: Decodable {
    public init(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        format: ResponseFormat = .envelope
    ) {
        self.init(
            method: method,
            path: path,
            queryItems: query,
            body: body,
            format: format,
            decodeBody: { data, decoder in
                try ResponseDecoding.decode(Response.self, from: data, format: format, decoder: decoder)
            }
        )
    }
}

enum ResponseDecoding {
    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        format: ResponseFormat,
        decoder: JSONDecoder
    ) throws -> Value {
        if isBlank(data), let missing = Value.self as? any MissingResponseRepresentable.Type,
           let placeholder = missing.missingResponse as? Value {
            return placeholder
        }
        switch format {
        case .envelope:
            return try decoder.decode(SuccessEnvelope<Value>.self, from: data).value
        case .bare:
            return try decoder.decode(Value.self, from: data)
        case .envelopeOrBare:
            if (try? decoder.decode(EnvelopeProbe.self, from: data))?.status != nil {
                return try decoder.decode(SuccessEnvelope<Value>.self, from: data).value
            }
            return try decoder.decode(Value.self, from: data)
        }
    }

    private static func isBlank(_ data: Data) -> Bool {
        data.allSatisfy { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
    }
}
