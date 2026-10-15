import MoneyMatterKit
import SwiftUI

/// AI categorization: the setup in use, run progress, transactions waiting for a category,
/// and past runs.
struct DataAICategorizationScreen: View {
    private enum Tab: Hashable { case categorize, history }

    @Environment(AppServices.self) private var services
    @State private var tab: Tab = .categorize
    @State private var feature: LoadState<DataAIFeatureStatus?> = .idle
    @State private var status: DataAICategorizationStatus?
    @State private var lastFinished: DataAICategorizationStatus?
    @State private var candidates: LoadState<[Transaction]> = .idle
    @State private var candidateTotal: Int?
    @State private var hasMoreCandidates = false
    @State private var selection: Set<String> = []
    @State private var editMode: EditMode = .inactive
    @State private var confirmsRunAll = false
    @State private var isTriggering = false
    @State private var alert: ErrorAlert?

    private let pageSize = 30
    private let maxPerRun = 5000

    var body: some View {
        List(selection: $selection) {
            Section {
                Picker("View", selection: $tab) {
                    Text("Categorize").tag(Tab.categorize)
                    Text("History").tag(Tab.history)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            setupSection
            runSection
            switch tab {
            case .categorize: candidatesSection
            case .history: DataAICategorizationHistorySection()
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("AI Categorization")
        .toolbar { toolbar }
        .refreshable { await reload() }
        .task { await reload() }
        .task(id: status?.status.isActive) { await pollWhileActive() }
        .confirmationDialog(
            "Categorize with AI?",
            isPresented: $confirmsRunAll,
            titleVisibility: .visible
        ) {
            Button("Categorize \(min(candidateTotal ?? 0, maxPerRun)) Transactions") {
                Task { await trigger(ids: nil) }
            }
        } message: {
            Text("AI assigns categories to transactions in your default category. Up to \(maxPerRun) transactions are processed per run.")
        }
        .errorAlert($alert)
    }

    // MARK: Sections

    @ViewBuilder
    private var setupSection: some View {
        switch feature {
        case .idle, .loading:
            Section {
                LabeledContent("Model", value: "Placeholder model")
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            Section {
                InlineRetryView(ErrorMessage.message(for: error)) { await loadFeature() }
            }
        case .loaded(let status):
            Section {
                if let status, status.isReadyToCategorize {
                    LabeledContent("Model", value: status.modelName ?? String(localized: "Default"))
                    if let endpoint = status.endpointName {
                        LabeledContent("Endpoint", value: endpoint)
                    }
                    LabeledContent("Credentials") {
                        Text(status.usingUserKey ? String(localized: "Your API key") : String(localized: "Shared key (3 runs per hour)"))
                    }
                } else {
                    Label("AI categorization isn't set up. Configure a model in Settings › AI.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                }
            } header: {
                Text("Setup")
            }
        }
    }

    @ViewBuilder
    private var runSection: some View {
        if let status, status.status.isActive {
            Section("Running") {
                VStack(alignment: .leading, spacing: 8) {
                    if let fraction = status.fraction {
                        ProgressView(value: fraction) {
                            Text("Categorizing…")
                        } currentValueLabel: {
                            Text("\(status.processedCount) of \(status.totalCount)").monospacedDigit()
                        }
                    } else {
                        ProgressView { Text("Waiting to start…") }
                    }
                }
                .padding(.vertical, 4)
            }
        } else if let lastFinished {
            Section {
                if lastFinished.status == .failed {
                    Label(lastFinished.errorMessage ?? String(localized: "The run failed."), systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                } else {
                    Label("\(lastFinished.categorizedCount) transactions categorized", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if lastFinished.failedCount > 0 {
                        LabeledContent("Failed", value: lastFinished.failedCount, format: .number)
                    }
                    if lastFinished.skippedCount > 0 {
                        LabeledContent("Skipped", value: lastFinished.skippedCount, format: .number)
                    }
                }
            } header: {
                Text("Last Run")
            }
        }
    }

    @ViewBuilder
    private var candidatesSection: some View {
        switch candidates {
        case .idle, .loading:
            Section {
                TransactionRowsPlaceholder()
            }
        case .failed(let error):
            Section {
                InlineRetryView(ErrorMessage.message(for: error)) { await loadCandidates() }
            }
        case .loaded(let items) where items.isEmpty:
            Section {
                ContentUnavailableView {
                    Label("Nothing to Categorize", systemImage: "checkmark.seal")
                } description: {
                    Text("Every transaction already has a category other than your default.")
                } actions: {
                    Button("Refresh") { Task { await loadCandidates() } }
                        .buttonStyle(.bordered)
                }
            }
        case .loaded(let items):
            Section {
                ForEach(items) { transaction in
                    ResolvedTransactionRow(transaction: transaction, showsDate: true)
                        .tag(transaction.id)
                }
                if hasMoreCandidates {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await loadMoreCandidates() }
                }
            } header: {
                if let candidateTotal {
                    Text("\(candidateTotal) transactions in your default category")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if tab == .categorize, !(candidates.value ?? []).isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Done" : "Select") {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                        if !editMode.isEditing { selection = [] }
                    }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                if isTriggering {
                    ProgressView()
                } else if editMode.isEditing {
                    Button("Categorize \(selection.count) Selected", systemImage: "sparkles") {
                        Task { await trigger(ids: Array(selection)) }
                    }
                    .disabled(selection.isEmpty || isRunning || !isConfigured)
                } else {
                    Button("Categorize All", systemImage: "sparkles") { confirmsRunAll = true }
                        .disabled(isRunning || !isConfigured)
                }
            }
        }
    }

    private var isRunning: Bool { status?.status.isActive ?? false }

    private var isConfigured: Bool { feature.value??.isReadyToCategorize ?? false }

    // MARK: Loading

    private func reload() async {
        async let featureLoad: Void = loadFeature()
        async let statusLoad: Void = loadStatus()
        async let candidatesLoad: Void = loadCandidates()
        _ = await (featureLoad, statusLoad, candidatesLoad)
    }

    private func loadFeature() async {
        guard let client = services.client else { return }
        if feature.value == nil { feature = .loading }
        do {
            feature = .loaded(try await client.send(Endpoints.dataAICategorizationFeature()))
        } catch {
            feature = .failed(APIError(error))
        }
    }

    private func loadStatus() async {
        guard let client = services.client else { return }
        guard let latest = try? await client.send(Endpoints.dataAICategorizationStatus()) else { return }
        apply(latest)
    }

    /// A finished status is reported once, so keep it for the "Last Run" summary.
    private func apply(_ latest: DataAICategorizationStatus) {
        if latest.status == .completed || latest.status == .failed {
            lastFinished = latest
        }
        status = latest
    }

    private func pollWhileActive() async {
        guard let client = services.client, status?.status.isActive == true else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let latest = try? await client.send(Endpoints.dataAICategorizationStatus()) else { continue }
            apply(latest)
            if !latest.status.isActive {
                await loadCandidates()
                return
            }
        }
    }

    private func loadCandidates() async {
        guard let client = services.client else { return }
        if candidates.value == nil { candidates = .loading }
        do {
            let page = try await client.send(Endpoints.dataAICategorizationCandidates(limit: pageSize, offset: 0))
            candidates = .loaded(page.items)
            candidateTotal = page.totalCount
            hasMoreCandidates = page.items.count == pageSize
            selection = selection.intersection(page.items.map(\.id))
        } catch {
            if candidates.value == nil { candidates = .failed(APIError(error)) }
        }
    }

    private func loadMoreCandidates() async {
        guard let client = services.client, let current = candidates.value else { return }
        do {
            let page = try await client.send(Endpoints.dataAICategorizationCandidates(limit: pageSize, offset: current.count))
            candidates = .loaded(current + page.items)
            hasMoreCandidates = page.items.count == pageSize
        } catch {
            hasMoreCandidates = false
        }
    }

    private func trigger(ids: [String]?) async {
        guard let client = services.client else { return }
        isTriggering = true
        defer { isTriggering = false }
        do {
            let result = try await client.send(Endpoints.dataTriggerAICategorization(transactionIds: ids))
            if result.enqueued {
                lastFinished = nil
                editMode = .inactive
                selection = []
                await loadStatus()
            } else {
                alert = ErrorAlert(title: String(localized: "Nothing to Categorize"), message: String(localized: "None of these transactions need a category."))
            }
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// Past AI runs, newest first; each opens the transactions it categorized.
private struct DataAICategorizationHistorySection: View {
    @Environment(AppServices.self) private var services
    @State private var state: LoadState<[DataAICategorizationRun]> = .idle
    @State private var hasMore = false

    private let pageSize = 20

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                Section {
                    ForEach(0..<4, id: \.self) { _ in
                        LabeledContent("Placeholder run date", value: "000")
                    }
                }
                .redactedWhileLoading(true)
            case .failed(let error):
                Section {
                    InlineRetryView(ErrorMessage.message(for: error)) { await load() }
                }
            case .loaded(let runs) where runs.isEmpty:
                Section {
                    ContentUnavailableView(
                        "No Runs Yet",
                        systemImage: "clock",
                        description: Text("Runs appear here after AI categorizes transactions.")
                    )
                }
            case .loaded(let runs):
                Section("Runs") {
                    ForEach(runs) { run in
                        NavigationLink {
                            DataAICategorizationRunScreen(run: run)
                        } label: {
                            LabeledContent {
                                Text("\(run.transactionCount)").monospacedDigit()
                            } label: {
                                Text(run.categorizedAt.formatted(date: .abbreviated, time: .shortened))
                                if let trigger = run.trigger {
                                    Text(Self.label(trigger))
                                }
                            }
                        }
                    }
                    if hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .task { await loadMore() }
                    }
                }
            }
        }
        .task { if case .idle = state { await load() } }
    }

    private static func label(_ trigger: DataAICategorizationTrigger) -> LocalizedStringKey {
        switch trigger {
        case .manual: "Manual run"
        case .import: "After import"
        case .sync: "After bank sync"
        case .unknown: "Run"
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        state = .loading
        do {
            let page = try await client.send(Endpoints.dataAICategorizationHistory(limit: pageSize, offset: 0))
            state = .loaded(page.items)
            hasMore = page.items.count == pageSize
        } catch {
            state = .failed(APIError(error))
        }
    }

    private func loadMore() async {
        guard let client = services.client, let current = state.value else { return }
        do {
            let page = try await client.send(Endpoints.dataAICategorizationHistory(limit: pageSize, offset: current.count))
            state = .loaded(current + page.items)
            hasMore = page.items.count == pageSize
        } catch {
            hasMore = false
        }
    }
}

/// The transactions one AI run categorized.
private struct DataAICategorizationRunScreen: View {
    let run: DataAICategorizationRun

    @Environment(AppServices.self) private var services
    @State private var state: LoadState<[Transaction]> = .idle
    @State private var hasMore = false

    private let pageSize = 30

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                List { TransactionRowsPlaceholder() }
            case .failed(let error):
                LoadFailedView(error: error) { await load() }
            case .loaded(let items) where items.isEmpty:
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "tray",
                    description: Text("These transactions have since been recategorized.")
                )
            case .loaded(let items):
                List {
                    ForEach(items) { transaction in
                        NavigationLink {
                            TransactionDetailScreen(transactionID: transaction.id)
                        } label: {
                            ResolvedTransactionRow(transaction: transaction, showsDate: true)
                        }
                    }
                    if hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .task { await loadMore() }
                    }
                }
            }
        }
        .navigationTitle(run.categorizedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if case .idle = state { await load() } }
    }

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            let items = try await client.send(Endpoints.dataAICategorizationRunTransactions(categorizedAt: run.categorizedAtRaw, limit: pageSize))
            state = .loaded(items)
            hasMore = items.count == pageSize
        } catch {
            if state.value == nil { state = .failed(APIError(error)) }
        }
    }

    private func loadMore() async {
        guard let client = services.client, let current = state.value else { return }
        do {
            let items = try await client.send(Endpoints.dataAICategorizationRunTransactions(categorizedAt: run.categorizedAtRaw, limit: pageSize, offset: current.count))
            state = .loaded(current + items)
            hasMore = items.count == pageSize
        } catch {
            hasMore = false
        }
    }
}
