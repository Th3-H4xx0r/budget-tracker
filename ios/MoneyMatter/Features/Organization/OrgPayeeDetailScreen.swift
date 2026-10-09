import MoneyMatterKit
import SwiftUI

/// One payee: stats, categorization defaults (saved as they change, like the web page),
/// aliases, its transactions, and edit, merge, and delete actions.
struct OrgPayeeDetailScreen: View {
    let payeeID: String
    /// Called after any write, so the list can refresh its stats.
    var onChange: () -> Void = {}

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var state: LoadState<OrgPayee> = .idle
    @State private var tagSelection: Set<String> = []
    @State private var isEditing = false
    @State private var isAddingAlias = false
    @State private var aliasDraft = ""
    @State private var isPickingMergeTarget = false
    @State private var mergeTarget: PayeeLookup?
    @State private var pendingAction: PendingAction?
    @State private var isWorking = false
    @State private var alert: ErrorAlert?

    private enum PendingAction: Identifiable {
        case delete
        case deleteAndIgnore
        case merge(PayeeLookup)
        case applyTags

        var id: String {
            switch self {
            case .delete: "delete"
            case .deleteAndIgnore: "deleteAndIgnore"
            case .merge(let target): "merge-\(target.id)"
            case .applyTags: "applyTags"
            }
        }
    }

    var body: some View {
        content
            .navigationTitle(state.value?.name ?? String(localized: "Payee"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let payee = state.value {
                    ToolbarItem(placement: .topBarTrailing) {
                        actionsMenu(payee)
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $isEditing) {
                if let payee = state.value {
                    OrgPayeeFormSheet(payee: payee) { _ in
                        Task { await afterWrite() }
                    }
                }
            }
            .sheet(isPresented: $isPickingMergeTarget) {
                NavigationStack {
                    TransactionPayeePicker(selectedId: nil) { target in
                        guard let target, target.id != payeeID else { return }
                        mergeTarget = target
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isPickingMergeTarget = false }
                        }
                    }
                }
                .onDisappear {
                    if let mergeTarget {
                        pendingAction = .merge(mergeTarget)
                        self.mergeTarget = nil
                    }
                }
            }
            .alert("Add Alias", isPresented: $isAddingAlias) {
                TextField("Bank name", text: $aliasDraft)
                Button("Cancel", role: .cancel) {}
                Button("Add") { Task { await addAlias() } }
            } message: {
                Text("Transactions whose bank name matches this alias are linked to this payee.")
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
                titleVisibility: .visible,
                presenting: pendingAction
            ) { action in
                switch action {
                case .delete:
                    Button("Delete Payee", role: .destructive) { Task { await delete(ignoreFuture: false) } }
                case .deleteAndIgnore:
                    Button("Delete and Ignore", role: .destructive) { Task { await delete(ignoreFuture: true) } }
                case .merge(let target):
                    Button("Merge into \(target.name)", role: .destructive) { Task { await merge(into: target) } }
                case .applyTags:
                    Button("Apply Tags") { Task { await applyTags() } }
                }
            } message: { action in
                switch action {
                case .delete:
                    Text("Its transactions stay but lose the payee link. The name may become a payee again on the next sync.")
                case .deleteAndIgnore:
                    Text("Its transactions lose the payee link, and its names are added to the ignored list so they don't become payees again.")
                case .merge(let target):
                    Text("Transactions and aliases move to \(target.name), and this payee is deleted.")
                case .applyTags:
                    Text("The default tags are added to this payee's existing transactions.")
                }
            }
            .errorAlert($alert)
    }

    private var confirmationTitle: String {
        switch pendingAction {
        case .delete: String(localized: "Delete this payee?")
        case .deleteAndIgnore: String(localized: "Delete and ignore future matches?")
        case .merge: String(localized: "Merge payees?")
        case .applyTags: String(localized: "Apply tags to existing transactions?")
        case nil: ""
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            form(OrgPayee(id: payeeID, name: "Placeholder payee", stats: OrgPayeeStats(transactionCount: 10, netFlowRef: -100)))
                .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let payee):
            form(payee)
                .disabled(isWorking)
        }
    }

