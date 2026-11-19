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

/// Per-task delegate that declines redirects to Cloudflare Access's login host and strips
/// credentials from redirects that leave the original request's origin. URLSession copies custom
/// headers onto redirected requests, so `CF-Access-Client-Secret` would otherwise follow them.
/// Passed per task (not as a session delegate), so a session never retains it.
final class CloudflareRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private static let credentialHeaders = [
        CloudflareAccessCredentials.clientIdHeader,
        CloudflareAccessCredentials.clientSecretHeader,
        "Authorization",
    ]

    static func isCloudflareAccessHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "cloudflareaccess.com" || host.hasSuffix(".cloudflareaccess.com")
    }

    /// The request to follow: `nil` for Cloudflare Access's login host, otherwise `new`, without
    /// credential headers unless it stays on `original`'s scheme, host, and port.
    static func redirectedRequest(_ new: URLRequest, original: URL?) -> URLRequest? {
        guard let url = new.url else { return nil }
        if let host = url.host(), isCloudflareAccessHost(host) { return nil }
        var request = new
        let sameOrigin = original.flatMap(APIClient.origin(of:)).map { $0 == APIClient.origin(of: url) } ?? false
        if !sameOrigin {
            for header in credentialHeaders { request.setValue(nil, forHTTPHeaderField: header) }
        }
        return request
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(Self.redirectedRequest(request, original: task.originalRequest?.url))
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
    private let cloudflareAccess: (any CloudflareAccessProviding)?
    private let session: URLSession
    private let acceptLanguage: @Sendable () -> String
    private let onUnauthenticated: (@Sendable (_ rejectedToken: String) -> Void)?
    private let ceremonyConfiguration: @Sendable () -> URLSessionConfiguration

    /// - Parameters:
    ///   - onUnauthenticated: Called with the token a request carried when it got a 401, so the
    ///     app can end that session. A late reply for a token that was already replaced can be
    ///     told apart by comparing tokens. Not called for requests without a token, like sign-in.
    ///   - ceremonyConfiguration: The base configuration for `withEphemeralCookieJar()`.
    ///   - cloudflareAccess: The Cloudflare Access token, sent only to `server`'s origin.
    public init(
        server: ServerEndpoint,
        tokenProvider: (any AccessTokenProviding)? = nil,
        session: URLSession = APIClient.makeURLSession(),
        acceptLanguage: @escaping @Sendable () -> String = APIClient.preferredLanguage,
        onUnauthenticated: (@Sendable (_ rejectedToken: String) -> Void)? = nil,
        ceremonyConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral },
        cloudflareAccess: (any CloudflareAccessProviding)? = nil
    ) {
        self.server = server
        self.cloudflareAccess = cloudflareAccess
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
        return makeSession(configuration: configuration)
    }

    static func makeSession(configuration: URLSessionConfiguration) -> URLSession {
        URLSession(configuration: configuration)
    }

    /// Sends `request` with the redirect guard attached to the task, so a redirect to Cloudflare
    /// Access reaches the caller as a response and credentials never follow a redirect off-origin.
    static func perform(_ request: URLRequest, on session: URLSession) async throws -> (Data, URLResponse) {
        try await session.data(for: request, delegate: CloudflareRedirectGuard())
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
            session: Self.makeSession(configuration: configuration),
            acceptLanguage: acceptLanguage,
            onUnauthenticated: nil,
            ceremonyConfiguration: ceremonyConfiguration,
            cloudflareAccess: cloudflareAccess
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
            ceremonyConfiguration: ceremonyConfiguration,
            cloudflareAccess: cloudflareAccess
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
            (data, urlResponse) = try await Self.perform(request, on: session)
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
            if let rejection = Self.cloudflareRejection(http) { throw rejection }
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
        for (name, value) in cloudflareAccessHeaders(for: finalURL) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return (request, sentToken)
    }

    /// The Cloudflare Access headers for `url`: empty unless a token exists, `url` is https, and
    /// it has the server's scheme, host, and port. The secret never travels in cleartext.
    public func cloudflareAccessHeaders(for url: URL) -> [String: String] {
        guard url.scheme?.lowercased() == "https",
              let credentials = cloudflareAccess?.cloudflareAccessCredentials(),
              Self.origin(of: url) == Self.origin(of: server.origin)
        else { return [:] }
        return credentials.headers
    }

    static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased() else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }

    /// `.cloudflareBlocked` when Cloudflare Access answered instead of the app: a redirect to
    /// its login host, or a 401/403 that is an HTML page and carries `cf-ray`.
    static func cloudflareRejection(_ response: HTTPURLResponse) -> APIError? {
        switch response.statusCode {
        case 300..<400:
            guard let location = response.value(forHTTPHeaderField: "Location"),
                  let host = URL(string: location, relativeTo: response.url)?.host(),
                  CloudflareRedirectGuard.isCloudflareAccessHost(host)
            else { return nil }
            return .cloudflareBlocked
        case 401, 403:
            let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            guard contentType.contains("text/html"), response.value(forHTTPHeaderField: "cf-ray") != nil else { return nil }
            return .cloudflareBlocked
        default:
            return nil
        }
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
