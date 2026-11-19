import Foundation
import Synchronization
import Testing
@testable import MoneyMatterKit

@Suite("Cloudflare Access")
struct CloudflareAccessTests {
    private static let credentials = CloudflareAccessCredentials(clientId: "abc.access", clientSecret: "s3cret")!

    private static let unauthorizedJSON =
        #"{"status":"error","response":{"message":"Unauthorized","code":"UNAUTHENTICATED"}}"#

    @Test("Credentials trim and reject blanks")
    func credentialsTrimAndRejectBlanks() throws {
        let trimmed = try #require(CloudflareAccessCredentials(clientId: "  abc.access\n", clientSecret: " s3cret "))
        #expect(trimmed.clientId == "abc.access")
        #expect(trimmed.clientSecret == "s3cret")
        #expect(trimmed.headers == ["CF-Access-Client-Id": "abc.access", "CF-Access-Client-Secret": "s3cret"])
        #expect(CloudflareAccessCredentials(clientId: "  ", clientSecret: "s3cret") == nil)
        #expect(CloudflareAccessCredentials(clientId: "abc.access", clientSecret: "\n") == nil)
    }

    @Test("Sends Cloudflare headers and still decodes a normal response")
    func sendsHeadersAndDecodes() async throws {
        let server = URLProtocolStub.register { request in
            guard request.header("CF-Access-Client-Id") == "abc.access",
                  request.header("CF-Access-Client-Secret") == "s3cret"
            else { return .json("{}", status: 500) }
            return .fixture("accounts")
        }
        let client = APIClient.stubbed(server: server, token: "t", cloudflareAccess: FixedCloudflareAccess(credentials: Self.credentials))

        let accounts = try await client.send(Endpoints.accounts())

        #expect(accounts.count == 3)
        let request = try #require(URLProtocolStub.requests(for: server).first)
        #expect(request.header("Authorization") == "Bearer t")
    }

    @Test("Sends no Cloudflare headers without credentials")
    func sendsNoHeadersWithoutCredentials() async throws {
        let server = URLProtocolStub.register { _ in .fixture("accounts") }
        let client = APIClient.stubbed(server: server, cloudflareAccess: FixedCloudflareAccess(credentials: nil))

        _ = try await client.send(Endpoints.accounts())

        let request = try #require(URLProtocolStub.requests(for: server).first)
        #expect(request.header("CF-Access-Client-Id") == nil)
        #expect(request.header("CF-Access-Client-Secret") == nil)
    }

    @Test("withEphemeralCookieJar keeps Cloudflare credentials")
    func ephemeralCookieJarKeepsCredentials() async throws {
        let server = URLProtocolStub.register { _ in .fixture("accounts") }
        let client = APIClient.stubbed(server: server, token: "t", cloudflareAccess: FixedCloudflareAccess(credentials: Self.credentials))
            .withEphemeralCookieJar()
        defer { client.finishAndInvalidate() }

        _ = try await client.send(Endpoints.accounts())

        let request = try #require(URLProtocolStub.requests(for: server).first)
        #expect(request.header("CF-Access-Client-Id") == "abc.access")
        #expect(request.header("CF-Access-Client-Secret") == "s3cret")
        #expect(request.header("Authorization") == nil)
    }

