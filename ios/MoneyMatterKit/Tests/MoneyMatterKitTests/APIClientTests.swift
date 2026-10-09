import Foundation
import Synchronization
import Testing
@testable import MoneyMatterKit

@Suite("APIClient")
struct APIClientTests {
    @Test("Sends bearer, Accept-Language, and Accept headers, and unwraps the envelope")
    func headersAndEnvelope() async throws {
        let server = URLProtocolStub.register { _ in .fixture("accounts") }
        let client = APIClient.stubbed(server: server, token: "signed.token")

        let accounts = try await client.send(Endpoints.accounts())

        #expect(accounts.count == 3)
        let request = try #require(URLProtocolStub.requests(for: server).first)
        #expect(request.url.path() == "/api/v1/accounts")
        #expect(request.method == "GET")
        #expect(request.header("Authorization") == "Bearer signed.token")
        #expect(request.header("Accept-Language") == "uk-UA")
        #expect(request.header("Accept") == "application/json")
        #expect(request.header("Origin") == nil)
        #expect(request.header("Cookie") == nil)
    }

    @Test("Sends no Authorization header without a token")
    func noToken() async throws {
        let server = URLProtocolStub.register { _ in .fixture("signups-open") }
        let client = APIClient.stubbed(server: server)

        let open = try await client.send(Endpoints.signupsOpen())

        #expect(open)
        let request = try #require(URLProtocolStub.requests(for: server).first)
        #expect(request.header("Authorization") == nil)
        #expect(request.url.path() == "/api/v1/auth/signups-open")
        // GETs under /auth don't need an Origin.
        #expect(request.header("Origin") == nil)
    }

