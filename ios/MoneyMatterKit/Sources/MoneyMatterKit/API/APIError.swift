import Foundation

/// One Zod issue from a 422 `validationErrors` array.
public struct ValidationIssue: Sendable, Hashable, Decodable {
    public let message: String
    public let code: String?
    /// Zod paths mix keys and array indices; both are kept as strings.
    public let path: [String]

    public init(message: String, code: String? = nil, path: [String] = []) {
        self.message = message
        self.code = code
        self.path = path
    }

    private enum CodingKeys: String, CodingKey { case message, code, path }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        code = try container.decodeIfPresent(String.self, forKey: .code)
        let components = (try? container.decodeIfPresent([PathComponent].self, forKey: .path)) ?? []
        path = components.map(\.value)
    }

    private struct PathComponent: Decodable {
        let value: String

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let key = try? container.decode(String.self) {
                value = key
            } else {
                value = String(try container.decode(Int.self))
            }
        }
    }
}

/// Every failure `APIClient` can produce. Callers can match on a case without
/// binding its payload, e.g. `case .unauthenticated:`.
public enum APIError: Error, Sendable, Equatable {
    /// 401. The bearer token is missing, expired, or revoked; there is no refresh.
    case unauthenticated(message: String?)
    /// 402 `PLAN_REQUIRED`: the server's plan blocks the action.
    case planRequired(message: String?)
    /// 423 `BASE_CURRENCY_CHANGE_IN_PROGRESS`: mutations wait for the change to finish.
    case baseCurrencyChangeInProgress(message: String?)
    /// 422. `code` distinguishes `VALIDATION_ERROR` from domain codes such as `CURRENCY_NOT_CONNECTED`.
    case validation(message: String, issues: [ValidationIssue], code: String?)
    /// 404.
    case notFound(message: String?)
    /// Any other error response.
    case server(statusCode: Int, code: String?, message: String?)
    /// The request never produced an HTTP response.
    case network(URLError)
    /// The body didn't match the expected shape.
    case decoding(String)

    /// The server's own (already localized) message, when it sent one.
    public var serverMessage: String? {
        switch self {
        case .unauthenticated(let message), .planRequired(let message),
             .baseCurrencyChangeInProgress(let message), .notFound(let message):
            message
        case .validation(let message, _, _):
            message
        case .server(_, _, let message):
            message
        case .network, .decoding:
            nil
        }
    }

    public var isUnauthenticated: Bool {
        if case .unauthenticated = self { return true }
        return false
    }

    /// A cancelled request (for example a view's `.task` going away); never worth showing.
    public var isCancellation: Bool {
        if case .network(let urlError) = self { return urlError.code == .cancelled }
        return false
    }

    /// Wraps any error thrown around an API call so callers deal with one type.
    public init(_ error: any Error) {
        switch error {
        case let apiError as APIError:
            self = apiError
        case let urlError as URLError:
            self = .network(urlError)
        case is CancellationError:
            self = .network(URLError(.cancelled))
        case let decodingError as DecodingError:
            self = .decoding(String(describing: decodingError))
        default:
            self = .decoding(String(describing: error))
        }
    }
}