    @Test("Maps a redirect to cloudflareaccess.com to cloudflareBlocked without calling onUnauthenticated")
    func redirectToCloudflareAccess() async {
        let calls = Mutex(0)
        let server = URLProtocolStub.register { _ in
            StubResponse(statusCode: 302, headers: ["Location": "https://team.cloudflareaccess.com/cdn-cgi/access/login/x"])
        }
        let client = APIClient.stubbed(server: server, token: "t") { _ in
            calls.withLock { $0 += 1 }
        }

        await #expect(throws: APIError.cloudflareBlocked) {
            _ = try await client.send(Endpoints.accounts())
        }
        #expect(calls.withLock { $0 } == 0)
    }

    @Test("Maps an HTML 403 with cf-ray to cloudflareBlocked")
    func htmlForbiddenWithRay() async {
        let calls = Mutex(0)
        let server = URLProtocolStub.register { _ in
            StubResponse(
                statusCode: 403,
                headers: ["Content-Type": "text/html; charset=utf-8", "cf-ray": "8a1b2c3d4e5f-AMS"],
                body: Data("<html>Forbidden</html>".utf8)
            )
        }
        let client = APIClient.stubbed(server: server, token: "t") { _ in
            calls.withLock { $0 += 1 }
        }

        await #expect(throws: APIError.cloudflareBlocked) {
            _ = try await client.send(Endpoints.accounts())
        }
        #expect(calls.withLock { $0 } == 0)
    }

    @Test("Keeps an app JSON 401 as unauthenticated, even with cf-ray")
    func appJSONUnauthorizedStaysUnauthenticated() async {
        let rejected = Mutex<[String]>([])
        let server = URLProtocolStub.register { _ in
            .json(Self.unauthorizedJSON, status: 401, headers: ["cf-ray": "8a1b2c3d4e5f-AMS"])
        }
        let client = APIClient.stubbed(server: server, token: "t") { token in
            rejected.withLock { $0.append(token) }
        }

        await #expect(throws: APIError.unauthenticated(message: "Unauthorized")) {
            _ = try await client.send(Endpoints.accounts())
        }
        #expect(rejected.withLock { $0 } == ["t"])
    }

    @Test("cloudflareAccessHeaders is empty for another origin")
    func headersEmptyForAnotherOrigin() throws {
        let server = try ServerEndpoint(validating: "https://budget.example.com")
        let client = APIClient.stubbed(server: server, cloudflareAccess: FixedCloudflareAccess(credentials: Self.credentials))

        #expect(client.cloudflareAccessHeaders(for: try #require(URL(string: "https://budget.example.com/api/v1/x"))) == Self.credentials.headers)
        #expect(client.cloudflareAccessHeaders(for: try #require(URL(string: "https://budget.example.com:443/x"))) == Self.credentials.headers)
        #expect(client.cloudflareAccessHeaders(for: try #require(URL(string: "https://evil.example.com/x"))).isEmpty)
        #expect(client.cloudflareAccessHeaders(for: try #require(URL(string: "http://budget.example.com/x"))).isEmpty)
        #expect(client.cloudflareAccessHeaders(for: try #require(URL(string: "https://budget.example.com:8443/x"))).isEmpty)
    }

    @Test("Credentials description redacts the secret")
    func credentialsRedacted() {
        for text in [String(describing: Self.credentials), String(reflecting: Self.credentials), "\(Self.credentials)"] {
            #expect(!text.contains("s3cret"))
            #expect(text.contains("abc.access"))
            #expect(text.contains("<redacted>"))
        }
    }

    @Test("Credentials decoding trims and rejects blanks")
    func credentialsDecodingValidates() throws {
        let trimmed = try JSONDecoder().decode(
            CloudflareAccessCredentials.self,
            from: Data(#"{"clientId":" abc.access ","clientSecret":" s3cret\n"}"#.utf8)
        )
        #expect(trimmed == Self.credentials)

        for json in [
            #"{"clientId":"  ","clientSecret":"s3cret"}"#,
            #"{"clientId":"abc.access","clientSecret":""}"#,
        ] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(CloudflareAccessCredentials.self, from: Data(json.utf8))
            }
        }
        let roundTripped = try JSONDecoder().decode(CloudflareAccessCredentials.self, from: JSONEncoder().encode(Self.credentials))
        #expect(roundTripped == Self.credentials)
    }

    @Test("Maps a 401 with an empty body and cf-ray to unauthenticated")
    func emptyUnauthorizedWithRayStaysUnauthenticated() async {
        let server = URLProtocolStub.register { _ in
            StubResponse(statusCode: 401, headers: ["cf-ray": "8a1b2c3d4e5f-AMS"])
        }
        let client = APIClient.stubbed(server: server, token: "t")

        await #expect(throws: APIError.unauthenticated(message: nil)) {
            _ = try await client.send(Endpoints.accounts())
        }
    }

    @Test("An HTML 403 without cf-ray is not cloudflareBlocked")
    func htmlForbiddenWithoutRay() async {
        let server = URLProtocolStub.register { _ in
            StubResponse(statusCode: 403, headers: ["Content-Type": "text/html"], body: Data("<html>Forbidden</html>".utf8))
        }
        let client = APIClient.stubbed(server: server, token: "t")

        do {
            _ = try await client.send(Endpoints.accounts())
            Issue.record("Expected an error")
        } catch {
            #expect(error as? APIError != .cloudflareBlocked)
        }
    }

    @Test("Sends no Cloudflare headers to an http server")
    func noHeadersOverCleartext() throws {
        let server = try ServerEndpoint(validating: "http://localhost:8100")
        let client = APIClient.stubbed(server: server, cloudflareAccess: FixedCloudflareAccess(credentials: Self.credentials))

        #expect(client.cloudflareAccessHeaders(for: try #require(URL(string: "http://localhost:8100/api/v1/x"))).isEmpty)
    }

    @Test("Sends no Cloudflare headers when the URL's userinfo imitates the server")
    func noHeadersForUserinfoTrick() throws {
        let server = try ServerEndpoint(validating: "https://budget.example.com")
        let client = APIClient.stubbed(server: server, cloudflareAccess: FixedCloudflareAccess(credentials: Self.credentials))

        #expect(client.cloudflareAccessHeaders(for: try #require(URL(string: "https://budget.example.com@evil.com/x"))).isEmpty)
    }

    @Test("Matches the server host case-insensitively")
    func headersMatchUppercaseHost() throws {
        let server = try ServerEndpoint(validating: "https://budget.example.com")
        let client = APIClient.stubbed(server: server, cloudflareAccess: FixedCloudflareAccess(credentials: Self.credentials))

        #expect(client.cloudflareAccessHeaders(for: try #require(URL(string: "https://BUDGET.Example.com/x"))) == Self.credentials.headers)
    }

    private static func redirect(to target: String) throws -> URLRequest {
        var request = URLRequest(url: try #require(URL(string: target)))
        request.setValue("abc.access", forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue("s3cret", forHTTPHeaderField: "CF-Access-Client-Secret")
        request.setValue("Bearer t", forHTTPHeaderField: "Authorization")
        request.setValue("uk-UA", forHTTPHeaderField: "Accept-Language")
        return request
    }

    private static func expectStripped(_ request: URLRequest?) {
        #expect(request != nil)
        #expect(request?.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(request?.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
        #expect(request?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request?.value(forHTTPHeaderField: "Accept-Language") == "uk-UA")
    }

    @Test("A same-origin redirect keeps credentials")
    func sameOriginRedirectKeepsHeaders() throws {
        let original = URL(string: "https://budget.example.com/api/v1/x")
        let followed = CloudflareRedirectGuard.redirectedRequest(try Self.redirect(to: "https://BUDGET.example.com:443/other"), original: original)

        #expect(followed?.value(forHTTPHeaderField: "CF-Access-Client-Id") == "abc.access")
        #expect(followed?.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "s3cret")
        #expect(followed?.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }

    @Test("A redirect to another host strips credentials")
    func otherHostRedirectStripsHeaders() throws {
        let original = URL(string: "https://budget.example.com/api/v1/x")
        Self.expectStripped(CloudflareRedirectGuard.redirectedRequest(try Self.redirect(to: "https://evil.example.com/x"), original: original))
    }

    @Test("A redirect from https to http on the same host strips credentials")
    func downgradeRedirectStripsHeaders() throws {
        let original = URL(string: "https://budget.example.com/api/v1/x")
        Self.expectStripped(CloudflareRedirectGuard.redirectedRequest(try Self.redirect(to: "http://budget.example.com/x"), original: original))
    }

    @Test("A redirect to another port strips credentials")
    func otherPortRedirectStripsHeaders() throws {
        let original = URL(string: "https://budget.example.com/api/v1/x")
        Self.expectStripped(CloudflareRedirectGuard.redirectedRequest(try Self.redirect(to: "https://budget.example.com:8443/x"), original: original))
    }

    @Test("A redirect without a known original URL strips credentials")
    func unknownOriginRedirectStripsHeaders() throws {
        Self.expectStripped(CloudflareRedirectGuard.redirectedRequest(try Self.redirect(to: "https://budget.example.com/x"), original: nil))
    }

    @Test("A redirect to cloudflareaccess.com is declined")
    func cloudflareAccessRedirectDeclined() throws {
        let original = URL(string: "https://budget.example.com/api/v1/x")
        #expect(CloudflareRedirectGuard.redirectedRequest(try Self.redirect(to: "https://team.cloudflareaccess.com/login"), original: original) == nil)
    }

    @Test("Parses a valid setup payload")
    func parsesValidPayload() throws {
        let payload = try CloudflareAccessSetupPayload.parse(
            #"{"v":1,"server":"https://budget.example.com","cfClientId":" abc.access ","cfClientSecret":"s3cret"}"#
        )

        #expect(payload.server.originString == "https://budget.example.com")
        #expect(payload.credentials == Self.credentials)
    }

    @Test("Rejects an http server")
    func rejectsHTTPServer() {
        for server in ["http://budget.example.com", "http://localhost:8100"] {
            let text = #"{"v":1,"server":"\#(server)","cfClientId":"abc.access","cfClientSecret":"s3cret"}"#
            #expect(throws: CloudflareAccessSetupPayloadError.insecureServer) {
                try CloudflareAccessSetupPayload.parse(text)
            }
        }
    }

    @Test("Rejects malformed input")
    func rejectsMalformed() {
        for text in [
            "not json",
            "[]",
            #"{"v":1,"server":"https://budget.example.com""#,
            #"{"server":"https://budget.example.com","cfClientId":"a","cfClientSecret":"b"}"#,
            #"{"v":1,"cfClientId":"a","cfClientSecret":"b"}"#,
            #"{"v":1,"server":"","cfClientId":"a","cfClientSecret":"b"}"#,
        ] {
            #expect(throws: CloudflareAccessSetupPayloadError.malformed) {
                try CloudflareAccessSetupPayload.parse(text)
            }
        }
    }

    @Test("Rejects a missing secret")
    func rejectsMissingSecret() {
        for text in [
            #"{"v":1,"server":"https://budget.example.com","cfClientId":"abc.access"}"#,
            #"{"v":1,"server":"https://budget.example.com","cfClientId":"abc.access","cfClientSecret":"  "}"#,
            #"{"v":1,"server":"https://budget.example.com","cfClientSecret":"s3cret"}"#,
        ] {
            #expect(throws: CloudflareAccessSetupPayloadError.missingCredentials) {
                try CloudflareAccessSetupPayload.parse(text)
            }
        }
    }

    @Test("Rejects an unsupported version")
    func rejectsUnsupportedVersion() {
        let text = #"{"v":2,"server":"https://budget.example.com","cfClientId":"abc.access","cfClientSecret":"s3cret"}"#
        #expect(throws: CloudflareAccessSetupPayloadError.unsupportedVersion) {
            try CloudflareAccessSetupPayload.parse(text)
        }
    }
}
