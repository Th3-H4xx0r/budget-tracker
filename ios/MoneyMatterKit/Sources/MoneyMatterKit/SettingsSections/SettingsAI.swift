import Foundation

// AI settings: per-feature model selection, provider API keys, custom OpenAI-compatible
// endpoints, and categorization custom instructions. Mirrors `packages/shared/src/types/ai`.

// MARK: - Enums

/// `AI_PROVIDER`. `custom` is a user's own endpoint and never owns an API-key slot.
public enum SettingsAIProvider: String, LenientEnum, CaseIterable, Identifiable {
    case anthropic
    case openai
    case google
    case groq
    case custom
    case unknown

    /// `AI_KEY_PROVIDERS`: the providers whose credential is a plain API key.
    public static let keyProviders: [SettingsAIProvider] = [.anthropic, .openai, .google, .groq]

    public var id: String { rawValue }
}

/// `AI_FEATURE`: AI-powered features that each pick their own model.
public enum SettingsAIFeature: String, LenientEnum, CaseIterable {
    case categorization
    case statementParsing = "statement_parsing"
    case investmentTransactionsParsing = "investment_transactions_parsing"
    case unknown
}

/// `AIApiKeyStatus`, shared by API keys and custom endpoints.
public enum SettingsAICredentialStatus: String, LenientEnum {
    case valid
    case invalid
    case unknown
}

/// `AIModelCostTier`.
public enum SettingsAIModelCostTier: String, LenientEnum {
    case free
    case low
    case medium
    case high
    case unknown
}

// MARK: - Models

/// `AIApiKeyInfo`: a stored key's metadata, never the key itself.
public struct SettingsAIKeyInfo: Sendable, Hashable, Identifiable, Decodable {
    public let provider: SettingsAIProvider
    public let createdAt: Date?
    public let status: SettingsAICredentialStatus
    public let lastValidatedAt: Date?
    public let lastError: String?
    public let invalidatedAt: Date?

    public var id: String { provider.rawValue }

    private enum CodingKeys: String, CodingKey {
        case provider, createdAt, status, lastValidatedAt, lastError, invalidatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeLenient(SettingsAIProvider.self, forKey: .provider, default: .unknown)
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        status = try container.decodeLenient(SettingsAICredentialStatus.self, forKey: .status, default: .unknown)
        lastValidatedAt = try? container.decodeIfPresent(Date.self, forKey: .lastValidatedAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        invalidatedAt = try? container.decodeIfPresent(Date.self, forKey: .invalidatedAt)
    }
}

/// `GET /user/settings/ai/api-keys`.
public struct SettingsAIKeyStatus: Sendable, Hashable, Decodable {
    public let hasApiKey: Bool
    public let providers: [SettingsAIKeyInfo]
    public let defaultProvider: SettingsAIProvider?

    private enum CodingKeys: String, CodingKey { case hasApiKey, providers, defaultProvider }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasApiKey = try container.decodeIfPresent(Bool.self, forKey: .hasApiKey) ?? false
        providers = try container.decodeLossyArrayIfPresent([SettingsAIKeyInfo].self, forKey: .providers) ?? []
        defaultProvider = try container.decodeIfPresent(SettingsAIProvider.self, forKey: .defaultProvider)
    }
}

/// `AIFeatureStatus`: the model that answers a feature's calls right now.
public struct SettingsAIFeatureStatus: Sendable, Hashable, Identifiable, Decodable {
    public let feature: SettingsAIFeature
    /// `false` while the feature runs on the server default.
    public let isConfigured: Bool
    /// `provider/model`, or `custom/<name>` for a custom endpoint.
    public let modelId: String
    public let modelName: String
    /// Whether the user's own key or endpoint pays for the call.
    public let usingUserKey: Bool
    public let customEndpointId: String?
    public let endpointName: String?

    public var id: String { feature.rawValue }

    /// Whether a custom endpoint serves the model.
    public var isCustomModel: Bool { modelId.hasPrefix(SettingsAIModel.customPrefix) }

