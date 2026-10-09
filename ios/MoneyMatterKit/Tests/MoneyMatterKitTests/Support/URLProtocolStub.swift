import Foundation
import Synchronization
@testable import MoneyMatterKit

/// A canned HTTP reply.
struct StubResponse: Sendable {
    var statusCode: Int = 200
    var headers: [String: String] = [:]
    var body: Data = Data()

    static func json(_ string: String, status: Int = 200, headers: [String: String] = [:]) -> StubResponse {
        StubResponse(statusCode: status, headers: headers.merging(["Content-Type": "application/json"]) { $1 }, body: Data(string.utf8))
    }

    static func fixture(_ name: String, status: Int = 200, headers: [String: String] = [:]) -> StubResponse {
        StubResponse(statusCode: status, headers: headers.merging(["Content-Type": "application/json"]) { $1 }, body: Fixture.data(name))
    }
}

/// What the stub saw, with the body read back from the upload stream.
struct RecordedRequest: Sendable {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data?

    func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }

    var queryItems: [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    func query(_ name: String) -> String? {
        queryItems.first { $0.name == name }?.value
    }

    var jsonBody: [String: Any]? {
        guard let body else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

/// Routes requests by host, so parallel tests each get their own handler.
final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (RecordedRequest) throws -> StubResponse

    private static let handlers = Mutex<[String: Handler]>([:])
    private static let recorded = Mutex<[String: [RecordedRequest]]>([:])

    /// Registers a handler for a fresh host and returns a server on that host.
    static func register(_ handler: @escaping Handler) -> ServerEndpoint {
        let host = "stub-\(UUID().uuidString.lowercased()).local"
        handlers.withLock { $0[host] = handler }
        // A `.local` host may use plain HTTP, but HTTPS keeps the origin realistic.
        return try! ServerEndpoint(validating: "https://\(host)")
    }

    static func requests(for server: ServerEndpoint) -> [RecordedRequest] {
        recorded.withLock { $0[server.host] ?? [] }
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let recordedRequest = RecordedRequest(
            url: url,
            method: request.httpMethod ?? "GET",
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? request.httpBodyStream.map(Self.read)
        )
        Self.recorded.withLock { $0[host, default: []].append(recordedRequest) }

        guard let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }

        do {
            let stub = try handler(recordedRequest)
            let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

extension APIClient {
    /// A client wired to `URLProtocolStub` for `server`.
    static func stubbed(
        server: ServerEndpoint,
        token: String? = nil,
        onUnauthenticated: (@Sendable (String) -> Void)? = nil
    ) -> APIClient {
        APIClient(
            server: server,
            tokenProvider: token.map(FixedToken.init),
            session: APIClient.makeURLSession(configuration: URLProtocolStub.configuration()),
            acceptLanguage: { "uk-UA" },
            onUnauthenticated: onUnauthenticated,
            ceremonyConfiguration: { URLProtocolStub.configuration() }
        )
    }
}

struct FixedToken: AccessTokenProviding {
    let token: String
    func accessToken() -> String? { token }
}
