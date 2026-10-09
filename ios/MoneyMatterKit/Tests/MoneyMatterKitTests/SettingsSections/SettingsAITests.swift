import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Settings AI and MCP")
struct SettingsAITests {
    private let server = try! ServerEndpoint(validating: "https://budget.example.com")

    private func request<Response>(_ endpoint: Endpoint<Response>) throws -> URLRequest {
        try APIClient(server: server).makeRequest(for: endpoint).0
    }

    private func body<Response>(_ endpoint: Endpoint<Response>) throws -> [String: Any] {
        let data = try #require(try request(endpoint).httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode<Response>(_ endpoint: Endpoint<Response>, _ json: String) throws -> Response {
        try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
    }

    // MARK: Decoding

    @Test("API key status decodes providers, statuses, and the default provider")
    func keyStatusDecoding() throws {
        let json = """
        {"status":"success","response":{"hasApiKey":true,"defaultProvider":"openai","providers":[
          {"provider":"openai","createdAt":"2026-10-01T10:00:00.000Z","status":"valid","lastValidatedAt":"2026-10-02T10:00:00.000Z"},
          {"provider":"anthropic","createdAt":"2026-10-01T10:00:00.000Z","status":"invalid","lastValidatedAt":"2026-10-02T10:00:00.000Z","lastError":"Bad key","invalidatedAt":"2026-10-03T10:00:00.000Z"},
          {"provider":"mistral","createdAt":"2026-10-01T10:00:00.000Z","status":"expired","lastValidatedAt":"2026-10-02T10:00:00.000Z"}
        ]}}
        """
        let status = try decode(Endpoints.settingsAIKeyStatus(), json)
        #expect(status.hasApiKey)
        #expect(status.defaultProvider == .openai)
        #expect(status.providers.count == 3)
        #expect(status.providers[0].status == .valid)
        #expect(status.providers[1].lastError == "Bad key")
        #expect(status.providers[1].invalidatedAt != nil)
        #expect(status.providers[2].provider == .unknown)
        #expect(status.providers[2].status == .unknown)
    }

    @Test("Feature statuses decode, including custom endpoint models")
    func featuresDecoding() throws {
        let json = """
        {"status":"success","response":{"features":[
          {"feature":"categorization","isConfigured":true,"modelId":"custom/llama3.1:8b","modelName":"llama3.1:8b","usingUserKey":true,"customEndpointId":"e1","endpointName":"Home"},
          {"feature":"statement_parsing","isConfigured":false,"modelId":"openai/gpt-5","modelName":"GPT-5","usingUserKey":false},
          {"feature":"receipt_parsing","isConfigured":false,"modelId":"openai/gpt-5","modelName":"GPT-5","usingUserKey":false}
        ]}}
        """
        let features = try decode(Endpoints.settingsAIFeatures(), json)
        #expect(features.count == 3)
        #expect(features[0].feature == .categorization)
        #expect(features[0].isCustomModel)
        #expect(features[0].endpointName == "Home")
        #expect(features[1].feature == .statementParsing)
        #expect(!features[1].isCustomModel)
        #expect(features[2].feature == .unknown)
    }

    @Test("Models decode with pricing, recommendation, and lenient enums")
    func modelsDecoding() throws {
        let json = """
        {"status":"success","response":{"models":[
          {"id":"openai/gpt-5","name":"GPT-5","provider":"openai","description":"Smart","contextWindow":400000,"capabilities":["text-generation","structured-output"],"costTier":"medium","pricing":{"inputPerMillion":1.25,"outputPerMillion":10},"recommendedForFeature":true},
          {"id":"groq/llama","name":"Llama","provider":"groq","description":"Fast","contextWindow":128000,"capabilities":[],"costTier":"premium"}
        ]}}
        """
        let models = try decode(Endpoints.settingsAIModels(feature: .categorization), json)
        #expect(models.count == 2)
        #expect(models[0].recommendedForFeature)
        #expect(models[0].pricing?.inputPerMillion == Decimal(string: "1.25"))
        #expect(models[0].costTier == .medium)
        #expect(models[1].costTier == .unknown)
        #expect(models[1].pricing == nil)
        #expect(!models[1].recommendedForFeature)
    }

    @Test("Custom endpoints decode")
    func customEndpointsDecoding() throws {
        let json = """
        {"status":"success","response":[
          {"id":"0b8f6a8e-2d0a-4a51-9c1e-6a2f3d1b9e77","name":"Home Ollama","baseUrl":"http://ollama.lan/v1","defaultModel":"llama3.1:8b","hasApiKey":false,"createdAt":"2026-10-01T10:00:00.000Z","status":"valid","lastValidatedAt":"2026-10-01T10:00:00.000Z"}
        ]}
        """
        let endpoints = try decode(Endpoints.settingsAICustomEndpoints(), json)
        let endpoint = try #require(endpoints.first)
        #expect(endpoint.name == "Home Ollama")
        #expect(endpoint.baseUrl == "http://ollama.lan/v1")
        #expect(!endpoint.hasApiKey)
        #expect(endpoint.status == .valid)
    }