    private enum CodingKeys: String, CodingKey {
        case feature, isConfigured, modelId, modelName, usingUserKey, customEndpointId, endpointName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        feature = try container.decodeLenient(SettingsAIFeature.self, forKey: .feature, default: .unknown)
        isConfigured = try container.decodeIfPresent(Bool.self, forKey: .isConfigured) ?? false
        modelId = try container.decodeIfPresent(String.self, forKey: .modelId) ?? ""
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? ""
        usingUserKey = try container.decodeIfPresent(Bool.self, forKey: .usingUserKey) ?? false
        customEndpointId = try container.decodeIfPresent(String.self, forKey: .customEndpointId)
        endpointName = try container.decodeIfPresent(String.self, forKey: .endpointName)
    }
}

/// `AIModelPricing`: USD per million tokens.
public struct SettingsAIModelPricing: Sendable, Hashable, Decodable {
    public let inputPerMillion: Decimal
    public let outputPerMillion: Decimal
}

/// `AIModelInfoWithRecommendation`: one catalog model.
public struct SettingsAIModel: Sendable, Hashable, Identifiable, Decodable {
    /// Prefix of a model ID served by the user's own endpoint.
    public static let customPrefix = "custom/"

    public let id: String
    public let name: String
    public let provider: SettingsAIProvider
    public let description: String
    public let contextWindow: Int
    public let capabilities: [String]
    public let costTier: SettingsAIModelCostTier
    public let pricing: SettingsAIModelPricing?
    public let recommendedForFeature: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, provider, description, contextWindow, capabilities, costTier, pricing, recommendedForFeature
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        provider = try container.decodeLenient(SettingsAIProvider.self, forKey: .provider, default: .unknown)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        contextWindow = try container.decodeIfPresent(Int.self, forKey: .contextWindow) ?? 0
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        costTier = try container.decodeLenient(SettingsAIModelCostTier.self, forKey: .costTier, default: .unknown)
        pricing = try? container.decodeIfPresent(SettingsAIModelPricing.self, forKey: .pricing)
        recommendedForFeature = try container.decodeIfPresent(Bool.self, forKey: .recommendedForFeature) ?? false
    }

    /// The `custom/<name>` ID for a model on a custom endpoint.
    public static func customModelID(name: String) -> String {
        customPrefix + name
    }
}

/// `AICustomEndpointInfo`: a user's OpenAI-compatible endpoint, without key material.
public struct SettingsAICustomEndpoint: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let baseUrl: String
    public let defaultModel: String
    public let hasApiKey: Bool
    public let createdAt: Date?
    public let status: SettingsAICredentialStatus
    public let lastValidatedAt: Date?
    public let lastError: String?
    public let invalidatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, name, baseUrl, defaultModel, hasApiKey, createdAt, status, lastValidatedAt, lastError, invalidatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl) ?? ""
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel) ?? ""
        hasApiKey = try container.decodeIfPresent(Bool.self, forKey: .hasApiKey) ?? false
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        status = try container.decodeLenient(SettingsAICredentialStatus.self, forKey: .status, default: .unknown)
        lastValidatedAt = try? container.decodeIfPresent(Date.self, forKey: .lastValidatedAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        invalidatedAt = try? container.decodeIfPresent(Date.self, forKey: .invalidatedAt)
    }
}

/// `POST /user/settings/ai/custom-endpoints/test` reply.
public struct SettingsAIEndpointTestResult: Sendable, Hashable, Decodable {
    public let isValid: Bool
    public let error: String?
}

// MARK: - Requests

/// `PUT /user/settings/ai/custom-endpoints/:id` body. Omitted fields keep their stored
/// values; `apiKey: .clear` sends `null`, which removes the stored key.
public struct SettingsAICustomEndpointUpdate: Encodable, Sendable, Hashable {
    public var name: String?
    public var baseUrl: String?
    public var defaultModel: String?
    public var apiKey: FieldUpdate<String>

