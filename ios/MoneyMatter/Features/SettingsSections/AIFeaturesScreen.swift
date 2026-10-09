import MoneyMatterKit
import SwiftUI

/// Settings > AI > Features: which model answers each AI feature, and the custom
/// instructions categorization follows.
struct AIFeaturesScreen: View {
    @Environment(AppServices.self) private var services
    @State private var state: LoadState<[SettingsAIFeatureStatus]> = .idle
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("AI Features")
            .task {
                if case .idle = state { await load() }
            }
            .errorAlert($alert)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            List {
                ForEach(SettingsAIFeature.settingsAIConfigurable, id: \.self) { feature in
                    Section {
                        LabeledContent(feature.settingsAITitle, value: "Model name")
                    }
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let features):
            let shown = features.filter { SettingsAIFeature.settingsAIConfigurable.contains($0.feature) }
            if shown.isEmpty {
                ContentUnavailableView {
                    Label("No AI Features", systemImage: "sparkles")
                } description: {
                    Text("This server doesn't offer any configurable AI features.")
                } actions: {
                    Button("Reload") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            } else {
                List {
                    ForEach(shown) { status in
                        featureSection(status)
                    }
                }
                .refreshable { await load() }
            }
        }
    }

    private func featureSection(_ status: SettingsAIFeatureStatus) -> some View {
        Section {
            NavigationLink {
                SettingsAIModelPickerScreen(initialStatus: status) { updated in
                    replace(updated)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: status.feature.settingsAISymbol)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(status.feature.settingsAITitle)
                            .font(.body.weight(.medium))
                        Text(modelLabel(status))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            if !status.isConfigured {
                                SettingsAIBadge(text: "Default", tint: .secondary)
                            }
                            SettingsAIBadge(
                                text: status.usingUserKey ? "Your key" : "Server key",
                                tint: status.usingUserKey ? .green : .blue
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }

            if status.feature == .categorization {
                NavigationLink {
                    SettingsAICustomInstructionsScreen()
                } label: {
                    Label("Custom Instructions", systemImage: "text.badge.star")
                }
            }
        } footer: {
            Text(status.feature.settingsAIDescription)
        }
    }

    private func modelLabel(_ status: SettingsAIFeatureStatus) -> String {
        if status.isCustomModel, let endpoint = status.endpointName {
            return String(localized: "\(status.modelName) on \(endpoint)")
        }
        return status.modelName
    }

    private func replace(_ updated: SettingsAIFeatureStatus) {
        guard var features = state.value else { return }
        if let index = features.firstIndex(where: { $0.feature == updated.feature }) {
            features[index] = updated
            state = .loaded(features)
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await services.settingsAIClient().send(Endpoints.settingsAIFeatures()))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(apiError) }
        }
    }
}

// MARK: - Model picker

/// Everything the picker shows: the catalog flagged for this feature, the user's saved keys
/// (to mark models their key pays for), and their custom endpoints.
private struct SettingsAIModelCatalog {
    var models: [SettingsAIModel]
    var keyProviders: Set<SettingsAIProvider>
    var endpoints: [SettingsAICustomEndpoint]
}

/// Picks the model for one feature: a catalog model, or a model on one of the user's custom
/// endpoints. Each pick saves immediately.
private struct SettingsAIModelPickerScreen: View {
    let onChange: (SettingsAIFeatureStatus) -> Void

    @Environment(AppServices.self) private var services
    @State private var status: SettingsAIFeatureStatus
    @State private var catalog: LoadState<SettingsAIModelCatalog> = .idle
    @State private var savingID: String?
    @State private var customTarget: SettingsAICustomEndpoint?
    @State private var confirmsReset = false
    @State private var alert: ErrorAlert?

    init(initialStatus: SettingsAIFeatureStatus, onChange: @escaping (SettingsAIFeatureStatus) -> Void) {
        self.onChange = onChange
        _status = State(initialValue: initialStatus)
    }