    @Test("Auth writes carry the server Origin and a JSON body")
    func originOnAuthWrites() async throws {
        let server = URLProtocolStub.register { _ in
            .json(#"{"redirect":false,"token":"raw","user":{"id":"u1","email":"a@b.c"}}"#, headers: ["set-auth-token": "signed.abc"])
        }
        let client = APIClient.stubbed(server: server)

        let token = try await client.signIn(email: "a@b.c", password: "hunter22")

        #expect(token == "signed.abc")
        let request = try #require(URLProtocolStub.requests(for: server).first)
        #expect(request.method == "POST")
        #expect(request.header("Origin") == server.originString)
        #expect(request.header("Content-Type") == "application/json")
        #expect(request.jsonBody?["email"] as? String == "a@b.c")
        #expect(request.jsonBody?["password"] as? String == "hunter22")
    }

    @Test("App writes don't carry an Origin")
    func noOriginOnAppWrites() async throws {
        let server = URLProtocolStub.register { _ in .fixture("base-currency") }
        let client = APIClient.stubbed(server: server, token: "t")

        _ = try await client.send(Endpoints.setBaseCurrency(code: "EUR"))

        let request = try #require(URLProtocolStub.requests(for: server).first)
        #expect(request.header("Origin") == nil)
        #expect(request.jsonBody?["currencyCode"] as? String == "EUR")
    }

    @Test("Sign-in without a set-auth-token header means the server is outdated")
    func missingTokenHeader() async {
        let server = URLProtocolStub.register { _ in .json(#"{"redirect":false,"token":"raw"}"#) }
        let client = APIClient.stubbed(server: server)

        await #expect(throws: APIError.serverOutdated) {
            _ = try await client.signIn(email: "a@b.c", password: "x")
        }
    }

    @Test("Passkey sign-in without a set-auth-token header means the server is outdated")
    func passkeyMissingTokenHeader() async {
        let server = URLProtocolStub.register { request in
            if request.url.path().hasSuffix("generate-authenticate-options") {
                return .fixture("passkey-options")
            }
            return .json(#"{"session":{"id":"s"},"user":{"id":"u"}}"#)
        }
        let client = APIClient.stubbed(server: server)

        await #expect(throws: APIError.serverOutdated) {
            _ = try await client.signInWithPasskey { _ in
                PasskeyAssertion(
                    credentialID: Data("cred-1".utf8),
                    clientDataJSON: Data("{}".utf8),
                    authenticatorData: Data([1, 2, 3]),
                    signature: Data([4, 5, 6]),
                    userHandle: nil
                )
            }
        }
    }

    @Test("The app-support probe passes on a 401 and sends no token")
    func appSupportOnCurrentServer() async throws {
        let calls = Mutex(0)
        let server = URLProtocolStub.register { _ in
            .json(#"{"status":"error","response":{"message":"Unauthorized","code":"UNAUTHENTICATED"}}"#, status: 401)
        }
        let client = APIClient.stubbed(server: server, token: "signed.saved") { _ in
            calls.withLock { $0 += 1 }
        }

        try await client.checkAppSupport()

        let request = try #require(URLProtocolStub.requests(for: server).first)
        #expect(request.url.path() == "/api/v1/transactions/review/summary")
        #expect(request.header("Authorization") == nil)
        #expect(calls.withLock { $0 } == 0)
    }

    @Test("The app-support probe maps an Express HTML 404 to .serverOutdated")
    func appSupportOnOutdatedServer() async {
        let server = URLProtocolStub.register { _ in
            StubResponse(
                statusCode: 404,
                headers: ["Content-Type": "text/html; charset=utf-8"],
                body: Data("<pre>Cannot GET /api/v1/transactions/review/summary</pre>".utf8)
            )
        }
        let client = APIClient.stubbed(server: server)

        await #expect(throws: APIError.serverOutdated) {
            try await client.checkAppSupport()
        }
    }

    @Test("The app-support probe keeps network errors as network errors")
    func appSupportNetworkError() async {
        let server = URLProtocolStub.register { _ in throw URLError(.cannotFindHost) }
        let client = APIClient.stubbed(server: server)

        let error = await #expect(throws: APIError.self) {
            try await client.checkAppSupport()
        }
        guard case .network(let urlError) = error else {
            Issue.record("Expected a network error")
            return
        }
        #expect(urlError.code == .cannotFindHost)
    }

    @Test("Sign-up returns verificationRequired when the body token is null")
    func signUpVerification() async throws {
        let server = URLProtocolStub.register { _ in .fixture("sign-up-verification") }
        let client = APIClient.stubbed(server: server)

        let result = try await client.signUp(name: "New", email: "new@example.com", password: "secret123")

        #expect(result == .verificationRequired)
        let request = try #require(URLProtocolStub.requests(for: server).first)
        #expect(request.jsonBody?["callbackURL"] as? String == "\(server.originString)/auth/callback")
        #expect(request.jsonBody?["name"] as? String == "New")
    }

    @Test("Sign-up returns the signed token from the header when a session starts")
    func signUpSignedIn() async throws {
        let server = URLProtocolStub.register { _ in
            .json(#"{"token":"raw","user":{"id":"u1"}}"#, headers: ["Set-Auth-Token": "signed.new"])
        }
        let client = APIClient.stubbed(server: server)

        let result = try await client.signUp(name: "New", email: "new@example.com", password: "secret123")

        #expect(result == .signedIn(token: "signed.new"))
    }

    @Test(
        "Maps error statuses to APIError",
        arguments: [
            (401, "error-better-auth", APIError.unauthenticated(message: "Invalid email or password")),
            (402, "error-plan-required", APIError.planRequired(message: "Your trial has ended")),
            (423, "error-locked", APIError.baseCurrencyChangeInProgress(message: "Base currency change in progress")),
            (404, "error-plan-required", APIError.notFound(message: "Your trial has ended")),
            (409, "error-conflict", APIError.server(statusCode: 409, code: "CATEGORY_HAS_TRANSACTIONS", message: "Category has transactions")),
            (403, "error-better-auth", APIError.server(statusCode: 403, code: "INVALID_EMAIL_OR_PASSWORD", message: "Invalid email or password")),
        ]
    )
    func errorMapping(status: Int, fixture: String, expected: APIError) async {
        let server = URLProtocolStub.register { _ in .fixture(fixture, status: status) }
        let client = APIClient.stubbed(server: server)

        await #expect(throws: expected) {
            _ = try await client.send(Endpoints.accounts())
        }
    }

    @Test("A 422 carries the message, code, and Zod issues")
    func validationError() async throws {
        let server = URLProtocolStub.register { _ in .fixture("error-validation", status: 422) }
        let client = APIClient.stubbed(server: server)

        let error = await #expect(throws: APIError.self) {
            _ = try await client.send(Endpoints.createTransaction(TransactionCreateRequest(amount: 1, transactionType: .expense, accountId: "a", categoryId: "c")))
        }
        guard case .validation(let message, let issues, let code) = error else {
            Issue.record("Expected a validation error, got \(String(describing: error))")
            return
        }
        #expect(message == "Validation failed")
        #expect(code == "VALIDATION_ERROR")
        #expect(issues.map(\.path) == [["body", "amount"], ["body", "splits", "0", "categoryId"]])
    }