    public init(name: String? = nil, baseUrl: String? = nil, defaultModel: String? = nil, apiKey: FieldUpdate<String> = .unchanged) {
        self.name = name
        self.baseUrl = baseUrl
        self.defaultModel = defaultModel
        self.apiKey = apiKey
    }

    private enum CodingKeys: String, CodingKey { case name, baseUrl, defaultModel, apiKey }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(baseUrl, forKey: .baseUrl)
        try container.encodeIfPresent(defaultModel, forKey: .defaultModel)
        switch apiKey {
        case .unchanged:
            break
        case .clear:
            try container.encodeNil(forKey: .apiKey)
        case .set(let key):
            try container.encode(key, forKey: .apiKey)
        }
    }
}

/// What to test: a saved endpoint (omitted fields fall back to its stored values, key
/// included), or a combination typed in before saving.
public enum SettingsAIEndpointTestRequest: Encodable, Sendable, Hashable {
    case saved(endpointID: String, baseUrl: String? = nil, defaultModel: String? = nil, apiKey: String? = nil)
    case typed(baseUrl: String, defaultModel: String, apiKey: String? = nil)

    private enum CodingKeys: String, CodingKey { case endpointId, baseUrl, defaultModel, apiKey }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .saved(endpointID, baseUrl, defaultModel, apiKey):
            try container.encode(endpointID, forKey: .endpointId)
            try container.encodeIfPresent(baseUrl, forKey: .baseUrl)
            try container.encodeIfPresent(defaultModel, forKey: .defaultModel)
            try container.encodeIfPresent(apiKey, forKey: .apiKey)
        case let .typed(baseUrl, defaultModel, apiKey):
            try container.encode(baseUrl, forKey: .baseUrl)
            try container.encode(defaultModel, forKey: .defaultModel)
            try container.encodeIfPresent(apiKey, forKey: .apiKey)
        }
    }
}

struct SettingsAIKeyBody: Encodable, Sendable {
    let provider: String
    let apiKey: String
}

struct SettingsAIProviderBody: Encodable, Sendable {
    let provider: String
}

struct SettingsAIFeatureModelBody: Encodable, Sendable {
    let modelId: String
    let customEndpointId: String?
}

struct SettingsAIInstructionsBody: Encodable, Sendable {
    let instructions: String
}

struct SettingsAICustomEndpointCreateBody: Encodable, Sendable {
    let name: String
    let baseUrl: String
    let defaultModel: String
    let apiKey: String?
}

private struct SettingsAIFeaturesResponse: Decodable, Sendable {
    let features: [SettingsAIFeatureStatus]
}

private struct SettingsAIModelsResponse: Decodable, Sendable {
    let models: [SettingsAIModel]
}

private struct SettingsAIInstructionsResponse: Decodable, Sendable {
    let instructions: String?
}

private struct SettingsAIEmptyBody: Encodable, Sendable {}

// MARK: - Endpoints

extension Endpoints {
    /// `GET /user/settings/ai/api-keys`.
    public static func settingsAIKeyStatus() -> Endpoint<SettingsAIKeyStatus> {
        Endpoint(.get, "/user/settings/ai/api-keys")
    }

