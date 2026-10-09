import MoneyMatterKit
import SwiftUI

/// Settings > AI > Endpoints: the user's own OpenAI-compatible endpoints (Ollama, vLLM,
/// LM Studio, a proxy), which AI features can then use as their model.
struct AIEndpointsScreen: View {
    @Environment(AppServices.self) private var services
    @State private var state: LoadState<[SettingsAICustomEndpoint]> = .idle
    @State private var alert: ErrorAlert?
    @State private var editor: SettingsAIEndpointEditorTarget?
    @State private var pendingDelete: SettingsAICustomEndpoint?
    @State private var testingID: String?
    @State private var testOutcome: SettingsAIEndpointTestOutcome?

    var body: some View {
        content
            .navigationTitle("Endpoints")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .create
                    } label: {
                        Label("Add Endpoint", systemImage: "plus")
                    }
                    .disabled(state.value == nil)
                }
            }
            .task {
                if case .idle = state { await load() }
            }
            .sheet(item: $editor) { target in
                SettingsAIEndpointEditorSheet(target: target) { await load() }
            }
            .confirmationDialog(
                "Delete this endpoint?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { endpoint in
                Button("Delete \(endpoint.name)", role: .destructive) { delete(endpoint) }
            } message: { _ in
                Text("Features using one of its models go back to the default model.")
            }
            .alert(
                testOutcome?.title ?? "",
                isPresented: Binding(get: { testOutcome != nil }, set: { if !$0 { testOutcome = nil } }),
                presenting: testOutcome
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { outcome in
                Text(outcome.message)
            }
            .errorAlert($alert)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            List {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading) {
                        Text("Endpoint name")
                        Text("https://example.com/v1").font(.caption)
                    }
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let endpoints):
            if endpoints.isEmpty {
                ContentUnavailableView {
                    Label("No Custom Endpoints", systemImage: "server.rack")
                } description: {
                    Text("Connect an OpenAI-compatible endpoint, such as Ollama, vLLM, or LM Studio, to run AI features on your own models.")
                } actions: {
                    Button("Add Endpoint") { editor = .create }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        ForEach(endpoints) { endpoint in
                            row(endpoint)
                        }
                    } footer: {
                        Text("Pick an endpoint's model for a feature in AI Features.")
                    }
                }
                .refreshable { await load() }
            }
        }
    }

    private func row(_ endpoint: SettingsAICustomEndpoint) -> some View {
        Button {
            editor = .edit(endpoint)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(endpoint.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(endpoint.baseUrl)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text("Model: \(endpoint.defaultModel)")
                        Text(verbatim: "·")
                        Text(endpoint.hasApiKey ? "Key saved" : "No key")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if endpoint.status == .invalid {
                        SettingsAICredentialProblem(lastError: endpoint.lastError)
                    }
                }
                Spacer(minLength: 0)
                if testingID == endpoint.id {
                    ProgressView()
                }
            }
            .contentShape(.rect)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edits the endpoint")
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = endpoint }
        }
        .swipeActions(edge: .leading) {
            Button("Test", systemImage: "bolt.horizontal") { test(endpoint) }
                .tint(.blue)
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editor = .edit(endpoint) }
            Button("Test Connection", systemImage: "bolt.horizontal") { test(endpoint) }
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = endpoint }
        }
    }

    // MARK: Data

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await services.settingsAIClient().send(Endpoints.settingsAICustomEndpoints()))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(apiError) }
        }
    }

    private func delete(_ endpoint: SettingsAICustomEndpoint) {
        Task {
            do {
                _ = try await services.settingsAIClient().send(Endpoints.settingsAIDeleteCustomEndpoint(id: endpoint.id))
            } catch {
                alert = ErrorAlert(error)
            }
            await load()
        }
    }

    private func test(_ endpoint: SettingsAICustomEndpoint) {
        testingID = endpoint.id
        Task {
            defer { testingID = nil }
            do {
                let result = try await services.settingsAIClient()
                    .send(Endpoints.settingsAITestCustomEndpoint(.saved(endpointID: endpoint.id)))
                testOutcome = SettingsAIEndpointTestOutcome(result)
            } catch {
                alert = ErrorAlert(error)
            }
            // A test refreshes the stored status, so the invalid badge follows it.
            await load()
        }
    }
}

/// What the endpoint sheet edits.
enum SettingsAIEndpointEditorTarget: Identifiable {
    case create
    case edit(SettingsAICustomEndpoint)

    var id: String {
        switch self {
        case .create: "new"
        case .edit(let endpoint): endpoint.id
        }
    }
}

/// The result of a connection test, phrased for an alert or an inline row.
struct SettingsAIEndpointTestOutcome: Equatable {
    let isValid: Bool
    let message: String

    init(_ result: SettingsAIEndpointTestResult) {
        isValid = result.isValid
        message = result.isValid
            ? String(localized: "The endpoint answered with the model.")
            : (result.error ?? String(localized: "The endpoint didn't answer."))
    }

    var title: String {
        isValid ? String(localized: "Connection Works") : String(localized: "Connection Failed")
    }
}

