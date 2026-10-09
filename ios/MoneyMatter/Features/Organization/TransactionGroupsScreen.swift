import MoneyMatterKit
import SwiftUI

/// Transaction groups: named bundles of related transactions (a trip, a split bill),
/// matching the web's `pages/transaction-groups`.
struct TransactionGroupsScreen: View {
    @Environment(AppServices.self) private var services
    @State private var state: LoadState<[OrgTxGroup]> = .idle
    @State private var searchText = ""
    @State private var isCreating = false
    @State private var pendingDelete: OrgTxGroup?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Transaction Groups")
            .searchable(text: $searchText, prompt: Text("Search groups"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("New Group", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreating) {
                OrgTxGroupCreateSheet {
                    await load()
                }
            }
            .confirmationDialog(
                "Delete Group?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { group in
                Button("Delete Group", role: .destructive) {
                    Task { await delete(group) }
                }
            } message: { group in
                Text("“\(group.name)” will be removed. Its transactions stay in your history.")
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
                ForEach(0..<5, id: \.self) { _ in
                    OrgTxGroupRow(group: OrgTxGroup(id: "", name: "Placeholder group", note: "Placeholder note", transactionCount: 3))
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let groups):
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("No Groups", systemImage: "rectangle.stack")
                } description: {
                    Text("Group related transactions, like a trip or a split bill, to see them together.")
                } actions: {
                    Button("New Group") { isCreating = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if filtered(groups).isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(filtered(groups)) { group in
                        NavigationLink {
                            OrgTxGroupDetailScreen(groupID: group.id, initialName: group.name) {
                                await load()
                            }
                        } label: {
                            OrgTxGroupRow(group: group)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDelete = group
                            }
                        }
                        .contextMenu {
                            Button("Delete Group", systemImage: "trash", role: .destructive) {
                                pendingDelete = group
                            }
                        }
                    }
                }
            }
        }
    }

    private func filtered(_ groups: [OrgTxGroup]) -> [OrgTxGroup] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return groups }
        return groups.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.note?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await client.send(Endpoints.orgTxGroups()))
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(error) }
        }
    }

    private func delete(_ group: OrgTxGroup) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.orgDeleteTxGroup(id: group.id))
            if case .loaded(let groups) = state {
                state = .loaded(groups.filter { $0.id != group.id })
            }
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// One group in the list: name, note, count, and date span.
struct OrgTxGroupRow: View {
    let group: OrgTxGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.name)
                .font(.body.weight(.medium))
            if let note = group.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text("\(group.count) transactions")
                if let span = OrgTxGroupRow.dateSpan(group) {
                    Text(verbatim: "·")
                    Text(span)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    static func dateSpan(_ group: OrgTxGroup) -> String? {
        guard let start = group.startDate else { return nil }
        let end = group.endDate ?? start
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return start.formatted(date: .abbreviated, time: .omitted)
        }
        return (start..<max(end, start)).formatted(.interval.day().month(.abbreviated).year())
    }
}
