import MoneyMatterKit
import SwiftUI

/// Settings > AI > API Keys: the user's own provider keys, which pay for AI features
/// instead of the server's. Keys are write-only; only their status comes back.
struct AIKeysScreen: View {
    @Environment(AppServices.self) private var services
    @State private var state: LoadState<SettingsAIKeyStatus> = .idle
    @State private var alert: ErrorAlert?
    @State private var addingProvider: SettingsAIProvider?
    @State private var pendingDelete: SettingsAIProvider?
    @State private var confirmsDeleteAll = false
    @State private var isWorking = false

    var body: some View {
        content
            .navigationTitle("API Keys")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addingProvider = firstUnconfiguredProvider
                    } label: {
                        Label("Add Key", systemImage: "plus")
                    }
                    .disabled(state.value == nil || isWorking)
                }
            }
            .task {
                if case .idle = state { await load() }
            }
            .sheet(item: $addingProvider) { provider in
                SettingsAIKeyEditorSheet(
                    initialProvider: provider,
                    configuredProviders: Set(configured.map(\.provider))
                ) { savedProvider, key in
                    _ = try await services.settingsAIClient().send(Endpoints.settingsAISetKey(provider: savedProvider, apiKey: key))
                    await load()
                }
            }
            .confirmationDialog(
                "Remove this API key?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { provider in
                Button("Remove \(provider.settingsAIDisplayName) Key", role: .destructive) {
                    mutate { _ = try await $0.send(Endpoints.settingsAIDeleteKey(provider: provider)) }
                }
            } message: { _ in
                Text("Features using this provider fall back to the server's key, if it allows one.")
            }
            .confirmationDialog("Remove all API keys?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
                Button("Remove All Keys", role: .destructive) {
                    mutate { _ = try await $0.send(Endpoints.settingsAIDeleteAllKeys()) }
                }
            } message: {
                Text("Every saved provider key is deleted. This can't be undone.")
            }
            .errorAlert($alert)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            List {
                Section {
                    ForEach(0..<2, id: \.self) { _ in
                        LabeledContent("Provider name", value: "Valid")
                    }
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let status):
            if status.providers.isEmpty {
                ContentUnavailableView {
                    Label("No API Keys", systemImage: "key")
                } description: {
                    Text("Add a key from Anthropic, OpenAI, Google, or Groq to run AI features on your own account.")
                } actions: {
                    Button("Add Key") { addingProvider = .anthropic }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                list(status)
            }
        }
    }

    private func list(_ status: SettingsAIKeyStatus) -> some View {
        List {
            Section {
                ForEach(configured) { info in
                    keyRow(info, isDefault: info.provider == status.defaultProvider)
                }
            } header: {
                Text("Saved Keys")
            } footer: {
                Text("Keys are stored encrypted and are never shown again after saving.")
            }

            Section {
                Button("Remove All Keys", role: .destructive) { confirmsDeleteAll = true }
                    .disabled(isWorking)
            }
        }
        .refreshable { await load() }
    }

    private func keyRow(_ info: SettingsAIKeyInfo, isDefault: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(info.provider.settingsAIDisplayName)
                    .font(.body.weight(.medium))
                if isDefault {
                    SettingsAIBadge(text: "Default")
                }
                Spacer()
                if info.status == .valid {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Valid")
                }
            }
            if let createdAt = info.createdAt {
                Text("Added \(createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if info.status == .invalid {
                SettingsAICredentialProblem(lastError: info.lastError)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button("Remove", systemImage: "trash", role: .destructive) { pendingDelete = info.provider }
        }
        .contextMenu {
            Button("Replace Key", systemImage: "arrow.triangle.2.circlepath") { addingProvider = info.provider }
            if !isDefault && configured.count > 1 {
                Button("Make Default", systemImage: "star") {
                    mutate { _ = try await $0.send(Endpoints.settingsAISetDefaultProvider(info.provider)) }
                }
            }
            Button("Remove", systemImage: "trash", role: .destructive) { pendingDelete = info.provider }
        }
    }

    // MARK: Data

    /// Saved keys in the web's provider order.
    private var configured: [SettingsAIKeyInfo] {
        let providers = state.value?.providers ?? []
        return providers.sorted { lhs, rhs in
            let order = SettingsAIProvider.keyProviders
            return (order.firstIndex(of: lhs.provider) ?? order.count) < (order.firstIndex(of: rhs.provider) ?? order.count)
        }
    }

    private var firstUnconfiguredProvider: SettingsAIProvider {
        let saved = Set(configured.map(\.provider))
        return SettingsAIProvider.keyProviders.first { !saved.contains($0) } ?? .anthropic
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await services.settingsAIClient().send(Endpoints.settingsAIKeyStatus()))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(apiError) }
        }
    }

    private func mutate(_ action: @escaping (APIClient) async throws -> Void) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await action(services.settingsAIClient())
            } catch {
                alert = ErrorAlert(error)
            }
            await load()
        }
    }
}

/// Adds or replaces one provider's key. The server validates the key before saving it.
private struct SettingsAIKeyEditorSheet: View {
    let configuredProviders: Set<SettingsAIProvider>
    let save: (SettingsAIProvider, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var provider: SettingsAIProvider
    @State private var apiKey = ""
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    init(
        initialProvider: SettingsAIProvider,
        configuredProviders: Set<SettingsAIProvider>,
        save: @escaping (SettingsAIProvider, String) async throws -> Void
    ) {
        self.configuredProviders = configuredProviders
        self.save = save
        _provider = State(initialValue: initialProvider)
    }

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $provider) {
                        ForEach(SettingsAIProvider.keyProviders) { provider in
                            Text(provider.settingsAIDisplayName).tag(provider)
                        }
                    }
                    SecureField(provider.settingsAIKeyPlaceholder, text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .accessibilityLabel("API Key")
                } footer: {
                    if configuredProviders.contains(provider) {
                        Text("Saving replaces the \(provider.settingsAIDisplayName) key you already have.")
                    } else {
                        Text("The key is checked with \(provider.settingsAIDisplayName) before it's saved.")
                    }
                }
            }
            .navigationTitle(configuredProviders.contains(provider) ? "Replace API Key" : "Add API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { submit() }
                            .disabled(trimmedKey.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($alert)
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await save(provider, trimmedKey)
                dismiss()
            } catch {
                alert = ErrorAlert(error)
            }
        }
    }
}
