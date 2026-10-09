import MoneyMatterKit
import SwiftUI

/// One transaction group: details, its transactions, and edit, add, remove, and delete.
struct OrgTxGroupDetailScreen: View {
    let groupID: String
    let initialName: String
    let onChange: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState<OrgTxGroup> = .idle
    @State private var isEditing = false
    @State private var isAdding = false
    @State private var isConfirmingDelete = false
    @State private var pendingDissolve: Transaction?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle(state.value?.name ?? initialName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let group = state.value {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Edit Details", systemImage: "pencil") { isEditing = true }
                            Button("Add Transactions", systemImage: "plus") { isAdding = true }
                                .disabled(group.count >= OrgTxGroupLimits.maxTransactions)
                            Divider()
                            Button("Delete Group", systemImage: "trash", role: .destructive) {
                                isConfirmingDelete = true
                            }
                        } label: {
                            Label("Actions", systemImage: "ellipsis")
                        }
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                if let group = state.value {
                    OrgTxGroupEditSheet(group: group) { updated in
                        state = .loaded(updated)
                        await onChange()
                        await load()
                    }
                }
            }
            .sheet(isPresented: $isAdding) {
                if let group = state.value {
                    OrgTxGroupAddSheet(
                        excludedIDs: Set((group.transactions ?? []).map(\.id)),
                        remaining: OrgTxGroupLimits.maxTransactions - group.count
                    ) { ids in
                        await add(ids)
                    }
                }
            }
            .confirmationDialog(
                "Delete Group?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Group", role: .destructive) {
                    Task { await deleteGroup() }
                }
            } message: {
                Text("The group is removed. Its transactions stay in your history.")
            }
            .confirmationDialog(
                "Dissolve Group?",
                isPresented: Binding(get: { pendingDissolve != nil }, set: { if !$0 { pendingDissolve = nil } }),
                titleVisibility: .visible,
                presenting: pendingDissolve
            ) { transaction in
                Button("Remove and Dissolve", role: .destructive) {
                    Task { await remove(transaction, force: true) }
                }
            } message: { _ in
                Text("A group needs at least two transactions. Removing this one dissolves the group.")
            }
            .errorAlert($alert)
            .task {
                if state.value == nil { await load() }
            }
            .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            List {
                Section {
                    Text(verbatim: "Placeholder note for the group")
                }
                Section {
                    TransactionRowsPlaceholder()
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let group):
            List {
                Section {
                    if let note = group.note, !note.isEmpty {
                        Text(note)
                    }
                    LabeledContent("Transactions") {
                        Text(group.count, format: .number)
                            .monospacedDigit()
                    }
                    if let span = OrgTxGroupRow.dateSpan(group) {
                        LabeledContent("Dates", value: span)
                    }
                }
                Section("Transactions") {
                    let transactions = (group.transactions ?? []).sorted { $0.time > $1.time }
                    if transactions.isEmpty {
                        Text("No transactions in this group.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(transactions) { transaction in
                        NavigationLink {
                            TransactionDetailScreen(transactionID: transaction.id, initial: transaction)
                        } label: {
                            ResolvedTransactionRow(transaction: transaction, showsDate: true)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                                Task { await remove(transaction, force: false) }
                            }
                        }
                        .contextMenu {
                            Button("Remove from Group", systemImage: "minus.circle", role: .destructive) {
                                Task { await remove(transaction, force: false) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await client.send(Endpoints.orgTxGroup(id: groupID)))
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(error) }
        }
    }

    private func add(_ ids: [String]) async -> Bool {
        guard let client = services.client, !ids.isEmpty else { return false }
        do {
            _ = try await client.send(Endpoints.orgAddTransactionsToTxGroup(groupId: groupID, transactionIds: ids))
            await load()
            await onChange()
            return true
        } catch {
            alert = ErrorAlert(error)
            return false
        }
    }

    private func remove(_ transaction: Transaction, force: Bool) async {
        guard let client = services.client else { return }
        do {
            let result = try await client.send(
                Endpoints.orgRemoveTransactionsFromTxGroup(groupId: groupID, transactionIds: [transaction.id], force: force)
            )
            await onChange()
            if result.dissolved {
                dismiss()
            } else {
                await load()
            }
        } catch {
            if !force, case .server(409, _, _) = APIError(error) {
                pendingDissolve = transaction
            } else {
                alert = ErrorAlert(error)
            }
        }
    }

    private func deleteGroup() async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.orgDeleteTxGroup(id: groupID))
            await onChange()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// Edits a group's name and note.
private struct OrgTxGroupEditSheet: View {
    let group: OrgTxGroup
    let onSaved: (OrgTxGroup) async -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    init(group: OrgTxGroup, onSaved: @escaping (OrgTxGroup) async -> Void) {
        self.group = group
        self.onSaved = onSaved
        _name = State(initialValue: group.name)
        _note = State(initialValue: group.note ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                OrgTxGroupFields(name: $name, note: $note)
            }
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(trimmedName.isEmpty || trimmedName.count > OrgTxGroupLimits.maxNameLength
                                || note.count > OrgTxGroupLimits.maxNoteLength)
                    }
                }
            }
            .errorAlert($alert)
        }
    }

    private func save() async {
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteUpdate: FieldUpdate<String> = trimmedNote == (group.note ?? "")
            ? .unchanged
            : (trimmedNote.isEmpty ? .clear : .set(trimmedNote))
        do {
            let updated = try await client.send(Endpoints.orgUpdateTxGroup(
                id: group.id,
                OrgTxGroupUpdateRequest(name: trimmedName == group.name ? nil : trimmedName, note: noteUpdate)
            ))
            await onSaved(updated)
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// Name and note fields shared by the create and edit sheets.
struct OrgTxGroupFields: View {
    @Binding var name: String
    @Binding var note: String

    var body: some View {
        Section {
            TextField("Name", text: $name)
            TextField("Note", text: $note, axis: .vertical)
                .lineLimit(2...5)
        } footer: {
            if name.count > OrgTxGroupLimits.maxNameLength {
                Text("Names can be up to 100 characters.")
            } else if note.count > OrgTxGroupLimits.maxNoteLength {
                Text("Notes can be up to 500 characters.")
            }
        }
    }
}

/// Creates a group from a name, a note, and at least two transactions.
struct OrgTxGroupCreateSheet: View {
    let onCreated: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var note = ""
    @State private var selection: Set<String> = []
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= OrgTxGroupLimits.maxNameLength
            && note.count <= OrgTxGroupLimits.maxNoteLength
            && (OrgTxGroupLimits.minTransactions...OrgTxGroupLimits.maxTransactions).contains(selection.count)
    }

    var body: some View {
        NavigationStack {
            Form {
                OrgTxGroupFields(name: $name, note: $note)
                Section {
                    NavigationLink {
                        OrgTxGroupTransactionPicker(
                            selection: $selection,
                            excludedIDs: [],
                            limit: OrgTxGroupLimits.maxTransactions
                        )
                        .navigationTitle("Choose Transactions")
                    } label: {
                        LabeledContent("Transactions") {
                            Text("\(selection.count) selected")
                        }
                    }
                } footer: {
                    Text("Pick 2 to 50 transactions. A transaction can belong to one group.")
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create") { Task { await create() } }
                            .disabled(!isValid)
                    }
                }
            }
            .errorAlert($alert)
        }
    }

    private func create() async {
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await client.send(Endpoints.orgCreateTxGroup(OrgTxGroupCreateRequest(
                name: trimmedName,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                transactionIds: Array(selection)
            )))
            await onCreated()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// A sheet that picks transactions to add to an existing group.
private struct OrgTxGroupAddSheet: View {
    let excludedIDs: Set<String>
    let remaining: Int
    let onAdd: ([String]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            OrgTxGroupTransactionPicker(selection: $selection, excludedIDs: excludedIDs, limit: max(remaining, 0))
                .navigationTitle("Add Transactions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Add") {
                                Task {
                                    isSaving = true
                                    let added = await onAdd(Array(selection))
                                    isSaving = false
                                    if added { dismiss() }
                                }
                            }
                            .disabled(selection.isEmpty)
                        }
                    }
                }
        }
    }
}