/// Creates an endpoint, or edits one: changed fields only, and the stored key is kept unless
/// a new one is typed or it's removed.
private struct SettingsAIEndpointEditorSheet: View {
    let target: SettingsAIEndpointEditorTarget
    let onSaved: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var baseURL: String
    @State private var defaultModel: String
    @State private var apiKey = ""
    @State private var hasStoredKey: Bool
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var testOutcome: SettingsAIEndpointTestOutcome?
    @State private var confirmsRemoveKey = false
    @State private var alert: ErrorAlert?

    init(target: SettingsAIEndpointEditorTarget, onSaved: @escaping () async -> Void) {
        self.target = target
        self.onSaved = onSaved
        switch target {
        case .create:
            _name = State(initialValue: "")
            _baseURL = State(initialValue: "")
            _defaultModel = State(initialValue: "")
            _hasStoredKey = State(initialValue: false)
        case .edit(let endpoint):
            _name = State(initialValue: endpoint.name)
            _baseURL = State(initialValue: endpoint.baseUrl)
            _defaultModel = State(initialValue: endpoint.defaultModel)
            _hasStoredKey = State(initialValue: endpoint.hasApiKey)
        }
    }

    private var existing: SettingsAICustomEndpoint? {
        if case .edit(let endpoint) = target { return endpoint }
        return nil
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedURL: String { baseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedModel: String { defaultModel.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isURLValid: Bool {
        guard let url = URL(string: trimmedURL), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host() != nil
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 50 && isURLValid && !trimmedModel.isEmpty && trimmedModel.count <= 200
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Home Ollama"))
                    TextField("Base URL", text: $baseURL, prompt: Text(verbatim: "http://localhost:11434/v1"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Default Model", text: $defaultModel, prompt: Text(verbatim: "llama3.1:8b"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    if !trimmedURL.isEmpty && !isURLValid {
                        Text("Enter an http or https URL, such as http://localhost:11434/v1.")
                            .foregroundStyle(.red)
                    } else {
                        Text("The endpoint root, usually ending in /v1. The model name is sent exactly as typed.")
                    }
                }

                Section {
                    SecureField(
                        hasStoredKey ? String(localized: "Leave blank to keep the saved key") : String(localized: "Optional"),
                        text: $apiKey
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("API Key")
                    if hasStoredKey, existing != nil {
                        Button("Remove Saved Key", role: .destructive) { confirmsRemoveKey = true }
                            .disabled(isSaving)
                    }
                } header: {
                    Text("API Key")
                } footer: {
                    Text("Only needed if the endpoint requires authentication.")
                }

                Section {
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "bolt.horizontal")
                            Spacer()
                            if isTesting { ProgressView() }
                        }
                    }
                    .disabled(!isURLValid || trimmedModel.isEmpty || isTesting)
                    if let testOutcome {
                        Label {
                            Text(testOutcome.message)
                        } icon: {
                            Image(systemName: testOutcome.isValid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(testOutcome.isValid ? .green : .red)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Endpoint" : "Edit Endpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(!canSave)
                    }
                }
            }
            .onChange(of: [baseURL, defaultModel, apiKey]) { testOutcome = nil }
            .confirmationDialog("Remove the saved key?", isPresented: $confirmsRemoveKey, titleVisibility: .visible) {
                Button("Remove Key", role: .destructive) { removeKey() }
            } message: {
                Text("The endpoint is called without authentication from now on.")
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($alert)
        }
    }

    private func runTest() {
        isTesting = true
        let request: SettingsAIEndpointTestRequest = if let existing {
            .saved(endpointID: existing.id, baseUrl: trimmedURL, defaultModel: trimmedModel, apiKey: trimmedKey.isEmpty ? nil : trimmedKey)
        } else {
            .typed(baseUrl: trimmedURL, defaultModel: trimmedModel, apiKey: trimmedKey.isEmpty ? nil : trimmedKey)
        }
        Task {
            defer { isTesting = false }
            do {
                let result = try await services.settingsAIClient().send(Endpoints.settingsAITestCustomEndpoint(request))
                testOutcome = SettingsAIEndpointTestOutcome(result)
            } catch {
                alert = ErrorAlert(error)
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let client = try services.settingsAIClient()
                if let existing {
                    let update = SettingsAICustomEndpointUpdate(
                        name: trimmedName == existing.name ? nil : trimmedName,
                        baseUrl: trimmedURL == existing.baseUrl ? nil : trimmedURL,
                        defaultModel: trimmedModel == existing.defaultModel ? nil : trimmedModel,
                        apiKey: trimmedKey.isEmpty ? .unchanged : .set(trimmedKey)
                    )
                    _ = try await client.send(Endpoints.settingsAIUpdateCustomEndpoint(id: existing.id, update))
                } else {
                    _ = try await client.send(Endpoints.settingsAICreateCustomEndpoint(
                        name: trimmedName,
                        baseUrl: trimmedURL,
                        defaultModel: trimmedModel,
                        apiKey: trimmedKey.isEmpty ? nil : trimmedKey
                    ))
                }
                await onSaved()
                dismiss()
            } catch {
                alert = ErrorAlert(error)
            }
        }
    }

    private func removeKey() {
        guard let existing else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let updated = try await services.settingsAIClient()
                    .send(Endpoints.settingsAIUpdateCustomEndpoint(id: existing.id, SettingsAICustomEndpointUpdate(apiKey: .clear)))
                hasStoredKey = updated.hasApiKey
                apiKey = ""
                await onSaved()
            } catch {
                alert = ErrorAlert(error)
            }
        }
    }
}
