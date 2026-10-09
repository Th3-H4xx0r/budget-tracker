import MoneyMatterKit
import SwiftUI

/// Automation rules that categorize, tag, and annotate incoming transactions, matching the
/// web's `pages/automations`. Rules run top to bottom, so the list can be reordered.
struct AutomationsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var state: LoadState<[OrgAutomation]> = .idle
    @State private var isCreating = false
    @State private var pendingDelete: OrgAutomation?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Automations")
            .toolbar {
                if let rules = state.value, rules.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("New Automation", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(isPresented: $isCreating) {
                OrgAutomationEditorScreen(rule: nil) {
                    await load()
                }
            }
            .confirmationDialog(
                "Delete Automation?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { rule in
                Button("Delete Automation", role: .destructive) {
                    Task { await delete(rule) }
                }
            } message: { rule in
                Text("“\(rule.name)” stops running. Transactions it already changed keep their changes.")
            }
            .errorAlert($alert)
            .task {
                await referenceData.loadIfNeeded()
                if state.value == nil { await load() }
            }
            .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            List {
                ForEach(0..<4, id: \.self) { _ in
                    OrgAutomationRow(rule: OrgAutomation(id: "", name: "Placeholder rule name"), summary: "Placeholder summary", setEnabled: { _ in })
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let rules):
            if rules.isEmpty {
                ContentUnavailableView {
                    Label("No Automations", systemImage: "wand.and.stars")
                } description: {
                    Text("Set the category, tags, payee, or note of new transactions automatically when they match your conditions.")
                } actions: {
                    Button("New Automation") { isCreating = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        ForEach(rules) { rule in
                            NavigationLink {
                                OrgAutomationEditorScreen(rule: rule) {
                                    await load()
                                }
                            } label: {
                                OrgAutomationRow(rule: rule, summary: summary(rule)) { isOn in
                                    Task { await setEnabled(rule, isOn: isOn) }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button(
                                    rule.isEnabled ? LocalizedStringKey("Disable") : LocalizedStringKey("Enable"),
                                    systemImage: rule.isEnabled ? "pause.circle" : "play.circle"
                                ) {
                                    Task { await setEnabled(rule, isOn: !rule.isEnabled) }
                                }
                                .tint(rule.isEnabled ? .orange : .green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    pendingDelete = rule
                                }
                            }
                            .contextMenu {
                                Button(rule.isEnabled ? LocalizedStringKey("Disable") : LocalizedStringKey("Enable"), systemImage: rule.isEnabled ? "pause.circle" : "play.circle") {
                                    Task { await setEnabled(rule, isOn: !rule.isEnabled) }
                                }
                                Button("Delete Automation", systemImage: "trash", role: .destructive) {
                                    pendingDelete = rule
                                }
                            }
                        }
                        .onMove { source, destination in
                            Task { await move(rules, from: source, to: destination) }
                        }
                    } footer: {
                        Text("Rules run from top to bottom on new transactions.")
                    }
                }
            }
        }
    }

    /// A short "When … then …" line built from the parts the app can resolve.
    private func summary(_ rule: OrgAutomation) -> String {
        let conditions = rule.conditions.items.count
        let actions = rule.actions.map { action -> String in
            switch action {
            case .setCategory(let id):
                String(localized: "Category: \(referenceData.category(id: id)?.name ?? String(localized: "Unknown"))")
            case .addTags(let ids):
                String(localized: "Tags: \(ids.compactMap { referenceData.tag(id: $0)?.name }.joined(separator: ", "))")
            case .setPayee(let id):
                String(localized: "Payee: \(referenceData.payee(id: id)?.name ?? String(localized: "Unknown"))")
            case .setNote:
                String(localized: "Note")
            case .unknown:
                String(localized: "Other action")
            }
        }
        let conditionText = conditions == 1
            ? String(localized: "1 condition")
            : String(localized: "\(conditions) conditions")
        return ([conditionText] + actions).joined(separator: " · ")
    }

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            let rules = try await client.send(Endpoints.orgAutomations())
            state = .loaded(rules.sorted { $0.position < $1.position })
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(error) }
        }
    }

    private func replace(_ rule: OrgAutomation) {
        guard case .loaded(var rules) = state, let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        state = .loaded(rules)
    }

    private func setEnabled(_ rule: OrgAutomation, isOn: Bool) async {
        guard let client = services.client, rule.isEnabled != isOn else { return }
        do {
            let updated = try await client.send(Endpoints.orgUpdateAutomation(id: rule.id, OrgAutomationPayload(isEnabled: isOn)))
            replace(updated)
        } catch {
            alert = ErrorAlert(error)
            await load()
        }
    }

    private func move(_ rules: [OrgAutomation], from source: IndexSet, to destination: Int) async {
        guard let client = services.client else { return }
        var reordered = rules
        reordered.move(fromOffsets: source, toOffset: destination)
        state = .loaded(reordered)
        do {
            let saved = try await client.send(Endpoints.orgReorderAutomations(ids: reordered.map(\.id)))
            state = .loaded(saved.sorted { $0.position < $1.position })
        } catch {
            alert = ErrorAlert(error)
            await load()
        }
    }

    private func delete(_ rule: OrgAutomation) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.orgDeleteAutomation(id: rule.id))
            if case .loaded(let rules) = state {
                state = .loaded(rules.filter { $0.id != rule.id })
            }
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// One rule: name, summary, match stats, a paused warning, and its on/off switch.
struct OrgAutomationRow: View {
    let rule: OrgAutomation
    let summary: String
    let setEnabled: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let paused = rule.pausedReason {
                    Label {
                        Text("Paused: “\(paused.label ?? String(localized: "an item"))” was deleted")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else if rule.matchCount > 0 {
                    Group {
                        if let last = rule.lastMatchedAt {
                            Text("Matched \(rule.matchCount) times · last \(last, format: .relative(presentation: .named))")
                        } else {
                            Text("Matched \(rule.matchCount) times")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            Toggle(
                "Enabled",
                isOn: Binding(get: { rule.isEnabled }, set: { setEnabled($0) })
            )
            .labelsHidden()
            .accessibilityLabel(Text("Enable \(rule.name)"))
        }
        .padding(.vertical, 2)
    }
}
