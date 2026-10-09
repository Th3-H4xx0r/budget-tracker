import Foundation

// MARK: - Models

/// The sign-in provider behind a linked better-auth account.
public enum SettingsAuthProvider: Sendable, Hashable {
    case credential
    case google
    case github
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "credential": self = .credential
        case "google": self = .google
        case "github": self = .github
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .credential: "credential"
        case .google: "google"
        case .github: "github"
        case .unknown(let value): value
        }
    }
}

/// `GET /auth/list-accounts` item: one way the user can sign in.
public struct SettingsLinkedAccount: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let providerId: String
    public let accountId: String
    public let createdAt: Date?

    public var provider: SettingsAuthProvider { SettingsAuthProvider(rawValue: providerId) }

    public init(id: String, providerId: String, accountId: String, createdAt: Date? = nil) {
        self.id = id
        self.providerId = providerId
        self.accountId = accountId
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, providerId, accountId, createdAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        providerId = try container.decodeIfPresent(String.self, forKey: .providerId) ?? ""
        accountId = try container.decodeIfPresent(String.self, forKey: .accountId) ?? ""
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

/// `GET /auth/passkey/list-user-passkeys` item.
public struct SettingsPasskey: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String?
    public let deviceType: String?
    public let backedUp: Bool?
    public let createdAt: Date?

    public init(id: String, name: String? = nil, deviceType: String? = nil, backedUp: Bool? = nil, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.deviceType = deviceType
        self.backedUp = backedUp
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, name, deviceType, backedUp, createdAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        deviceType = try container.decodeIfPresent(String.self, forKey: .deviceType)
        backedUp = try? container.decodeIfPresent(Bool.self, forKey: .backedUp)
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

/// `GET /auth/list-sessions` item.
public struct SettingsAuthSessionEntry: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let token: String
    public let ipAddress: String?
    public let userAgent: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let expiresAt: Date?

    public init(
        id: String,
        token: String,
        ipAddress: String? = nil,
        userAgent: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.token = token
        self.ipAddress = ipAddress
        self.userAgent = userAgent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey { case id, token, ipAddress, userAgent, createdAt, updatedAt, expiresAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        ipAddress = try container.decodeIfPresent(String.self, forKey: .ipAddress)
        userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent)
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(Date.self, forKey: .updatedAt)
        expiresAt = try? container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }

    /// The device class the user agent describes, for picking an icon.
    public var deviceKind: SettingsSessionDeviceKind {
        guard let userAgent, !userAgent.isEmpty else { return .unknown }
        if userAgent.contains("iPad") || userAgent.contains("Tablet") { return .tablet }
        if userAgent.contains("Mobile") || userAgent.contains("Android") || userAgent.contains("iPhone")
            || userAgent.contains("CFNetwork") {
            return .phone
        }
        return .computer
    }

    /// A short browser or app name from the user agent, e.g. `Safari 18`. `nil` when unrecognised.
    public var clientName: String? {
        guard let userAgent, !userAgent.isEmpty else { return nil }
        func version(after marker: String) -> String {
            guard let range = userAgent.range(of: marker) else { return "" }
            return String(userAgent[range.upperBound...].prefix(while: \.isNumber))
        }
        if userAgent.contains("Edg") { return "Edge \(version(after: "Edg/"))".trimmingCharacters(in: .whitespaces) }
        if userAgent.contains("Chrome") { return "Chrome \(version(after: "Chrome/"))".trimmingCharacters(in: .whitespaces) }
        if userAgent.contains("Firefox") { return "Firefox \(version(after: "Firefox/"))".trimmingCharacters(in: .whitespaces) }
        if userAgent.contains("CFNetwork") || userAgent.hasPrefix("MoneyMatter") { return "MoneyMatter for iOS" }
        if userAgent.contains("Safari") { return "Safari \(version(after: "Version/"))".trimmingCharacters(in: .whitespaces) }
        return nil
    }
}

public enum SettingsSessionDeviceKind: Sendable, Hashable {
    case phone, tablet, computer, unknown
}

/// Error codes the security screens react to.
public enum SettingsSecurityErrorCode {
    /// Passkey registration needs a session signed in within the last day.
    public static let sessionNotFresh = "SESSION_NOT_FRESH"
    /// `POST /auth/set-password` when the account already has one.
    public static let passwordAlreadySet = "PASSWORD_ALREADY_SET"
    /// `POST /user/wipe-data` (409) when owned data is shared with others.
    public static let wipeNeedsSharingAcknowledgement = "WIPE_DATA_SHARING_ACK_REQUIRED"
}

// MARK: - Passkey registration

/// `GET /auth/passkey/generate-register-options`: SimpleWebAuthn creation options.
public struct SettingsPasskeyCreationOptions: Sendable, Hashable, Decodable {
    public let challenge: Data
    public let rpId: String?
    public let userID: Data
    public let userName: String
    public let excludedCredentialIDs: [Data]
    public let userVerification: String?

    public init(
        challenge: Data,
        rpId: String?,
        userID: Data,
        userName: String,
        excludedCredentialIDs: [Data] = [],
        userVerification: String? = nil
    ) {
        self.challenge = challenge
        self.rpId = rpId
        self.userID = userID
        self.userName = userName
        self.excludedCredentialIDs = excludedCredentialIDs
        self.userVerification = userVerification
    }

    private enum CodingKeys: String, CodingKey { case challenge, rp, user, excludeCredentials, authenticatorSelection }
    private struct RelyingParty: Decodable { let id: String? }
    private struct UserEntity: Decodable { let id: String; let name: String? }
    private struct Descriptor: Decodable { let id: String }
    private struct Selection: Decodable { let userVerification: String? }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let challengeString = try container.decode(String.self, forKey: .challenge)
        guard let challenge = Base64URL.decode(challengeString) else {
            throw DecodingError.dataCorruptedError(forKey: .challenge, in: container, debugDescription: "Challenge isn't base64url")
        }
        self.challenge = challenge
        rpId = try container.decodeIfPresent(RelyingParty.self, forKey: .rp)?.id
        let user = try container.decode(UserEntity.self, forKey: .user)
        userID = Base64URL.decode(user.id) ?? Data(user.id.utf8)
        userName = user.name ?? ""
        let descriptors = try container.decodeIfPresent([Descriptor].self, forKey: .excludeCredentials) ?? []
        excludedCredentialIDs = descriptors.compactMap { Base64URL.decode($0.id) }
        userVerification = try container.decodeIfPresent(Selection.self, forKey: .authenticatorSelection)?.userVerification
    }
}

