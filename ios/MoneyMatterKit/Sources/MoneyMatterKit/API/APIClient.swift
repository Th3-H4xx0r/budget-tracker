import Foundation

/// Supplies the bearer token for each request. Read on every call, so a sign-in or
/// sign-out takes effect without rebuilding the client.
public protocol AccessTokenProviding: Sendable {
    func accessToken() -> String?
}

/// A decoded value plus the response metadata some auth calls need (`set-auth-token`).
public struct APIResponse<Value: Sendable>: Sendable {
    public let value: Value
    public let statusCode: Int
    private let headers: [String: String]

    init(value: Value, statusCode: Int, headers: [String: String]) {
        self.value = value
        self.statusCode = statusCode
        self.headers = headers
    }

    /// Case-insensitive header lookup.
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// Talks to one server's `/api/v1`.
///
/// - The default `URLSession` never stores or sends cookies, so better-auth's origin check
///   (which only applies to requests carrying a `Cookie`) never trips on the bearer flow.
/// - Every request sends `Accept-Language`, and `Authorization: Bearer` when a token exists.
///   `/auth/*` writes also send `Origin: <server origin>`.
/// - Every failure is thrown as `APIError`.
public struct APIClient: Sendable {
    public let server: ServerEndpoint
    private let tokenProvider: (any AccessTokenProviding)?
    private let session: URLSession
    private let acceptLanguage: @Sendable () -> String
    private let onUnauthenticated: (@Sendable (_ rejectedToken: String) -> Void)?
    private let ceremonyConfiguration: @Sendable () -> URLSessionConfiguration

    /// - Parameters:
    ///   - onUnauthenticated: Called with the token a request carried when it got a 401, so the
    ///     app can end that session. A late reply for a token that was already replaced can be
    ///     told apart by comparing tokens. Not called for requests without a token, like sign-in.
    ///   - ceremonyConfiguration: The base configuration for `withEphemeralCookieJar()`.
    public init(
        server: ServerEndpoint,
        tokenProvider: (any AccessTokenProviding)? = nil,
        session: URLSession = APIClient.makeURLSession(),
        acceptLanguage: @escaping @Sendable () -> String = APIClient.preferredLanguage,
        onUnauthenticated: (@Sendable (_ rejectedToken: String) -> Void)? = nil,
        ceremonyConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }
    ) {
        self.server = server
        self.tokenProvider = tokenProvider
        self.session = session
        self.acceptLanguage = acceptLanguage
        self.onUnauthenticated = onUnauthenticated
        self.ceremonyConfiguration = ceremonyConfiguration
    }

    @Sendable public static func preferredLanguage() -> String {
        Locale.preferredLanguages.first ?? "en"
    }

    /// An ephemeral session that never stores, sends, or accepts cookies.
    public static func makeURLSession(configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// A client with its own in-memory cookie jar and no bearer token, for a single passkey
    /// ceremony: the challenge lives in a signed cookie between the two calls.
    /// Call `finishAndInvalidate()` when the ceremony ends.
    public func withEphemeralCookieJar() -> APIClient {
        let configuration = ceremonyConfiguration()
        configuration.httpCookieStorage = HTTPCookieStorage()
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.urlCache = nil
        return APIClient(
            server: server,
            tokenProvider: nil,
            session: URLSession(configuration: configuration),
            acceptLanguage: acceptLanguage,
            onUnauthenticated: nil,
            ceremonyConfiguration: ceremonyConfiguration
        )
    }

    /// The same client without a bearer token, so a probe can't affect the stored session.
    func withoutToken() -> APIClient {
        APIClient(
            server: server,
            tokenProvider: nil,
            session: session,
            acceptLanguage: acceptLanguage,
            onUnauthenticated: nil,
            ceremonyConfiguration: ceremonyConfiguration
        )
    }

    public func finishAndInvalidate() {
        session.finishTasksAndInvalidate()
    }

    var sessionConfiguration: URLSessionConfiguration { session.configuration }

    public func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        try await response(for: endpoint).value
    }

    public func response<Response>(for endpoint: Endpoint<Response>) async throws -> APIResponse<Response> {
        let (request, sentToken) = try makeRequest(for: endpoint)

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
            let error = Self.mapError(statusCode: http.statusCode, data: data)
            if error.isUnauthenticated, let sentToken { onUnauthenticated?(sentToken) }
            throw error
        }

        let value: Response
        do {
            value = try endpoint.decodeBody(data, JSONCoding.makeDecoder())
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(String(describing: error))
        }
        return APIResponse(value: value, statusCode: http.statusCode, headers: Self.headers(of: http))
    }

    /// Builds the request, also returning the bearer token it carries, if any.
    func makeRequest<Response>(for endpoint: Endpoint<Response>) throws -> (URLRequest, String?) {
        let url = server.apiBaseURL.appending(path: endpoint.path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.network(URLError(.badURL))
        }
        components.percentEncodedQuery = QueryBuilder.percentEncodedQuery(endpoint.queryItems)
        guard let finalURL = components.url else { throw APIError.network(URLError(.badURL)) }

        var request = URLRequest(url: finalURL)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(acceptLanguage(), forHTTPHeaderField: "Accept-Language")

        if let body = endpoint.body {
            do {
                request.httpBody = try JSONCoding.makeEncoder().encode(body)
            } catch {
                throw APIError.decoding("Couldn't encode the request: \(error)")
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if endpoint.sendsOrigin {
            request.setValue(server.originString, forHTTPHeaderField: "Origin")
        }

        var sentToken: String?
        if let token = tokenProvider?.accessToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            sentToken = token
        }
        return (request, sentToken)
    }

    static func mapError(statusCode: Int, data: Data) -> APIError {
        let decoder = JSONDecoder()
        let payload = (try? decoder.decode(ErrorEnvelope.self, from: data))?.response
            ?? (try? decoder.decode(ErrorPayload.self, from: data))
        let message = payload?.message

        switch statusCode {
        case 401:
            return .unauthenticated(message: message)
        case 402:
            return .planRequired(message: message)
        case 404:
            return .notFound(message: message)
        case 422:
            return .validation(message: message ?? "", issues: payload?.validationErrors ?? [], code: payload?.code)
        case 423:
            return .baseCurrencyChangeInProgress(message: message)
        default:
            return .server(statusCode: statusCode, code: payload?.code, message: message)
        }
    }

    private static func headers(of response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String else { continue }
            headers[key.lowercased()] = value as? String ?? String(describing: value)
        }
        return headers
    }
}