    /// `PUT /user/settings/ai/api-keys`: adds or replaces one provider's key.
    public static func settingsAISetKey(provider: SettingsAIProvider, apiKey: String) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/user/settings/ai/api-keys", body: SettingsAIKeyBody(provider: provider.rawValue, apiKey: apiKey))
    }

    /// `DELETE /user/settings/ai/api-keys` with `{provider}` in the body.
    public static func settingsAIDeleteKey(provider: SettingsAIProvider) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/user/settings/ai/api-keys", body: SettingsAIProviderBody(provider: provider.rawValue))
    }

    /// `DELETE /user/settings/ai/api-keys/all`.
    public static func settingsAIDeleteAllKeys() -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/user/settings/ai/api-keys/all")
    }

    /// `PUT /user/settings/ai/api-keys/default`.
    public static func settingsAISetDefaultProvider(_ provider: SettingsAIProvider) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/user/settings/ai/api-keys/default", body: SettingsAIProviderBody(provider: provider.rawValue))
    }

    /// `GET /user/settings/ai/features`.
    public static func settingsAIFeatures() -> Endpoint<[SettingsAIFeatureStatus]> {
        Endpoint<SettingsAIFeaturesResponse>(.get, "/user/settings/ai/features").map(\.features)
    }

    /// `PUT /user/settings/ai/features/:feature`. `customEndpointId` is required for a
    /// `custom/*` model and ignored for catalog models.
    public static func settingsAISetFeatureModel(
        feature: SettingsAIFeature,
        modelId: String,
        customEndpointId: String? = nil
    ) -> Endpoint<SettingsAIFeatureStatus> {
        Endpoint(
            .put,
            "/user/settings/ai/features/\(feature.rawValue)",
            body: SettingsAIFeatureModelBody(modelId: modelId, customEndpointId: customEndpointId)
        )
    }

    /// `DELETE /user/settings/ai/features/:feature`: back to the server default.
    public static func settingsAIResetFeature(_ feature: SettingsAIFeature) -> Endpoint<SettingsAIFeatureStatus> {
        Endpoint(.delete, "/user/settings/ai/features/\(feature.rawValue)")
    }

    /// `GET /user/settings/ai/models`, flagged with recommendations when `feature` is set.
    public static func settingsAIModels(feature: SettingsAIFeature? = nil) -> Endpoint<[SettingsAIModel]> {
        var query: [URLQueryItem] = []
        if let feature, feature != .unknown {
            query.append(URLQueryItem(name: "feature", value: feature.rawValue))
        }
        return Endpoint<SettingsAIModelsResponse>(.get, "/user/settings/ai/models", query: query).map(\.models)
    }

    /// `GET /user/settings/ai/custom-instructions`: `nil` when none are set.
    public static func settingsAICustomInstructions() -> Endpoint<String?> {
        Endpoint<SettingsAIInstructionsResponse>(.get, "/user/settings/ai/custom-instructions").map(\.instructions)
    }

    /// `PUT /user/settings/ai/custom-instructions`. At most 2000 characters.
    public static func settingsAISetCustomInstructions(_ instructions: String) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/user/settings/ai/custom-instructions", body: SettingsAIInstructionsBody(instructions: instructions))
    }

    /// `GET /user/settings/ai/custom-endpoints`.
    public static func settingsAICustomEndpoints() -> Endpoint<[SettingsAICustomEndpoint]> {
        Endpoint(.get, "/user/settings/ai/custom-endpoints")
    }

    /// `POST /user/settings/ai/custom-endpoints`. A `nil` key means no authentication.
    public static func settingsAICreateCustomEndpoint(
        name: String,
        baseUrl: String,
        defaultModel: String,
        apiKey: String?
    ) -> Endpoint<SettingsAICustomEndpoint> {
        Endpoint(
            .post,
            "/user/settings/ai/custom-endpoints",
            body: SettingsAICustomEndpointCreateBody(name: name, baseUrl: baseUrl, defaultModel: defaultModel, apiKey: apiKey)
        )
    }

    /// `PUT /user/settings/ai/custom-endpoints/:id`.
    public static func settingsAIUpdateCustomEndpoint(
        id: String,
        _ update: SettingsAICustomEndpointUpdate
    ) -> Endpoint<SettingsAICustomEndpoint> {
        Endpoint(.put, "/user/settings/ai/custom-endpoints/\(id)", body: update)
    }

    /// `DELETE /user/settings/ai/custom-endpoints/:id`.
    public static func settingsAIDeleteCustomEndpoint(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/user/settings/ai/custom-endpoints/\(id)")
    }

    /// `POST /user/settings/ai/custom-endpoints/test`.
    public static func settingsAITestCustomEndpoint(_ request: SettingsAIEndpointTestRequest) -> Endpoint<SettingsAIEndpointTestResult> {
        Endpoint(.post, "/user/settings/ai/custom-endpoints/test", body: request)
    }
}
