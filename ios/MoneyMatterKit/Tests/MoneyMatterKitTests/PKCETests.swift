import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("PKCE")
struct PKCETests {
    @Test("Matches the RFC 7636 appendix B test vector")
    func rfcVector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("Generated verifiers are 43 unpadded base64url characters and unique")
    func generated() {
        let first = PKCE.generate()
        let second = PKCE.generate()
        #expect(first.verifier.count == 43)
        #expect(first.verifier != second.verifier)
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(first.verifier.allSatisfy(allowed.contains))
        #expect(first.challenge == PKCE.challenge(for: first.verifier))
        #expect(!first.challenge.contains("="))
    }

    @Test("Base64URL round-trips and pads on decode")
    func base64URL() {
        let data = Data([0xfb, 0xff, 0xbf, 0x01])
        let encoded = Base64URL.encode(data)
        #expect(encoded == "-_-_AQ")
        #expect(Base64URL.decode(encoded) == data)
    }
}
