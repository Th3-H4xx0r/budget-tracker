import CryptoKit
import Foundation

/// A PKCE verifier and its S256 challenge (RFC 7636).
public struct PKCE: Sendable, Hashable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.challenge(for: verifier)
    }

    /// A fresh pair with a 43-character verifier from 32 random bytes.
    public static func generate() -> PKCE {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return PKCE(verifier: Base64URL.encode(Data(bytes)))
    }

    /// `base64url(SHA256(ASCII(verifier)))`.
    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Base64URL.encode(Data(digest))
    }
}
