import Foundation

/// `GET /auth/passkey/generate-authenticate-options` (WebAuthn request options JSON).
public struct PasskeyRequestOptions: Sendable, Hashable, Decodable {
    public let challenge: Data
    /// The relying party; falls back to the server host when the server omits it.
    public let rpId: String?
    public let allowedCredentialIDs: [Data]
    public let userVerification: String?

    public init(challenge: Data, rpId: String?, allowedCredentialIDs: [Data] = [], userVerification: String? = nil) {
        self.challenge = challenge
        self.rpId = rpId
        self.allowedCredentialIDs = allowedCredentialIDs
        self.userVerification = userVerification
    }

    private enum CodingKeys: String, CodingKey { case challenge, rpId, allowCredentials, userVerification }

    private struct Descriptor: Decodable { let id: String }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let challengeString = try container.decode(String.self, forKey: .challenge)
        guard let challenge = Base64URL.decode(challengeString) else {
            throw DecodingError.dataCorruptedError(forKey: .challenge, in: container, debugDescription: "Challenge isn't base64url")
        }
        self.challenge = challenge
        rpId = try container.decodeIfPresent(String.self, forKey: .rpId)
        let descriptors = try container.decodeIfPresent([Descriptor].self, forKey: .allowCredentials) ?? []
        allowedCredentialIDs = descriptors.compactMap { Base64URL.decode($0.id) }
        userVerification = try container.decodeIfPresent(String.self, forKey: .userVerification)
    }
}

/// A platform passkey assertion, as returned by `ASAuthorizationPlatformPublicKeyCredentialAssertion`.
public struct PasskeyAssertion: Sendable, Hashable {
    public let credentialID: Data
    public let clientDataJSON: Data
    public let authenticatorData: Data
    public let signature: Data
    public let userHandle: Data?

    public init(credentialID: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data, userHandle: Data?) {
        self.credentialID = credentialID
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.signature = signature
        self.userHandle = userHandle
    }
}

/// `POST /auth/passkey/verify-authentication` body: `{response: <AuthenticationResponseJSON>}`.
struct PasskeyVerificationRequest: Encodable, Sendable {
    struct AssertionResponse: Encodable, Sendable {
        let clientDataJSON: String
        let authenticatorData: String
        let signature: String
        let userHandle: String?
    }

    struct Credential: Encodable, Sendable {
        let id: String
        let rawId: String
        let type = "public-key"
        let authenticatorAttachment = "platform"
        let clientExtensionResults: [String: String] = [:]
        let response: AssertionResponse
    }

    let response: Credential

    init(assertion: PasskeyAssertion) {
        let credentialID = Base64URL.encode(assertion.credentialID)
        response = Credential(
            id: credentialID,
            rawId: credentialID,
            response: AssertionResponse(
                clientDataJSON: Base64URL.encode(assertion.clientDataJSON),
                authenticatorData: Base64URL.encode(assertion.authenticatorData),
                signature: Base64URL.encode(assertion.signature),
                userHandle: assertion.userHandle.map(Base64URL.encode)
            )
        )
    }
}
