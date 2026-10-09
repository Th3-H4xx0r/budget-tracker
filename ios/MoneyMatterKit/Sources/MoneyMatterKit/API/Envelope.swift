import Foundation

/// The body of a handler that returns `{status:'success'}` with no `response`, or
/// any body the caller doesn't need.
public struct EmptyResponse: Sendable, Hashable, Decodable {
    public init() {}
    public init(from decoder: any Decoder) throws {}
}

/// Types that stand in for a missing `response` key or an empty body.
protocol MissingResponseRepresentable {
    static var missingResponse: Self { get }
}

extension EmptyResponse: MissingResponseRepresentable {
    static var missingResponse: EmptyResponse { EmptyResponse() }
}

extension Optional: MissingResponseRepresentable {
    static var missingResponse: Optional<Wrapped> { nil }
}

/// `{status:'success', response:<data>}`.
struct SuccessEnvelope<Value: Decodable>: Decodable {
    let value: Value

    private enum CodingKeys: String, CodingKey { case status, response }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.response) {
            value = try container.decode(Value.self, forKey: .response)
        } else if let missing = Value.self as? any MissingResponseRepresentable.Type,
                  let placeholder = missing.missingResponse as? Value {
            value = placeholder
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.response,
                .init(codingPath: container.codingPath, debugDescription: "Envelope has no response")
            )
        }
    }
}

/// Used to tell an enveloped body from a bare one.
struct EnvelopeProbe: Decodable {
    let status: String?
}

/// The `response` of an error envelope, or a bare better-auth `{code, message}` body.
struct ErrorPayload: Decodable {
    let message: String?
    let code: String?
    let validationErrors: [ValidationIssue]?
}

struct ErrorEnvelope: Decodable {
    let status: String
    let response: ErrorPayload
}
