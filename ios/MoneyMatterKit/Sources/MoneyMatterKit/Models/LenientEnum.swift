import Foundation

/// A string enum mirroring a backend value set. A raw value the app doesn't know yet
/// decodes to `.unknown` instead of failing the whole response.
public protocol LenientEnum: RawRepresentable, Codable, Sendable, Hashable where RawValue == String {
    static var unknown: Self { get }
}

extension LenientEnum {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension KeyedDecodingContainer {
    /// Decodes a lenient enum, treating a missing key or `null` as `fallback`.
    func decodeLenient<Value: LenientEnum>(_ type: Value.Type, forKey key: Key, default fallback: Value) throws -> Value {
        try decodeIfPresent(Value.self, forKey: key) ?? fallback
    }
}

extension KeyedDecodingContainer {
    /// Decodes an optional array element by element, dropping elements that fail, so one odd
    /// split or tag doesn't fail the whole row (and with it the whole page).
    func decodeLossyArrayIfPresent<Element: Decodable>(_ type: [Element].Type, forKey key: Key) throws -> [Element]? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decode([LossyElement<Element>].self, forKey: key).compactMap(\.value)
    }
}

private struct LossyElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
