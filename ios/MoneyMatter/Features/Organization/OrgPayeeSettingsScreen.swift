import MoneyMatterKit
import SwiftUI

/// Payee settings, mirroring the web Settings tab: payee detection from descriptions, the
/// promotion threshold, a bulk categorization mode, and the ignored-names list.
struct OrgPayeeSettingsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData

    @State private var settingsState: LoadState<OrgPayeeUserSettings> = .idle
    @State private var ignoredState: LoadState<[OrgPayeeIgnoredName]> = .idle
    @State private var bulkMode: OrgPayeeCategorizationMode = .enforce
    @State private var isConfirmingBulk = false
    @State private var newIgnoredName = ""
    @State private var pendingForceName: String?
    @State private var isWorking = false
    @State private var alert: ErrorAlert?
    @State private var notice: String?

    var body: some View {
        Form {
            detectionSection
            bulkSection
            ignoredSection
        }
        .navigationTitle("Payee Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .confirmationDialog(
            "Apply to all payees?",
            isPresented: $isConfirmingBulk,
            titleVisibility: .visible
        ) {
            Button("Apply \(OrgPayeeSupport.title(for: bulkMode))", role: .destructive) {
                Task { await applyBulkMode() }
            }
        } message: {
            Text("Every payee's categorization mode changes to \(OrgPayeeSupport.title(for: bulkMode)).")
        }
        .confirmationDialog(
            "A payee already uses this name",
            isPresented: Binding(get: { pendingForceName != nil }, set: { if !$0 { pendingForceName = nil } }),
            titleVisibility: .visible,
            presenting: pendingForceName
        ) { name in
            Button("Delete Payee and Ignore", role: .destructive) {
                Task { await addIgnoredName(name, force: true) }
            }
        } message: { name in
            Text("Ignoring \"\(name)\" deletes the matching payee and unlinks its transactions.")
        }
        .alert(
            "Done",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
            presenting: notice
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .errorAlert($alert)
    }

    // MARK: Sections

    @ViewBuilder
    private var detectionSection: some View {
        Section {
            switch settingsState {
            case .idle, .loading:
                Toggle("Detect Payees from Descriptions", isOn: .constant(false))
                    .redactedWhileLoading(true)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await loadSettings() }
            case .loaded(let settings):
                Toggle("Detect Payees from Descriptions", isOn: Binding(
                    get: { settings.payeeExtractionUsesDescription },
                    set: { value in Task { await patch(OrgPayeeSettingsPatch(payeeExtractionUsesDescription: value)) } }
                ))
                Picker("Create Payee After", selection: Binding(
                    get: { settings.payeePromotionThreshold },
                    set: { value in Task { await patch(OrgPayeeSettingsPatch(payeePromotionThreshold: value)) } }
                )) {
                    Text("1 transaction").tag(1)
                    Text("2 transactions").tag(2)
                    Text("3 transactions").tag(3)
                }
            }
        } header: {
            Text("Detection")
        } footer: {
            Text("When a bank sends no merchant name, the payee can be read from the description. A new name becomes a payee after it appears in the chosen number of transactions.")
        }
        .disabled(isWorking)
    }

    private var bulkSection: some View {
        Section {
            Picker("Categorization", selection: $bulkMode) {
                ForEach(OrgPayeeCategorizationMode.allCases, id: \.self) { mode in
                    Text(OrgPayeeSupport.title(for: mode)).tag(mode)
                }
            }
            Button("Apply to All Payees") { isConfirmingBulk = true }
                .disabled(isWorking)
        } header: {
            Text("Categorization for All Payees")
        } footer: {
            Text(OrgPayeeSupport.hint(for: bulkMode))
        }
    }

    @ViewBuilder
    private var ignoredSection: some View {
        Section {
            HStack {
                TextField("Name to ignore", text: $newIgnoredName)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await addIgnoredName(newIgnoredName, force: false) } }
                Button("Add") { Task { await addIgnoredName(newIgnoredName, force: false) } }
                    .disabled(newIgnoredName.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
            switch ignoredState {
            case .idle, .loading:
                ForEach(0..<3, id: \.self) { _ in
                    Text(verbatim: "Placeholder name")
                }
                .redactedWhileLoading(true)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await loadIgnored() }
            case .loaded(let names):
                if names.isEmpty {
                    Text("No ignored names.")
                        .foregroundStyle(.secondary)
                }
                ForEach(names) { row in
                    Text(row.displayName)
                        .swipeActions {
                            Button("Remove", role: .destructive) { Task { await removeIgnored(row) } }
                        }
                        .contextMenu {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                Task { await removeIgnored(row) }
                            }
                        }
                }
            }
        } header: {
            Text("Ignored Names")
        } footer: {
            Text("Names on this list never become payees, such as transfers or generic card descriptions.")
        }
    }

    // MARK: Loading and writes

    private func loadAll() async {
        async let settings: Void = loadSettings()
        async let ignored: Void = loadIgnored()
        _ = await (settings, ignored)
    }

    private func loadSettings() async {
        if settingsState.value == nil { settingsState = .loading }
        do {
            settingsState = .loaded(try await OrgPayeeSupport.client(services).send(Endpoints.orgPayeeUserSettings()))
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation, settingsState.value == nil { settingsState = .failed(apiError) }
        }
    }

    private func loadIgnored() async {
        if ignoredState.value == nil { ignoredState = .loading }
        do {
            ignoredState = .loaded(try await OrgPayeeSupport.client(services).send(Endpoints.orgPayeeIgnoredNames()))
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation, ignoredState.value == nil { ignoredState = .failed(apiError) }
        }
    }

    private func patch(_ patch: OrgPayeeSettingsPatch) async {
        isWorking = true
        defer { isWorking = false }
        do {
            settingsState = .loaded(try await OrgPayeeSupport.client(services).send(Endpoints.orgPatchPayeeSettings(patch)))
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func applyBulkMode() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await OrgPayeeSupport.client(services).send(Endpoints.orgBulkPayeeCategorizationMode(bulkMode))
            notice = String(localized: "Updated \(result.updatedCount) payees.")
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func addIgnoredName(_ raw: String, force: Bool) async {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await OrgPayeeSupport.client(services).send(Endpoints.orgAddPayeeIgnoredName(rawName: name, force: force))
            newIgnoredName = ""
            await loadIgnored()
            if force { await referenceData.refreshPayees() }
        } catch {
            if !force, OrgPayeeSupport.isConflict(error) {
                pendingForceName = name
            } else {
                alert = ErrorAlert(error)
            }
        }
    }

    private func removeIgnored(_ row: OrgPayeeIgnoredName) async {
        guard let current = ignoredState.value else { return }
        ignoredState = .loaded(current.filter { $0.id != row.id })
        do {
            _ = try await OrgPayeeSupport.client(services).send(Endpoints.orgRemovePayeeIgnoredName(id: row.id))
        } catch {
            ignoredState = .loaded(current)
            alert = ErrorAlert(error)
        }
    }
}