    var body: some View {
        content
            .navigationTitle(status.feature.settingsAITitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if status.isConfigured {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Reset") { confirmsReset = true }
                            .disabled(savingID != nil)
                    }
                }
            }
            .task {
                if case .idle = catalog { await load() }
            }
            .confirmationDialog("Use the default model?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Reset to Default", role: .destructive) { reset() }
            } message: {
                Text("\(status.feature.settingsAITitle) goes back to the server's recommended model.")
            }
            .sheet(item: $customTarget) { endpoint in
                SettingsAICustomModelSheet(
                    endpoint: endpoint,
                    initialModel: status.isCustomModel && status.customEndpointId == endpoint.id
                        ? status.modelName
                        : endpoint.defaultModel
                ) { modelName in
                    try await apply(
                        modelID: SettingsAIModel.customModelID(name: modelName),
                        customEndpointID: endpoint.id
                    )
                }
            }
            .errorAlert($alert)
    }

    @ViewBuilder
    private var content: some View {
        switch catalog {
        case .idle, .loading:
            List {
                Section {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading) {
                            Text("Model name")
                            Text("A description of the model").font(.caption)
                        }
                    }
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let catalog):
            list(catalog)
        }
    }

    private func list(_ catalog: SettingsAIModelCatalog) -> some View {
        let recommended = catalog.models.filter(\.recommendedForFeature)
        let others = catalog.models.filter { !$0.recommendedForFeature }
        let providers = SettingsAIProvider.allCases.filter { provider in others.contains { $0.provider == provider } }

        return List {
            Section {
                LabeledContent("Current Model", value: status.modelName)
                if let endpoint = status.endpointName, status.isCustomModel {
                    LabeledContent("Endpoint", value: endpoint)
                }
            } footer: {
                Text(status.usingUserKey
                    ? "Calls are paid with your own key or endpoint."
                    : "Calls use the server's key. Add your own key to pay for them directly.")
            }

            if !recommended.isEmpty {
                Section("Recommended") {
                    ForEach(recommended) { model in
                        modelRow(model, hasUserKey: catalog.keyProviders.contains(model.provider))
                    }
                }
            }

            ForEach(providers) { provider in
                Section(provider.settingsAIDisplayName) {
                    ForEach(others.filter { $0.provider == provider }) { model in
                        modelRow(model, hasUserKey: catalog.keyProviders.contains(model.provider))
                    }
                }
            }

            Section {
                if catalog.endpoints.isEmpty {
                    NavigationLink {
                        AIEndpointsScreen()
                    } label: {
                        Label("Add a Custom Endpoint", systemImage: "plus.circle")
                    }
                } else {
                    ForEach(catalog.endpoints) { endpoint in
                        endpointRow(endpoint)
                    }
                }
            } header: {
                Text("Your Endpoints")
            } footer: {
                Text("Run this feature on a model served by your own OpenAI-compatible endpoint.")
            }
        }
        .refreshable { await load() }
    }

    private func modelRow(_ model: SettingsAIModel, hasUserKey: Bool) -> some View {
        let isSelected = !status.isCustomModel && status.modelId == model.id
        return Button {
            guard !isSelected else { return }
            Task {
                do {
                    try await apply(modelID: model.id, customEndpointID: nil)
                } catch {
                    alert = ErrorAlert(error)
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        if hasUserKey {
                            SettingsAIBadge(text: "Your key", tint: .green)
                        }
                    }
                    if !model.description.isEmpty {
                        Text(model.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(details(model))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if savingID == model.id {
                    ProgressView()
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .disabled(savingID != nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func endpointRow(_ endpoint: SettingsAICustomEndpoint) -> some View {
        let isSelected = status.isCustomModel && status.customEndpointId == endpoint.id
        return Button {
            customTarget = endpoint
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(endpoint.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(isSelected ? status.modelName : endpoint.defaultModel)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if endpoint.status == .invalid {
                        SettingsAICredentialProblem(lastError: endpoint.lastError)
                    }
                }
                Spacer(minLength: 0)
                if savingID == endpoint.id {
                    ProgressView()
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .disabled(savingID != nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Choose the model to use on this endpoint")
    }

    private func details(_ model: SettingsAIModel) -> String {
        var parts: [String] = []
        if let cost = model.costTier.settingsAILabel { parts.append(cost) }
        if model.contextWindow > 0 {
            let tokens = model.contextWindow.formatted(.number.notation(.compactName))
            parts.append(String(localized: "\(tokens) context"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Data

    private func load() async {
        if catalog.value == nil { catalog = .loading }
        do {
            let client = try services.settingsAIClient()
            async let models = client.send(Endpoints.settingsAIModels(feature: status.feature))
            async let keys = client.send(Endpoints.settingsAIKeyStatus())
            async let endpoints = client.send(Endpoints.settingsAICustomEndpoints())
            let loaded = SettingsAIModelCatalog(
                models: try await models,
                keyProviders: Set(try await keys.providers.map(\.provider)),
                endpoints: try await endpoints
            )
            catalog = .loaded(loaded)
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if catalog.value == nil { catalog = .failed(apiError) } else { alert = ErrorAlert(apiError) }
        }
    }

    /// Saves a pick. Throws so the custom-model sheet can stay open on a refusal.
    private func apply(modelID: String, customEndpointID: String?) async throws {
        savingID = customEndpointID ?? modelID
        defer { savingID = nil }
        let updated = try await services.settingsAIClient().send(Endpoints.settingsAISetFeatureModel(
            feature: status.feature,
            modelId: modelID,
            customEndpointId: customEndpointID
        ))
        status = updated
        onChange(updated)
    }

    private func reset() {
        savingID = status.modelId
        Task {
            defer { savingID = nil }
            do {
                let updated = try await services.settingsAIClient().send(Endpoints.settingsAIResetFeature(status.feature))
                status = updated
                onChange(updated)
            } catch {
                alert = ErrorAlert(error)
            }
        }
    }
}

/// Names the model to use on a custom endpoint. The server probes the endpoint with it
/// before saving, so a refusal keeps the sheet open with the reason.
private struct SettingsAICustomModelSheet: View {
    let endpoint: SettingsAICustomEndpoint
    let apply: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var modelName: String
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    init(endpoint: SettingsAICustomEndpoint, initialModel: String, apply: @escaping (String) async throws -> Void) {
        self.endpoint = endpoint
        self.apply = apply
        _modelName = State(initialValue: initialModel)
    }

    private var trimmed: String { modelName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Model", text: $modelName, prompt: Text(verbatim: endpoint.defaultModel))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("Model on \(endpoint.name)")
                } footer: {
                    Text("Sent to the endpoint exactly as typed, e.g. llama3.1:8b.")
                }
            }
            .navigationTitle("Custom Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Use Model") { submit() }
                            .disabled(trimmed.isEmpty || trimmed.count > 200)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($alert)
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await apply(trimmed)
                dismiss()
            } catch {
                alert = ErrorAlert(error)
            }
        }
    }
}

// MARK: - Custom instructions

/// Free-text guidance appended to every categorization request, e.g. "Coffee shops are Dining".
private struct SettingsAICustomInstructionsScreen: View {
    private static let maxLength = 2000

    @Environment(AppServices.self) private var services
    @State private var state: LoadState<String> = .idle
    @State private var text = ""
    @State private var isSaving = false
    @State private var alert: ErrorAlert?
    @FocusState private var isFocused: Bool

    private var isOverLimit: Bool { text.count > Self.maxLength }
    private var hasChanges: Bool { state.value.map { $0 != text } ?? false }

    var body: some View {
        content
            .navigationTitle("Custom Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(!hasChanges || isOverLimit)
                    }
                }
            }
            .task {
                if case .idle = state { await load() }
            }
            .errorAlert($alert)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            Form {
                Section {
                    Text("Loading the saved instructions for categorization")
                        .frame(minHeight: 160, alignment: .topLeading)
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded:
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .focused($isFocused)
                        .accessibilityLabel("Instructions")
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("For example: Transfers to Jane are Rent. Coffee shops are Dining Out.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } footer: {
                    HStack(alignment: .top) {
                        Text("AI categorization follows these rules for every transaction it categorizes.")
                        Spacer()
                        Text("\(text.count)/\(Self.maxLength)")
                            .monospacedDigit()
                            .foregroundStyle(isOverLimit ? .red : .secondary)
                    }
                }

                if !text.isEmpty {
                    Section {
                        Button("Clear Instructions", role: .destructive) { text = "" }
                    }
                }
            }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let saved = try await services.settingsAIClient().send(Endpoints.settingsAICustomInstructions()) ?? ""
            state = .loaded(saved)
            text = saved
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(apiError) }
        }
    }

    private func save() {
        isSaving = true
        isFocused = false
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isSaving = false }
            do {
                _ = try await services.settingsAIClient().send(Endpoints.settingsAISetCustomInstructions(value))
                text = value
                state = .loaded(value)
            } catch {
                alert = ErrorAlert(error)
            }
        }
    }
}