    @Test("A non-JSON error body still maps by status")
    func errorWithoutBody() async {
        let server = URLProtocolStub.register { _ in StubResponse(statusCode: 503, body: Data("<html>down</html>".utf8)) }
        let client = APIClient.stubbed(server: server)

        await #expect(throws: APIError.server(statusCode: 503, code: nil, message: nil)) {
            _ = try await client.send(Endpoints.accounts())
        }
    }

    @Test("Transport failures become .network")
    func networkError() async {
        let server = URLProtocolStub.register { _ in throw URLError(.notConnectedToInternet) }
        let client = APIClient.stubbed(server: server)

        let error = await #expect(throws: APIError.self) {
            _ = try await client.send(Endpoints.accounts())
        }
        guard case .network(let urlError) = error else {
            Issue.record("Expected a network error")
            return
        }
        #expect(urlError.code == .notConnectedToInternet)
    }

    @Test("An unexpected body becomes .decoding")
    func decodingError() async {
        let server = URLProtocolStub.register { _ in .json(#"{"status":"success","response":{"unexpected":true}}"#) }
        let client = APIClient.stubbed(server: server)

        let error = await #expect(throws: APIError.self) {
            _ = try await client.send(Endpoints.accounts())
        }
        guard case .decoding = error else {
            Issue.record("Expected a decoding error")
            return
        }
    }

    @Test("A 401 on a request that carried a token reports the expired session")
    func unauthenticatedCallback() async {
        let rejected = Mutex<[String]>([])
        let server = URLProtocolStub.register { _ in .json(#"{"status":"error","response":{"message":"Unauthorized","code":"UNAUTHENTICATED"}}"#, status: 401) }
        let client = APIClient.stubbed(server: server, token: "expired") { token in
            rejected.withLock { $0.append(token) }
        }

        await #expect(throws: APIError.unauthenticated(message: "Unauthorized")) {
            _ = try await client.send(Endpoints.currentUser())
        }
        #expect(rejected.withLock { $0 } == ["expired"])
    }

    @Test("A 401 on a request without a token doesn't report an expired session")
    func unauthenticatedWithoutToken() async {
        let calls = Mutex(0)
        let server = URLProtocolStub.register { _ in .fixture("error-better-auth", status: 401) }
        let client = APIClient.stubbed(server: server) { _ in
            calls.withLock { $0 += 1 }
        }

        await #expect(throws: APIError.self) {
            _ = try await client.signIn(email: "a@b.c", password: "wrong")
        }
        #expect(calls.withLock { $0 } == 0)
    }

    @Test("The default session never stores or sends cookies")
    func cookieLessSession() {
        let session = APIClient.makeURLSession()
        #expect(session.configuration.httpCookieStorage == nil)
        #expect(session.configuration.httpShouldSetCookies == false)
        #expect(session.configuration.httpCookieAcceptPolicy == .never)
    }

    @Test("The passkey ceremony client keeps cookies, unlike the default client")
    func ceremonyCookieJar() {
        let server = URLProtocolStub.register { _ in .json("{}") }
        let ceremony = APIClient.stubbed(server: server).withEphemeralCookieJar()
        defer { ceremony.finishAndInvalidate() }
        #expect(ceremony.sessionConfiguration.httpShouldSetCookies)
        #expect(ceremony.sessionConfiguration.httpCookieStorage != nil)
        #expect(ceremony.sessionConfiguration.httpCookieAcceptPolicy == .always)
    }

    @Test("Passkey sign-in fetches options, asserts, and verifies with the server Origin")
    func passkeyCeremony() async throws {
        let server = URLProtocolStub.register { request in
            if request.url.path().hasSuffix("generate-authenticate-options") {
                return .fixture("passkey-options", headers: ["Set-Cookie": "better-auth-passkey=signed-challenge; Path=/; Secure; HttpOnly"])
            }
            return .json(#"{"session":{"id":"s"},"user":{"id":"u"}}"#, headers: ["set-auth-token": "signed.passkey"])
        }
        let client = APIClient.stubbed(server: server, token: "ignored")

        let token = try await client.signInWithPasskey { options in
            #expect(options.rpId == "budget.pkrishna.dev")
            return PasskeyAssertion(
                credentialID: Data("cred-1".utf8),
                clientDataJSON: Data("{}".utf8),
                authenticatorData: Data([1, 2, 3]),
                signature: Data([4, 5, 6]),
                userHandle: nil
            )
        }

        #expect(token == "signed.passkey")
        let requests = URLProtocolStub.requests(for: server)
        #expect(requests.count == 2)
        let verify = try #require(requests.last)
        #expect(verify.header("Origin") == server.originString)
        #expect(verify.header("Authorization") == nil)
        let credential = try #require(verify.jsonBody?["response"] as? [String: Any])
        #expect(credential["id"] as? String == "Y3JlZC0x")
        #expect(credential["rawId"] as? String == "Y3JlZC0x")
        #expect(credential["type"] as? String == "public-key")
        let assertion = try #require(credential["response"] as? [String: Any])
        #expect(assertion["authenticatorData"] as? String == "AQID")
        #expect(assertion["signature"] as? String == "BAUG")
    }
}
