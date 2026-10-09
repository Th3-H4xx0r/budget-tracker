import MoneyMatterKit
import SwiftUI

/// Adds the selected transactions to an existing group, or to a new one.
struct TransactionBulkGroupSheet: View {
    let transactionIds: [String]
    let onDone: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState<[TransactionGroupSummary]> = .idle
    @State private var newGroupName = ""
    @State private var isWorking = false
    @State private var errorAlert: ErrorAlert?

    /// The server needs 2 to 50 transactions to create a group.
    private var canCreateGroup: Bool { (2...50).contains(transactionIds.count) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Group name", text: $newGroupName)
                        .disabled(!canCreateGroup)
                    Button("Create Group", systemImage: "plus.rectangle.on.rectangle") {
                        Task { await createGroup() }
                    }
                    .disabled(!canCreateGroup || newGroupName.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                } header: {
                    Text("New Group")
                } footer: {
                    if !canCreateGroup {
                        Text("A new group needs between 2 and 50 transactions.")
                    }
                }

                Section("Existing Groups") {
                    switch state {
                    case .idle, .loading:
                        ForEach(0..<3, id: \.self) { _ in
                            Text(verbatim: "Group name placeholder").redacted(reason: .placeholder)
                        }
                    case .failed(let error):
                        InlineRetryView(ErrorMessage.message(for: error)) { await load() }
                    case .loaded(let groups):
                        if groups.isEmpty {
                            ContentUnavailableView(
                                "No Groups",
                                systemImage: "rectangle.stack",
                                description: Text("Create a group above to collect related transactions.")
                            )
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(groups) { group in
                                Button {
                                    Task { await add(to: group) }
                                } label: {
                                    LabeledContent(group.name) {
                                        if let count = group.transactionCount {
                                            Text("\(count) transactions")
                                        }
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .disabled(isWorking)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if isWorking {
                    ToolbarItem(placement: .confirmationAction) { ProgressView() }
                }
            }
            .task { await load() }
            .errorAlert($errorAlert)
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await client.send(Endpoints.transactionGroupSummaries()))
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if state.value == nil { state = .failed(apiError) }
        }
    }

    private func add(to group: TransactionGroupSummary) async {
        await perform {
            _ = try await $0.send(Endpoints.addTransactionsToGroup(groupId: group.id, TransactionGroupAddRequest(transactionIds: transactionIds)))
        }
    }

    private func createGroup() async {
        let name = String(newGroupName.trimmingCharacters(in: .whitespaces).prefix(100))
        await perform {
            _ = try await $0.send(Endpoints.createTransactionGroupWith(TransactionGroupCreateRequest(name: name, transactionIds: transactionIds)))
        }
    }

    private func perform(_ action: (APIClient) async throws -> Void) async {
        guard let client = services.client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await action(client)
            TransactionChangeFeed.shared.publish(.invalidated)
            onDone()
            dismiss()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}