    @Test("Custom instructions decode null as nil")
    func customInstructionsDecoding() throws {
        let set = try decode(Endpoints.settingsAICustomInstructions(), #"{"status":"success","response":{"instructions":"Coffee is Dining"}}"#)
        #expect(set == "Coffee is Dining")
        let unset = try decode(Endpoints.settingsAICustomInstructions(), #"{"status":"success","response":{"instructions":null}}"#)
        #expect(unset == nil)
    }

    @Test("Endpoint test result decodes")
    func endpointTestResultDecoding() throws {
        let result = try decode(
            Endpoints.settingsAITestCustomEndpoint(.saved(endpointID: "e1")),
            #"{"status":"success","response":{"isValid":false,"error":"Connection refused"}}"#
        )
        #expect(!result.isValid)
        #expect(result.error == "Connection refused")
    }

    @Test("MCP connected apps decode")
    func connectedAppsDecoding() throws {
        let json = """
        {"status":"success","response":[
          {"clientId":"abc","name":"Claude","icon":null,"scopes":["openid","read"],"connectedAt":"2026-10-01T10:00:00.000Z","lastUsedAt":null}
        ]}
        """
        let apps = try decode(Endpoints.settingsMCPConnectedApps(), json)
        let app = try #require(apps.first)
        #expect(app.id == "abc")
        #expect(app.name == "Claude")
        #expect(app.scopes == ["openid", "read"])
        #expect(app.connectedAt != nil)
        #expect(app.lastUsedAt == nil)
    }

    // MARK: Requests

    @Test("Key writes send the provider and key")
    func keyRequests() throws {
        let set = Endpoints.settingsAISetKey(provider: .anthropic, apiKey: "sk-ant-1")
        #expect(try request(set).httpMethod == "PUT")
        #expect(try body(set)["provider"] as? String == "anthropic")
        #expect(try body(set)["apiKey"] as? String == "sk-ant-1")

        let delete = Endpoints.settingsAIDeleteKey(provider: .groq)
        #expect(try request(delete).httpMethod == "DELETE")
        #expect(try request(delete).url?.path() == "/api/v1/user/settings/ai/api-keys")
        #expect(try body(delete)["provider"] as? String == "groq")

        let deleteAll = Endpoints.settingsAIDeleteAllKeys()
        #expect(try request(deleteAll).url?.path() == "/api/v1/user/settings/ai/api-keys/all")
        #expect(try request(deleteAll).httpBody == nil)

        let makeDefault = Endpoints.settingsAISetDefaultProvider(.google)
        #expect(try request(makeDefault).url?.path() == "/api/v1/user/settings/ai/api-keys/default")
        #expect(try body(makeDefault)["provider"] as? String == "google")
    }

    @Test("Feature model writes use the feature's raw value in the path")
    func featureRequests() throws {
        let set = Endpoints.settingsAISetFeatureModel(feature: .statementParsing, modelId: "custom/qwen", customEndpointId: "e1")
        #expect(try request(set).url?.path() == "/api/v1/user/settings/ai/features/statement_parsing")
        #expect(try body(set)["modelId"] as? String == "custom/qwen")
        #expect(try body(set)["customEndpointId"] as? String == "e1")

        let catalog = Endpoints.settingsAISetFeatureModel(feature: .categorization, modelId: "openai/gpt-5")
        #expect(try body(catalog)["customEndpointId"] == nil)

        let reset = Endpoints.settingsAIResetFeature(.categorization)
        #expect(try request(reset).httpMethod == "DELETE")
        #expect(try request(reset).url?.path() == "/api/v1/user/settings/ai/features/categorization")

        let models = Endpoints.settingsAIModels(feature: .categorization)
        #expect(try request(models).url?.query() == "feature=categorization")
    }

    @Test("Custom endpoint create, update, and test bodies")
    func customEndpointRequests() throws {
        let create = Endpoints.settingsAICreateCustomEndpoint(name: "Home", baseUrl: "http://lan/v1", defaultModel: "llama", apiKey: nil)
        #expect(try request(create).httpMethod == "POST")
        #expect(try body(create)["name"] as? String == "Home")
        #expect(try body(create)["apiKey"] == nil || (try body(create)["apiKey"] is NSNull))

        let keep = Endpoints.settingsAIUpdateCustomEndpoint(id: "e1", SettingsAICustomEndpointUpdate(name: "Office"))
        #expect(try request(keep).url?.path() == "/api/v1/user/settings/ai/custom-endpoints/e1")
        #expect(try body(keep)["name"] as? String == "Office")
        #expect(try body(keep).keys.contains("apiKey") == false)

        let remove = Endpoints.settingsAIUpdateCustomEndpoint(id: "e1", SettingsAICustomEndpointUpdate(apiKey: .clear))
        #expect(try body(remove)["apiKey"] is NSNull)

        let replace = Endpoints.settingsAIUpdateCustomEndpoint(id: "e1", SettingsAICustomEndpointUpdate(apiKey: .set("k")))
        #expect(try body(replace)["apiKey"] as? String == "k")

        let saved = try body(Endpoints.settingsAITestCustomEndpoint(.saved(endpointID: "e1")))
        #expect(saved["endpointId"] as? String == "e1")
        #expect(saved.keys.count == 1)

        let typed = try body(Endpoints.settingsAITestCustomEndpoint(.typed(baseUrl: "http://lan/v1", defaultModel: "llama")))
        #expect(typed["baseUrl"] as? String == "http://lan/v1")
        #expect(typed["defaultModel"] as? String == "llama")
        #expect(typed["endpointId"] == nil)
    }

    @Test("Custom instructions and MCP revoke requests")
    func instructionsAndRevokeRequests() throws {
        let save = Endpoints.settingsAISetCustomInstructions("Rent is Housing")
        #expect(try request(save).httpMethod == "PUT")
        #expect(try body(save)["instructions"] as? String == "Rent is Housing")

        let revoke = Endpoints.settingsMCPRevokeConnectedApp(clientID: "abc")
        #expect(try request(revoke).httpMethod == "DELETE")
        #expect(try request(revoke).url?.path() == "/api/v1/user/settings/mcp/connected-apps/abc")

        #expect(Endpoints.settingsMCPServerURL(server: server).absoluteString == "https://budget.example.com/mcp")
    }
}