/// A new platform passkey, as returned by `ASAuthorizationPlatformPublicKeyCredentialRegistration`.
public struct SettingsPasskeyRegistration: Sendable, Hashable {
    public let credentialID: Data
    public let clientDataJSON: Data
    public let attestationObject: Data

    public init(credentialID: Data, clientDataJSON: Data, attestationObject: Data) {
        self.credentialID = credentialID
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
    }
}

/// `POST /auth/passkey/verify-registration` body: `{response: <RegistrationResponseJSON>, name}`.
struct SettingsPasskeyVerifyRegistrationBody: Encodable, Sendable {
    struct AttestationResponse: Encodable, Sendable {
        let clientDataJSON: String
        let attestationObject: String
        let transports: [String]
    }

    struct Credential: Encodable, Sendable {
        let id: String
        let rawId: String
        let type = "public-key"
        let authenticatorAttachment = "platform"
        let clientExtensionResults: [String: String] = [:]
        let response: AttestationResponse
    }

    let response: Credential
    let name: String?

    init(registration: SettingsPasskeyRegistration, name: String?) {
        let credentialID = Base64URL.encode(registration.credentialID)
        response = Credential(
            id: credentialID,
            rawId: credentialID,
            response: AttestationResponse(
                clientDataJSON: Base64URL.encode(registration.clientDataJSON),
                attestationObject: Base64URL.encode(registration.attestationObject),
                transports: ["internal", "hybrid"]
            )
        )
        self.name = name
    }
}

// MARK: - Endpoints

extension Endpoints {
    struct SettingsUnlinkAccountBody: Encodable, Sendable {
        let providerId: String
        let accountId: String
    }

    struct SettingsIDBody: Encodable, Sendable {
        let id: String
    }

    struct SettingsRenamePasskeyBody: Encodable, Sendable {
        let id: String
        let name: String
    }

    struct SettingsSessionTokenBody: Encodable, Sendable {
        let token: String
    }

    struct SettingsChangePasswordBody: Encodable, Sendable {
        let currentPassword: String
        let newPassword: String
        let revokeOtherSessions: Bool
    }

    struct SettingsSetPasswordBody: Encodable, Sendable {
        let newPassword: String
    }

    struct SettingsWipeDataBody: Encodable, Sendable {
        let acknowledgeSharing: Bool
    }

    /// `GET /auth/list-accounts`: password and OAuth sign-in methods.
    public static func settingsLinkedAccounts() -> Endpoint<[SettingsLinkedAccount]> {
        Endpoint(.get, "/auth/list-accounts", format: .bare)
    }

    /// `POST /auth/unlink-account`. The server refuses to remove the last sign-in method.
    public static func settingsUnlinkAccount(providerId: String, accountId: String) -> Endpoint<EmptyResponse> {
        Endpoint(
            .post,
            "/auth/unlink-account",
            body: SettingsUnlinkAccountBody(providerId: providerId, accountId: accountId),
            format: .bare
        )
    }