    private func form(_ payee: OrgPayee) -> some View {
        let currency = OrgPayeeSupport.baseCurrencyCode(referenceData)
        return Form {
            Section {
                HStack(spacing: 14) {
                    OrgPayeeLogoBadge(name: payee.name, initials: payee.logoInitials, colorHex: payee.logoColor, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(payee.name)
                            .font(.title3.weight(.semibold))
                        if let domain = payee.logoDomain, !domain.isEmpty {
                            Text(domain)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            statsSection(payee, currency: currency)
            defaultsSection(payee)
            aliasesSection(payee)
        }
    }

    @ViewBuilder
    private func statsSection(_ payee: OrgPayee, currency: String) -> some View {
        let stats = payee.stats ?? OrgPayeeStats()
        Section("Activity") {
            if stats.transactionCount > 0 {
                NavigationLink {
                    OrgPayeeTransactionsScreen(payeeID: payee.id, payeeName: payee.name) {
                        Task { await afterWrite() }
                    }
                } label: {
                    LabeledContent("Transactions") {
                        Text(stats.transactionCount, format: .number).monospacedDigit()
                    }
                }
            } else {
                LabeledContent("Transactions") {
                    Text(verbatim: "0").monospacedDigit()
                }
            }
            LabeledContent("Net Flow") {
                OrgPayeeNetFlowText(amount: stats.netFlowRef, currencyCode: currency)
            }
            if let first = stats.firstSeenAt {
                LabeledContent("First Seen") {
                    Text(first, format: .dateTime.day().month().year())
                }
            }
            if let last = stats.lastSeenAt {
                LabeledContent("Last Seen") {
                    Text(last, format: .dateTime.day().month().year())
                }
            }
            if let top = referenceData.category(id: stats.topCategoryId) {
                LabeledContent("Most Used Category") {
                    HStack(spacing: 6) {
                        CategoryIcon(category: top, size: 20)
                        Text(top.name)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func defaultsSection(_ payee: OrgPayee) -> some View {
        Section {
            NavigationLink {
                TransactionCategoryPicker(isSelected: { $0 == payee.defaultCategoryId }) { category in
                    Task { await update(OrgPayeeWriteRequest(defaultCategoryId: .set(category.id))) }
                }
            } label: {
                LabeledContent("Default Category") {
                    if let category = referenceData.category(id: payee.defaultCategoryId) {
                        HStack(spacing: 6) {
                            CategoryIcon(category: category, size: 20)
                            Text(category.name)
                        }
                    } else {
                        Text("None")
                    }
                }
            }
            if payee.defaultCategoryId != nil {
                Button("Clear Default Category", role: .destructive) {
                    Task { await update(OrgPayeeWriteRequest(defaultCategoryId: .clear)) }
                }
            }
            Picker("Categorization", selection: Binding(
                get: { payee.categorizationMode == .unknown ? .enforce : payee.categorizationMode },
                set: { mode in
                    guard mode != payee.categorizationMode else { return }
                    Task { await update(OrgPayeeWriteRequest(categorizationMode: mode)) }
                }
            )) {
                ForEach(OrgPayeeCategorizationMode.allCases, id: \.self) { option in
                    Text(OrgPayeeSupport.title(for: option)).tag(option)
                }
            }
            NavigationLink {
                TransactionTagsPicker(selection: $tagSelection)
                    .onDisappear {
                        Task { await saveTagsIfChanged() }
                    }
            } label: {
                LabeledContent("Default Tags") {
                    Text(tagSummary(payee.defaultTagIds))
                        .lineLimit(1)
                }
            }
            if !payee.defaultTagIds.isEmpty, (payee.stats?.transactionCount ?? 0) > 0 {
                Button("Apply Tags to Existing Transactions") { pendingAction = .applyTags }
            }
        } header: {
            Text("Defaults")
        } footer: {
            Text(OrgPayeeSupport.hint(for: payee.categorizationMode))
        }
    }

    @ViewBuilder
    private func aliasesSection(_ payee: OrgPayee) -> some View {
        Section {
            let aliases = payee.aliases ?? []
            if aliases.isEmpty {
                Text("No aliases yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(aliases) { alias in
                HStack {
                    Text(alias.rawName)
                    Spacer()
                    if alias.isCanonical {
                        Text("Name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    if !alias.isCanonical {
                        Button("Delete", role: .destructive) {
                            Task { await deleteAlias(alias) }
                        }
                    }
                }
                .contextMenu {
                    if !alias.isCanonical {
                        Button("Delete Alias", systemImage: "trash", role: .destructive) {
                            Task { await deleteAlias(alias) }
                        }
                    }
                }
            }
            Button {
                aliasDraft = ""
                isAddingAlias = true
            } label: {
                Label("Add Alias", systemImage: "plus")
            }
        } header: {
            Text("Aliases")
        } footer: {
            Text("Bank names that link to this payee. The payee's own name can't be removed.")
        }
    }

    private func actionsMenu(_ payee: OrgPayee) -> some View {
        Menu {
            Button("Edit", systemImage: "pencil") { isEditing = true }
            if payee.logoSource == "manual" {
                Button("Reset Logo", systemImage: "arrow.counterclockwise") {
                    Task { await resetLogo() }
                }
            }
            Button("Merge into Another Payee", systemImage: "arrow.triangle.merge") {
                isPickingMergeTarget = true
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { pendingAction = .delete }
            Button("Delete and Ignore Future", systemImage: "eye.slash", role: .destructive) {
                pendingAction = .deleteAndIgnore
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
    }

    private func tagSummary(_ ids: [String]) -> String {
        let names = ids.compactMap { referenceData.tag(id: $0)?.name }.sorted()
        return names.isEmpty ? String(localized: "None") : names.joined(separator: ", ")
    }

    // MARK: Loading and writes

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let payee = try await OrgPayeeSupport.client(services).send(Endpoints.orgPayee(id: payeeID))
            state = .loaded(payee)
            tagSelection = Set(payee.defaultTagIds)
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if state.value == nil {
                state = .failed(apiError)
            } else {
                alert = ErrorAlert(error)
            }
        }
    }

    private func afterWrite() async {
        await load()
        onChange()
        await referenceData.refreshPayees()
    }

    private func perform(_ work: (APIClient) async throws -> Void) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work(try OrgPayeeSupport.client(services))
            return true
        } catch {
            alert = ErrorAlert(error)
            return false
        }
    }

    private func update(_ request: OrgPayeeWriteRequest) async {
        if await perform({ _ = try await $0.send(Endpoints.orgUpdatePayee(id: payeeID, request)) }) {
            await afterWrite()
        }
    }

    private func saveTagsIfChanged() async {
        guard let payee = state.value, Set(payee.defaultTagIds) != tagSelection else { return }
        let ids = Array(tagSelection).sorted()
        if await perform({ _ = try await $0.send(Endpoints.orgUpdatePayee(id: payeeID, OrgPayeeWriteRequest(defaultTagIds: ids))) }) {
            await afterWrite()
        } else {
            tagSelection = Set(payee.defaultTagIds)
        }
    }

    private func applyTags() async {
        if await perform({ _ = try await $0.send(Endpoints.orgApplyPayeeTags(id: payeeID)) }) {
            await afterWrite()
        }
    }

    private func resetLogo() async {
        if await perform({ _ = try await $0.send(Endpoints.orgResetPayeeLogo(id: payeeID)) }) {
            await afterWrite()
        }
    }

    private func addAlias() async {
        let rawName = aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await OrgPayeeSupport.client(services).send(Endpoints.orgCreatePayeeAlias(payeeId: payeeID, rawName: rawName))
            await afterWrite()
        } catch {
            if OrgPayeeSupport.isConflict(error) {
                let message = APIError(error).serverMessage ?? ""
                alert = ErrorAlert(
                    title: String(localized: "Alias Already Used"),
                    message: message.isEmpty ? String(localized: "This name already links to a payee.") : message
                )
            } else {
                alert = ErrorAlert(error)
            }
        }
    }

    private func deleteAlias(_ alias: OrgPayeeAlias) async {
        if await perform({ _ = try await $0.send(Endpoints.orgDeletePayeeAlias(payeeId: payeeID, aliasId: alias.id)) }) {
            await afterWrite()
        }
    }

    private func merge(into target: PayeeLookup) async {
        if await perform({ _ = try await $0.send(Endpoints.orgMergePayee(sourceId: payeeID, targetPayeeId: target.id)) }) {
            onChange()
            await referenceData.refreshPayees()
            dismiss()
        }
    }

    private func delete(ignoreFuture: Bool) async {
        let succeeded = await perform { client in
            if ignoreFuture {
                _ = try await client.send(Endpoints.orgDeletePayeeAndIgnore(id: payeeID))
            } else {
                _ = try await client.send(Endpoints.orgDeletePayee(id: payeeID))
            }
        }
        if succeeded {
            onChange()
            await referenceData.refreshPayees()
            dismiss()
        }
    }
}

/// The payee's transactions, newest first. Swipe to unlink a transaction from the payee;
/// unlinking locks the row so a later sync doesn't re-attach it.
struct OrgPayeeTransactionsScreen: View {
    let payeeID: String
    let payeeName: String
    var onChange: () -> Void = {}

    @Environment(AppServices.self) private var services

    @State private var state: LoadState<[Transaction]> = .idle
    @State private var canLoadMore = false
    @State private var isLoadingMore = false
    @State private var alert: ErrorAlert?

    private static let pageSize = 50

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                List { TransactionRowsPlaceholder(count: 8) }
            case .failed(let error):
                LoadFailedView(error: error) { await reload() }
            case .loaded(let transactions):
                if transactions.isEmpty {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "list.bullet.rectangle",
                        description: Text("No transactions are linked to \(payeeName).")
                    )
                } else {
                    list(transactions)
                }
            }
        }
        .navigationTitle(payeeName)
        .navigationBarTitleDisplayMode(.inline)
        .task { if state.value == nil { await reload() } }
        .refreshable { await reload() }
        .errorAlert($alert)
    }

    private func list(_ transactions: [Transaction]) -> some View {
        List {
            ForEach(transactions) { transaction in
                NavigationLink {
                    TransactionDetailScreen(transactionID: transaction.id)
                } label: {
                    ResolvedTransactionRow(transaction: transaction, showsDate: true)
                }
                .swipeActions {
                    Button("Unlink") { Task { await unlink(transaction) } }
                        .tint(.orange)
                }
                .onAppear {
                    if transaction.id == transactions.last?.id, canLoadMore {
                        Task { await loadMore() }
                    }
                }
            }
            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
    }

    private func query(offset: Int) -> TransactionListQuery {
        var query = TransactionListQuery(limit: Self.pageSize, offset: offset)
        query.payeeIds = [payeeID]
        query.includeSplits = true
        query.includeTags = true
        return query
    }

    private func reload() async {
        if state.value == nil { state = .loading }
        do {
            let page = try await OrgPayeeSupport.client(services).send(Endpoints.transactions(query(offset: 0)))
            state = .loaded(page)
            canLoadMore = page.count >= Self.pageSize
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if state.value == nil {
                state = .failed(apiError)
            } else {
                alert = ErrorAlert(error)
            }
        }
    }

    private func loadMore() async {
        guard let current = state.value, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await OrgPayeeSupport.client(services).send(Endpoints.transactions(query(offset: current.count)))
            let known = Set(current.map(\.id))
            state = .loaded(current + page.filter { !known.contains($0.id) })
            canLoadMore = page.count >= Self.pageSize
        } catch {
            canLoadMore = false
            alert = ErrorAlert(error)
        }
    }

    private func unlink(_ transaction: Transaction) async {
        guard let current = state.value else { return }
        state = .loaded(current.filter { $0.id != transaction.id })
        do {
            _ = try await OrgPayeeSupport.client(services).send(
                Endpoints.updateTransaction(id: transaction.id, TransactionUpdateRequest(payeeId: .clear))
            )
            onChange()
        } catch {
            state = .loaded(current)
            alert = ErrorAlert(error)
        }
    }
}
