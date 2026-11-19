import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("App updates")
struct AppUpdateTests {
    private static let installLink =
        "itms-services://?action=download-manifest&url=https%3A%2F%2Fx.dev%2Fota%2Fm%2Fios.5.99.abc.plist"

    private static func available(build: Int = 5) -> String {
        """
        {"status":"success","response":{"available":true,"platform":"ios","build":\(build),"version":"1.2",\
        "notes":"\\n- Faster\\n- Fixes\\n","commit":null,"size":1234,"uploadedAt":"2026-11-19T10:00:00.000Z",\
        "installUrl":"\(installLink)","sha256":"aa"}}
        """
    }

    private static let unavailable = """
        {"status":"success","response":{"available":false,"platform":"ios","build":null,"version":null,\
        "notes":null,"commit":null,"size":null,"uploadedAt":null,"installUrl":null,"sha256":null}}
        """

    @Test("Decodes an available offer")
    func decodesAvailable() async throws {
        let server = URLProtocolStub.register { _ in .json(Self.available()) }
        let client = APIClient.stubbed(server: server, token: "t")

        guard case .offer(let offer) = try await client.send(Endpoints.latestAppUpdate(installedBuild: 2)) else {
            Issue.record("expected an offer")
            return
        }

        #expect(offer.build == 5)
        #expect(offer.version == "1.2")
        #expect(offer.notes == "- Faster\n- Fixes")
        #expect(offer.size == 1234)
        #expect(offer.installURL.scheme == "itms-services")
    }

    @Test("An unavailable answer is no offer")
    func decodesUnavailable() async throws {
        let server = URLProtocolStub.register { _ in .json(Self.unavailable) }
        let client = APIClient.stubbed(server: server, token: "t")

        #expect(try await client.send(Endpoints.latestAppUpdate(installedBuild: 2)) == .upToDate)
    }

    @Test("A build that is not newer than the installed one is no offer")
    func notNewer() async throws {
        let server = URLProtocolStub.register { _ in .json(Self.available(build: 5)) }
        let client = APIClient.stubbed(server: server, token: "t")

        #expect(try await client.send(Endpoints.latestAppUpdate(installedBuild: 5)) == .upToDate)
        #expect(try await client.send(Endpoints.latestAppUpdate(installedBuild: 9)) == .upToDate)
    }

    @Test("An available answer without an install link is not installable")
    func missingLink() async throws {
        let body = #"{"status":"success","response":{"available":true,"build":5,"installUrl":null}}"#
        let server = URLProtocolStub.register { _ in .json(body) }
        let client = APIClient.stubbed(server: server, token: "t")

        #expect(try await client.send(Endpoints.latestAppUpdate(installedBuild: 1)) == .notInstallable)
    }

    @Test("Latest goes through APIClient with bearer and Cloudflare headers, platform and build")
    func latestRequest() async throws {
        let server = URLProtocolStub.register { _ in .json(Self.unavailable) }
        let cloudflare = FixedCloudflareAccess(credentials: CloudflareAccessCredentials(clientId: "id.access", clientSecret: "secret")!)
        let client = APIClient.stubbed(server: server, token: "signed.token", cloudflareAccess: cloudflare)

        _ = try await client.send(Endpoints.latestAppUpdate(installedBuild: 42))

        let request = try #require(URLProtocolStub.requests(for: server).first)
        #expect(request.method == "GET")
        #expect(request.url.path() == "/api/v1/app-updates/latest")
        #expect(request.query("platform") == "ios")
        #expect(request.query("build") == "42")
        #expect(request.header("Authorization") == "Bearer signed.token")
        #expect(request.header(CloudflareAccessCredentials.clientIdHeader) == "id.access")
        #expect(request.header(CloudflareAccessCredentials.clientSecretHeader) == "secret")
    }

    @Test("Install status sends the token and reads started")
    func installStatus() async throws {
        let server = URLProtocolStub.register { _ in .json(#"{"status":"success","response":{"started":true}}"#) }
        let client = APIClient.stubbed(server: server, token: "t")

        let started = try await client.send(Endpoints.appUpdateInstallStarted(token: "ios.5.99.abc"))

        #expect(started)
        let request = try #require(URLProtocolStub.requests(for: server).first)
        #expect(request.url.path() == "/api/v1/app-updates/install-status")
        #expect(request.query("token") == "ios.5.99.abc")
    }

    @Test("The install token is the manifest name inside the link")
    func installToken() {
        let offer = AppUpdateOffer(build: 5, version: "1.2", notes: "", installURL: URL(string: Self.installLink)!)
        #expect(offer.installToken == "ios.5.99.abc")

        let other = AppUpdateOffer(build: 5, version: "1.2", notes: "", installURL: URL(string: "itms-services://x")!)
        #expect(other.installToken == nil)
    }

    @Test("The card shows in front, and not for a build put off with Not Now")
    func shouldShow() {
        let offer = AppUpdateOffer(build: 5, version: "1.2", notes: "", installURL: URL(string: "itms-services://x")!)
        #expect(AppUpdateRules.shouldShow(offer, foreground: true, laterBuild: nil))
        #expect(!AppUpdateRules.shouldShow(offer, foreground: false, laterBuild: nil))
        #expect(!AppUpdateRules.shouldShow(offer, foreground: true, laterBuild: 5))
        #expect(AppUpdateRules.shouldShow(offer, foreground: true, laterBuild: 4))
        #expect(!AppUpdateRules.shouldShow(nil, foreground: true, laterBuild: nil))
    }
}
