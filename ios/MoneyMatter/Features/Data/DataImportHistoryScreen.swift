import MoneyMatterKit
import SwiftUI

/// Past imports, newest first. Deleting a batch removes every transaction it created;
/// large batches are deleted by a background job, polled until it ends.
struct DataImportHistoryScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var reference
    @State private var state: LoadState<[DataImportBatch]> = .idle
    @State private var hasMore = false
    @State private var pendingDelete: DataImportBatch?
    @State private var deleteStatus: DataImportBatchDeleteStatus?
    @State private var alert: ErrorAlert?

    private let pageSize = 30

    var body: some View {
        content
            .navigationTitle("Import History")
            .refreshable { await load() }
            .task {
                if case .idle = state { await load() }
                await watchActiveDelete()
            }
            .confirmationDialog(
                "Delete this import?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { batch in
                Button("Delete \(batch.transactionCount) Transactions", role: .destructive) {
                    Task { await delete(batch, linkedTransfers: false) }
                }
                Button("Delete Including Linked Transfers", role: .destructive) {
                    Task { await delete(batch, linkedTransfers: true) }
                }
            } message: { _ in
                Text("Every transaction this import created is deleted. This can't be undone.")
            }
            .errorAlert($alert)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            List {
                ForEach(0..<6, id: \.self) { _ in
                    Label("CSV import of 120 transactions", systemImage: "tablecells")
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let batches) where batches.isEmpty:
            ContentUnavailableView {
                Label("No Imports Yet", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Imports you run appear here, so you can review or undo them.")
            } actions: {
                NavigationLink("Import Data") { ImportScreen() }
                    .buttonStyle(.bordered)
            }
        case .loaded(let batches):
            List {
                if let deleteStatus, deleteStatus.isActive {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Deleting an import…")
                        }
                    }
                }
                Section {
                    ForEach(batches) { batch in
                        row(batch)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = batch }
                                    .disabled(deleteStatus?.isActive ?? false)
                            }
                            .contextMenu {
                                Button("Delete Import", systemImage: "trash", role: .destructive) { pendingDelete = batch }
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
    }

    private func row(_ batch: DataImportBatch) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(batch.source.displayName)
                Text(batch.importedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                let names = batch.accountIds.compactMap { reference.account(id: $0)?.name }
                if !names.isEmpty {
                    Text(names.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: batch.source.systemImage)
        }
        .badge(Text("\(batch.transactionCount)").monospacedDigit())
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            let page = try await client.send(Endpoints.dataImportBatches(limit: pageSize, offset: 0))
            state = .loaded(page.items)
            hasMore = page.items.count == pageSize
        } catch {
            if state.value == nil { state = .failed(APIError(error)) } else { alert = ErrorAlert(error) }
        }
    }

    private func loadMore() async {
        guard let client = services.client, let current = state.value else { return }
        do {
            let page = try await client.send(Endpoints.dataImportBatches(limit: pageSize, offset: current.count))
            state = .loaded(current + page.items)
            hasMore = page.items.count == pageSize
        } catch {
            hasMore = false
        }
    }

    private func delete(_ batch: DataImportBatch, linkedTransfers: Bool) async {
        guard let client = services.client else { return }
        do {
            let result = try await client.send(Endpoints.dataDeleteImportBatch(batchId: batch.batchId, deleteLinkedTransfers: linkedTransfers))
            if result.jobId != nil {
                await watchActiveDelete()
            } else {
                await load()
            }
            await reference.refreshAccounts()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    /// Polls the background delete every 2 seconds while one runs, then reloads.
    private func watchActiveDelete() async {
        guard let client = services.client else { return }
        var sawActive = false
        while !Task.isCancelled {
            guard let status = try? await client.send(Endpoints.dataImportBatchDeleteStatus()) else { return }
            deleteStatus = status
            if status.isActive {
                sawActive = true
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            if status.state == .failed, let message = status.error {
                alert = ErrorAlert(title: String(localized: "Couldn't Delete Import"), message: message)
            }
            if sawActive { await load() }
            return
        }
    }
}