    /// `GET /auth/passkey/list-user-passkeys`.
    public static func settingsPasskeys() -> Endpoint<[SettingsPasskey]> {
        Endpoint(.get, "/auth/passkey/list-user-passkeys", format: .bare)
    }

    /// `POST /auth/passkey/delete-passkey`.
    public static func settingsDeletePasskey(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/auth/passkey/delete-passkey", body: SettingsIDBody(id: id), format: .bare)
    }

    /// `POST /auth/passkey/update-passkey`.
    public static func settingsRenamePasskey(id: String, name: String) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/auth/passkey/update-passkey", body: SettingsRenamePasskeyBody(id: id, name: name), format: .bare)
    }

    /// `GET /auth/passkey/generate-register-options`. Needs a fresh session and sets the challenge
    /// cookie, so it runs inside `APIClient.registerSettingsPasskey`.
    static func settingsPasskeyRegistrationOptions() -> Endpoint<SettingsPasskeyCreationOptions> {
        var builder = QueryBuilder()
        builder.add("authenticatorAttachment", "platform")
        return Endpoint(.get, "/auth/passkey/generate-register-options", query: builder.items, format: .bare)
    }

    /// `POST /auth/passkey/verify-registration`.
    static func settingsVerifyPasskeyRegistration(
        _ registration: SettingsPasskeyRegistration,
        name: String?
    ) -> Endpoint<SettingsPasskey> {
        Endpoint(
            .post,
            "/auth/passkey/verify-registration",
            body: SettingsPasskeyVerifyRegistrationBody(registration: registration, name: name),
            format: .bare
        )
    }

    /// `GET /auth/list-sessions`.
    public static func settingsSessions() -> Endpoint<[SettingsAuthSessionEntry]> {
        Endpoint(.get, "/auth/list-sessions", format: .bare)
    }

    /// `POST /auth/revoke-session`.
    public static func settingsRevokeSession(token: String) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/auth/revoke-session", body: SettingsSessionTokenBody(token: token), format: .bare)
    }

    /// `POST /auth/revoke-other-sessions`: keeps only the session making the call.
    public static func settingsRevokeOtherSessions() -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/auth/revoke-other-sessions", body: EmptyBody(), format: .bare)
    }

    /// `POST /auth/change-password`. Other sessions stay signed in, as on the web.
    public static func settingsChangePassword(currentPassword: String, newPassword: String) -> Endpoint<EmptyResponse> {
        Endpoint(
            .post,
            "/auth/change-password",
            body: SettingsChangePasswordBody(
                currentPassword: currentPassword,
                newPassword: newPassword,
                revokeOtherSessions: false
            ),
            format: .bare
        )
    }

    /// `POST /auth/set-password`: adds a password to an OAuth- or passkey-only account.
    public static func settingsSetPassword(newPassword: String) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/auth/set-password", body: SettingsSetPasswordBody(newPassword: newPassword), format: .envelopeOrBare)
    }

    /// `POST /user/wipe-data`. Fails with 409 `WIPE_DATA_SHARING_ACK_REQUIRED` until
    /// `acknowledgeSharing` is true when owned data is shared.
    public static func settingsWipeData(acknowledgeSharing: Bool) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/user/wipe-data", body: SettingsWipeDataBody(acknowledgeSharing: acknowledgeSharing))
    }

    /// `DELETE /user/delete`: deletes the account and all its data.
    public static func settingsDeleteAccount() -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/user/delete")
    }
}

// MARK: - Registration ceremony

extension APIClient {
    /// Registers a platform passkey for the signed-in user.
    ///
    /// Both calls carry the bearer token (registration needs a session under a day old) and share
    /// a private cookie jar, because the server keeps the challenge in a signed cookie between them.
    public func registerSettingsPasskey(
        name: String?,
        create: @Sendable (SettingsPasskeyCreationOptions) async throws -> SettingsPasskeyRegistration
    ) async throws -> SettingsPasskey {
        // A copy of this client's configuration (so protocol classes carry over), with its own jar.
        let configuration = sessionConfiguration
        configuration.httpCookieStorage = HTTPCookieStorage()
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.urlCache = nil
        let ceremony = URLSession(configuration: configuration)
        defer { ceremony.finishTasksAndInvalidate() }

        let options = try await settingsCeremonySend(Endpoints.settingsPasskeyRegistrationOptions(), session: ceremony)
        let registration = try await create(options)
        return try await settingsCeremonySend(
            Endpoints.settingsVerifyPasskeyRegistration(registration, name: name),
            session: ceremony
        )
    }

    private func settingsCeremonySend<Response>(_ endpoint: Endpoint<Response>, session: URLSession) async throws -> Response {
        let (request, _) = try makeRequest(for: endpoint)
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
        do {
            return try endpoint.decodeBody(data, JSONCoding.makeDecoder())
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