/// Multi-select over the transactions list, newest first, with note search and paging.
/// Transactions already in a group can't be picked.
struct OrgTxGroupTransactionPicker: View {
    @Binding var selection: Set<String>
    let excludedIDs: Set<String>
    let limit: Int

    @Environment(AppServices.self) private var services
    @State private var transactions: [Transaction] = []
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var loadError: APIError?
    @State private var searchText = ""

    private static let pageSize = 50

    var body: some View {
        List {
            if transactions.isEmpty, isLoading {
                TransactionRowsPlaceholder()
            } else if transactions.isEmpty, let loadError {
                InlineRetryView(ErrorMessage.message(for: loadError)) { await reload() }
            } else if transactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "list.bullet",
                    description: Text("No transactions match your search.")
                )
            } else {
                Section {
                    ForEach(transactions) { transaction in
                        row(transaction)
                    }
                    if hasMore {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else if let loadError {
                                InlineRetryView(ErrorMessage.message(for: loadError)) { await loadMore() }
                            } else {
                                Button("Load More") { Task { await loadMore() } }
                            }
                            Spacer()
                        }
                    }
                } header: {
                    Text("\(selection.count) of \(limit) selected")
                }
            }
        }
        .searchable(text: $searchText, prompt: Text("Search notes"))
        .task(id: searchText) {
            if !searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(350))
                if Task.isCancelled { return }
            }
            await reload()
        }
    }

    @ViewBuilder
    private func row(_ transaction: Transaction) -> some View {
        let groupName = transaction.transactionGroups?.first?.name
        let isSelected = selection.contains(transaction.id)
        let isBlocked = groupName != nil || excludedIDs.contains(transaction.id)
        Button {
            if isSelected {
                selection.remove(transaction.id)
            } else if selection.count < limit {
                selection.insert(transaction.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    ResolvedTransactionRow(transaction: transaction, showsDate: true)
                    if let groupName {
                        Text("In “\(groupName)”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isBlocked || (!isSelected && selection.count >= limit))
        .opacity(isBlocked ? 0.5 : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func reload() async {
        transactions = []
        hasMore = true
        await loadMore()
    }

    private func loadMore() async {
        guard let client = services.client, !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        var query = TransactionListQuery(limit: Self.pageSize, offset: transactions.count)
        query.order = .descending
        query.includeGroups = true
        let search = searchText.trimmingCharacters(in: .whitespaces)
        if !search.isEmpty { query.noteSearch = [search] }
        do {
            let page = try await client.send(Endpoints.transactions(query))
            let known = Set(transactions.map(\.id))
            transactions += page.filter { !known.contains($0.id) }
            hasMore = page.count == Self.pageSize
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation { loadError = apiError }
        }
    }
}
