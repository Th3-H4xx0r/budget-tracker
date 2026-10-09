import MoneyMatterKit
import SwiftUI

/// Syndicate and fund platforms with their default fee terms. Mirrors the web
/// `venture/platforms` page.
struct VenturePlatformsScreen: View {
    @Environment(AppServices.self) private var services

    @State private var state: LoadState<[VenturePlatform]> = .idle
    @State private var isCreating = false
    @State private var editing: VenturePlatform?
    @State private var pendingDelete: VenturePlatform?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Platforms")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("New Platform", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreating) {
                VenturePlatformFormSheet(platform: nil) { await reload() }
            }
            .sheet(item: $editing) { platform in
                VenturePlatformFormSheet(platform: platform) { await reload() }
            }
            .confirmationDialog(
                "Delete this platform?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { platform in
                Button("Delete Platform", role: .destructive) {
                    Task { await delete(platform) }
                }
            } message: { _ in
                Text("Deals on this platform keep their terms but lose the platform link.")
            }
            .errorAlert($alert)
            .task {
                if case .idle = state { await reload() }
            }
            .refreshable { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            List {
                ForEach(0..<3, id: \.self) { _ in
                    VenturePlatformRow(platform: VenturePlatform(id: "placeholder", name: "Platform name"))
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await reload() }
        case .loaded(let platforms) where platforms.isEmpty:
            ContentUnavailableView {
                Label("No Platforms", systemImage: "building.columns")
            } description: {
                Text("Add the syndicates or funds you invest through to prefill deal fees.")
            } actions: {
                Button("New Platform") { isCreating = true }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let platforms):
            List {
                ForEach(platforms) { platform in
                    Button {
                        editing = platform
                    } label: {
                        VenturePlatformRow(platform: platform)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = platform }
                        Button("Edit", systemImage: "pencil") { editing = platform }
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editing = platform }
                        if let website = platform.website, let url = URL(string: website) {
                            Link(destination: url) {
                                Label("Open Website", systemImage: "safari")
                            }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = platform }
                    }
                }
            }
        }
    }

    private func reload() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await client.send(Endpoints.venturePlatforms()))
        } catch {
            if state.value == nil { state = .failed(APIError(error)) }
        }
    }

    private func delete(_ platform: VenturePlatform) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.venturePlatformDelete(id: platform.id))
            if case .loaded(let platforms) = state {
                state = .loaded(platforms.filter { $0.id != platform.id })
            }
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// A platform: name, website host, and its default fee terms.
private struct VenturePlatformRow: View {
    let platform: VenturePlatform

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: platform.name)
                .font(.body.weight(.medium))
            if let website = platform.website, let host = URL(string: website)?.host() {
                Text(verbatim: host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let details = platform.platformDescription, !details.isEmpty {
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Text("Entry \(VentureFormat.percent(platform.defaultEntryFeePct))")
                Text("Mgmt \(VentureFormat.percent(platform.defaultMgmtFeePct))")
                Text("Carry \(VentureFormat.percent(platform.defaultCarryPct))")
                Text("Hurdle \(VentureFormat.percent(platform.defaultHurdlePct))")
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
