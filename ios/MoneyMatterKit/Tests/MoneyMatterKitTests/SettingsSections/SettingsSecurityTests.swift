import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Settings security and preferences")
struct SettingsSecurityTests {
    private let server = try! ServerEndpoint(validating: "https://budget.example.com")

    private func decode<Value>(_ endpoint: Endpoint<Value>, _ json: String) throws -> Value {
        try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
    }

    private func request<Response>(_ endpoint: Endpoint<Response>) throws -> URLRequest {
        try APIClient(server: server).makeRequest(for: endpoint).0
    }

    private func body<Response>(_ endpoint: Endpoint<Response>) throws -> [String: Any] {
        let data = try #require(try request(endpoint).httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Decoding

    @Test("Linked accounts decode the provider, unknown providers stay readable")
    func linkedAccounts() throws {
        let accounts = try decode(Endpoints.settingsLinkedAccounts(), """
        [
          {"id":"a1","providerId":"credential","accountId":"u1","userId":"u1","createdAt":"2026-01-02T10:15:30.123Z","scopes":[]},
          {"id":"a2","providerId":"google","accountId":"g-123","userId":"u1","createdAt":"2026-02-02T10:15:30.000Z"},
          {"id":"a3","providerId":"apple","accountId":"x","userId":"u1"}
        ]
        """)
        #expect(accounts.map(\.provider) == [.credential, .google, .unknown("apple")])
        #expect(accounts[1].accountId == "g-123")
        #expect(accounts[0].createdAt == Date.iso("2026-01-02T10:15:30.123Z"))
        #expect(accounts[2].createdAt == nil)
    }

    @Test("Passkeys decode with optional name and metadata")
    func passkeys() throws {
        let passkeys = try decode(Endpoints.settingsPasskeys(), """
        [
          {"id":"pk1","name":"iPhone","publicKey":"abc","userId":"u1","credentialID":"cred","counter":0,
           "deviceType":"multiDevice","backedUp":true,"transports":"internal,hybrid","createdAt":"2026-03-01T00:00:00.000Z"},
          {"id":"pk2","name":null,"createdAt":null}
        ]
        """)
        #expect(passkeys.count == 2)
        #expect(passkeys[0].name == "iPhone")
        #expect(passkeys[0].backedUp == true)
        #expect(passkeys[0].createdAt == Date.iso("2026-03-01T00:00:00.000Z"))
        #expect(passkeys[1].name == nil)
        #expect(passkeys[1].createdAt == nil)
    }

    @Test("Sessions decode and describe their device")
    func sessions() throws {
        let sessions = try decode(Endpoints.settingsSessions(), """
        [
          {"id":"s1","token":"t1","userId":"u1","ipAddress":"10.0.0.1",
           "userAgent":"Mozilla/5.0 (Macintosh) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15",
           "createdAt":"2026-10-01T00:00:00.000Z","updatedAt":"2026-10-08T00:00:00.000Z","expiresAt":"2026-11-01T00:00:00.000Z"},
          {"id":"s2","token":"t2","userAgent":"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0) Chrome/120.0 Mobile"},
          {"id":"s3","token":"t3","userAgent":null}
        ]
        """)
        #expect(sessions.map(\.token) == ["t1", "t2", "t3"])
        #expect(sessions[0].clientName == "Safari 18")
        #expect(sessions[0].deviceKind == .computer)
        #expect(sessions[0].updatedAt == Date.iso("2026-10-08T00:00:00.000Z"))
        #expect(sessions[1].clientName == "Chrome 120")
        #expect(sessions[1].deviceKind == .phone)
        #expect(sessions[2].clientName == nil)
        #expect(sessions[2].deviceKind == .unknown)
    }

    @Test("Passkey creation options decode base64url fields")
    func creationOptions() throws {
        let challenge = Data([1, 2, 3, 250])
        let userID = Data("user-handle".utf8)
        let excluded = Data([9, 8, 7])
        let options = try decode(Endpoints.settingsPasskeyRegistrationOptions(), """
        {"challenge":"\(Base64URL.encode(challenge))","rp":{"name":"MoneyMatter","id":"budget.example.com"},
         "user":{"id":"\(Base64URL.encode(userID))","name":"pranav@example.com","displayName":"Pranav"},
         "pubKeyCredParams":[{"alg":-7,"type":"public-key"}],"timeout":60000,"attestation":"none",
         "excludeCredentials":[{"id":"\(Base64URL.encode(excluded))","type":"public-key","transports":["internal"]}],
         "authenticatorSelection":{"residentKey":"preferred","userVerification":"preferred","authenticatorAttachment":"platform"}}
        """)
        #expect(options.challenge == challenge)
        #expect(options.rpId == "budget.example.com")
        #expect(options.userID == userID)
        #expect(options.userName == "pranav@example.com")
        #expect(options.excludedCredentialIDs == [excluded])
        #expect(options.userVerification == "preferred")
    }

    @Test("User settings decode nested slices with web defaults")
    func preferences() throws {
        let full = try decode(Endpoints.settingsPreferences(), """
        {"status":"success","response":{
          "locale":"uk","includeCreditLimitInStats":true,"matchTransfersWithManualAccounts":true,
          "savingsCategoryIds":["c1","c2"],"hideZeroBalances":true,"currencyDisplay":"narrowSymbol",
          "sidebarSections":{"portfolios":false,"ventures":true,"vehicles":false,"loans":true},
          "accounts":{"defaultAccountId":"acc-1","showArchivedInDropdowns":true},
          "ui":{"transactionsList":{"hideUpcoming":true},
                "transactionForm":{"optionalFields":["location","bogus","externalUrl"],"mapPicker":true}},
          "dashboard":{"widgets":[]}
        }}
        """)
        #expect(full.locale == .ukrainian)
        #expect(full.includeCreditLimitInStats)
        #expect(full.matchTransfersWithManualAccounts)
        #expect(full.savingsCategoryIds == ["c1", "c2"])
        #expect(full.hideZeroBalances)
        #expect(full.currencyDisplay == .narrowSymbol)
        #expect(full.sidebarSections == SettingsSidebarSections(portfolios: false, ventures: true, vehicles: false, loans: true))
        #expect(full.defaultAccountId == "acc-1")
        #expect(full.showArchivedInDropdowns)
        #expect(full.hideUpcomingTransactions)
        #expect(full.optionalTransactionFields == [.location, .externalUrl])
        #expect(full.mapPicker)

        let empty = try decode(Endpoints.settingsPreferences(), #"{"status":"success","response":{"locale":"xx","currencyDisplay":"code"}}"#)
        #expect(empty.locale == nil)
        #expect(empty.currencyDisplay == .symbol)
        #expect(empty.sidebarSections == SettingsSidebarSections())
        #expect(!empty.hideZeroBalances)
        #expect(empty.defaultAccountId == nil)
        #expect(empty.optionalTransactionFields.isEmpty)
    }

    @Test("Locales map to server codes")
    func locales() {
        #expect(SettingsLocale.allCases.map(\.code) == ["en", "uk", "es", "id", "ru"])
        #expect(SettingsLocale(code: "es") == .spanish)
        #expect(SettingsLocale.spanish.isCommunityTranslated)
        #expect(!SettingsLocale.ukrainian.isCommunityTranslated)
    }

    // MARK: Requests

    @Test("Auth writes are bare POSTs to better-auth with the Origin header")
    func authWrites() throws {
        let unlink = try request(Endpoints.settingsUnlinkAccount(providerId: "google", accountId: "g-1"))
        #expect(unlink.url?.path == "/api/v1/auth/unlink-account")
        #expect(unlink.httpMethod == "POST")
        #expect(unlink.value(forHTTPHeaderField: "Origin") == "https://budget.example.com")
        let unlinkBody = try body(Endpoints.settingsUnlinkAccount(providerId: "google", accountId: "g-1"))
        #expect(unlinkBody["providerId"] as? String == "google")
        #expect(unlinkBody["accountId"] as? String == "g-1")

        #expect(try body(Endpoints.settingsDeletePasskey(id: "pk1"))["id"] as? String == "pk1")
        let rename = try body(Endpoints.settingsRenamePasskey(id: "pk1", name: "Work Mac"))
        #expect(rename["name"] as? String == "Work Mac")
        #expect(try body(Endpoints.settingsRevokeSession(token: "t2"))["token"] as? String == "t2")
        #expect(try request(Endpoints.settingsRevokeOtherSessions()).url?.path == "/api/v1/auth/revoke-other-sessions")

        let change = try body(Endpoints.settingsChangePassword(currentPassword: "old-pass", newPassword: "new-pass-123"))
        #expect(change["currentPassword"] as? String == "old-pass")
        #expect(change["newPassword"] as? String == "new-pass-123")
        #expect(change["revokeOtherSessions"] as? Bool == false)

        let set = try request(Endpoints.settingsSetPassword(newPassword: "new-pass-123"))
        #expect(set.url?.path == "/api/v1/auth/set-password")
        #expect(try body(Endpoints.settingsSetPassword(newPassword: "new-pass-123"))["newPassword"] as? String == "new-pass-123")
    }

    @Test("Registration options ask for a platform authenticator")
    func registrationOptionsQuery() throws {
        let url = try #require(try request(Endpoints.settingsPasskeyRegistrationOptions()).url)
        #expect(url.path == "/api/v1/auth/passkey/generate-register-options")
        #expect(url.query == "authenticatorAttachment=platform")
    }

    @Test("Registration verification body matches SimpleWebAuthn's RegistrationResponseJSON")
    func verifyRegistrationBody() throws {
        let registration = SettingsPasskeyRegistration(
            credentialID: Data([0xFB, 0xFF, 0x01]),
            clientDataJSON: Data(#"{"type":"webauthn.create"}"#.utf8),
            attestationObject: Data([0xA3, 0x01])
        )
        let json = try body(Endpoints.settingsVerifyPasskeyRegistration(registration, name: "iPhone"))
        #expect(json["name"] as? String == "iPhone")
        let response = try #require(json["response"] as? [String: Any])
        #expect(response["id"] as? String == Base64URL.encode(registration.credentialID))
        #expect(response["rawId"] as? String == response["id"] as? String)
        #expect(response["type"] as? String == "public-key")
        #expect(response["authenticatorAttachment"] as? String == "platform")
        #expect((response["clientExtensionResults"] as? [String: Any])?.isEmpty == true)
        let attestation = try #require(response["response"] as? [String: Any])
        #expect(attestation["clientDataJSON"] as? String == Base64URL.encode(registration.clientDataJSON))
        #expect(attestation["attestationObject"] as? String == Base64URL.encode(registration.attestationObject))
        #expect(attestation["transports"] as? [String] == ["internal", "hybrid"])
    }

    @Test("Danger zone writes hit the app routes")
    func dangerZone() throws {
        let wipe = try request(Endpoints.settingsWipeData(acknowledgeSharing: true))
        #expect(wipe.url?.path == "/api/v1/user/wipe-data")
        #expect(wipe.httpMethod == "POST")
        #expect(try body(Endpoints.settingsWipeData(acknowledgeSharing: false))["acknowledgeSharing"] as? Bool == false)

        let delete = try request(Endpoints.settingsDeleteAccount())
        #expect(delete.url?.path == "/api/v1/user/delete")
        #expect(delete.httpMethod == "DELETE")
        #expect(delete.httpBody == nil)
    }

    @Test("Preference patches send only the changed slices")
    func preferencesPatch() throws {
        let locale = try body(Endpoints.updateSettingsPreferences(SettingsPreferencesPatch(localeCode: "uk")))
        #expect(locale.keys.sorted() == ["locale"])
        #expect(locale["locale"] as? String == "uk")
        #expect(try request(Endpoints.updateSettingsPreferences(SettingsPreferencesPatch())).httpMethod == "PATCH")

        let clearDefault = try body(Endpoints.updateSettingsPreferences(SettingsPreferencesPatch(defaultAccountId: .clear)))
        let accounts = try #require(clearDefault["accounts"] as? [String: Any])
        #expect(accounts.keys.sorted() == ["defaultAccountId"])
        #expect(accounts["defaultAccountId"] is NSNull)

        let nested = try body(Endpoints.updateSettingsPreferences(SettingsPreferencesPatch(
            currencyDisplay: .narrowSymbol,
            sidebarSections: SettingsSidebarSections(portfolios: false),
            defaultAccountId: .set("acc-2"),
            hideUpcomingTransactions: true,
            optionalTransactionFields: [.location]
        )))
        #expect(nested["currencyDisplay"] as? String == "narrowSymbol")
        #expect((nested["sidebarSections"] as? [String: Bool])?["portfolios"] == false)
        #expect((nested["accounts"] as? [String: Any])?["defaultAccountId"] as? String == "acc-2")
        let ui = try #require(nested["ui"] as? [String: Any])
        #expect((ui["transactionsList"] as? [String: Bool])?["hideUpcoming"] == true)
        let form = try #require(ui["transactionForm"] as? [String: Any])
        #expect(form["optionalFields"] as? [String] == ["location"])
        #expect(form["mapPicker"] == nil)
    }

    // MARK: Ceremony

    @Test("Passkey registration sends the bearer token on both calls and returns the new passkey")
    func registrationCeremony() async throws {
        let challenge = Data([5, 6, 7])
        let stubServer = URLProtocolStub.register { request in
            if request.url.path.hasSuffix("/generate-register-options") {
                return .json("""
                {"challenge":"\(Base64URL.encode(challenge))","rp":{"id":"settings-passkey.example.com"},
                 "user":{"id":"dXNlcg","name":"pranav"}}
                """, headers: ["Set-Cookie": "better-auth.passkey=abc; Path=/"])
            }
            return .json(#"{"id":"pk-new","name":"iPhone","createdAt":"2026-10-09T00:00:00.000Z"}"#)
        }
        let client = APIClient.stubbed(server: stubServer, token: "bearer-1")
        let passkey = try await client.registerSettingsPasskey(name: "iPhone") { options in
            #expect(options.challenge == challenge)
            return SettingsPasskeyRegistration(credentialID: Data([1]), clientDataJSON: Data([2]), attestationObject: Data([3]))
        }
        #expect(passkey.id == "pk-new")

        let requests = URLProtocolStub.requests(for: stubServer)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.header("Authorization") == "Bearer bearer-1" })
        #expect(requests[1].method == "POST")
        #expect(requests[1].header("Origin") != nil)
    }

    @Test("A stale session surfaces SESSION_NOT_FRESH")
    func registrationNeedsFreshSession() async throws {
        let stubServer = URLProtocolStub.register { _ in
            .json(#"{"code":"SESSION_NOT_FRESH","message":"Session is not fresh"}"#, status: 403)
        }
        let client = APIClient.stubbed(server: stubServer, token: "bearer-1")
        await #expect(throws: APIError.server(statusCode: 403, code: SettingsSecurityErrorCode.sessionNotFresh, message: "Session is not fresh")) {
            _ = try await client.registerSettingsPasskey(name: nil) { _ in
                Issue.record("The authenticator shouldn't run")
                return SettingsPasskeyRegistration(credentialID: Data(), clientDataJSON: Data(), attestationObject: Data())
            }
        }
    }
}
