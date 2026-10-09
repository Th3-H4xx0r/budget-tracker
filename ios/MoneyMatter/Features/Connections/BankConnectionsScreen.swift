import MoneyMatterKit
import SwiftUI

/// Bank connections: sync status, connections needing reconnection, and every connection
/// with its consent state. Mirrors the web integrations list on the Accounts page.
struct BankConnectionsScreen: View {
    @Environment(AppServices.self) private var services
    @State private var connections: LoadState<[BankConnectionSummary]> = .idle
    @State private var monitor = BankSyncMonitor.shared
    @State private var isConnectPresented = false
    @State private var openedConnectionID: String?
    @State private var errorAlert: ErrorAlert?

    var body: some View {
        List {
            switch connections {
            case .idle, .loading:
                Section {
                    ForEach(0..<3, id: \.self) { _ in
                        BankConnectionRow.placeholder
                    }
                }
                .redactedWhileLoading(true)
            case .failed(let error):
                Section {
                    InlineRetryView(ErrorMessage.message(for: error)) { await load() }
                }
            case .loaded(let list):
                if !list.isEmpty {
                    syncSection
                    reauthSection
                    Section("Connections") {
                        ForEach(list) { connection in
                            NavigationLink {
                                BankConnectionDetailScreen(connectionID: connection.id)
                            } label: {
                                BankConnectionRow(
                                    connection: connection,
                                    status: monitor.status?.connectionStatus(forConnectionID: connection.id)
                                )
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if case .loaded(let list) = connections, list.isEmpty {
                ContentUnavailableView {
                    Label("No Bank Connections", systemImage: "building.columns")
                } description: {
                    Text("Connect a bank to import accounts and sync transactions automatically.")
                } actions: {
                    Button("Connect a Bank") { isConnectPresented = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Bank Connections")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Connect a Bank", systemImage: "plus") { isConnectPresented = true }
            }
        }
        .refreshable { await load() }
        .task { if case .idle = connections { await load() } }
        .sheet(isPresented: $isConnectPresented) {
            BankConnectSheet { connectionID in
                Task {
                    await load()
                    openedConnectionID = connectionID
                }
            }
        }
        .navigationDestination(item: $openedConnectionID) { id in
            BankConnectionDetailScreen(connectionID: id)
        }
        .errorAlert($errorAlert)
    }

    private var syncSection: some View {
        Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(BankSyncText.summary(monitor.status, isSyncing: monitor.isSyncing))
                    if let failed = monitor.status?.summary.failed, failed > 0 {
                        Text("\(failed) accounts failed to sync")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                Spacer(minLength: 8)
                if monitor.isSyncing {
                    ProgressView()
                } else {
                    Button("Sync Now") {
                        Task { await syncNow() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(minHeight: 44)
        } header: {
            Text("Sync")
        } footer: {
            Text("Connected accounts sync automatically every few hours.")
        }
    }

    @ViewBuilder
    private var reauthSection: some View {
        if let needing = monitor.status?.connectionsNeedingReauth, !needing.isEmpty {
            Section {
                ForEach(needing) { connection in
                    NavigationLink {
                        BankConnectionDetailScreen(connectionID: connection.connectionId)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.bankName ?? connection.providerName)
                                Text("Reconnect to resume syncing \(connection.accountsCount) accounts.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } header: {
                Text("Needs Attention")
            }
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        if connections.value == nil { connections = .loading }
        async let status: Void = monitor.refresh(client: client)
        do {
            connections = .loaded(try await client.send(Endpoints.bankConnections()))
        } catch {
            if connections.value == nil { connections = .failed(APIError(error)) } else { errorAlert = ErrorAlert(error) }
        }
        await status
    }

    private func syncNow() async {
        do {
            try await monitor.syncNow(client: services.client)
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

/// One connection: the bank or provider, its accounts, last sync, and consent badge.
private struct BankConnectionRow: View {
    let connection: BankConnectionSummary?
    let status: BankSyncStatus.ConnectionStatus?

    static var placeholder: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.columns")
                .frame(width: 32)
            VStack(alignment: .leading) {
                Text(verbatim: "Placeholder bank")
                Text(verbatim: "3 accounts · synced today")
                    .font(.subheadline)
            }
        }
    }

    var body: some View {
        if let connection {
            HStack(spacing: 12) {
                Image(systemName: BankSyncText.providerSymbol(connection.providerType))
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.providerName.isEmpty ? (connection.bankName ?? BankSyncText.providerName(connection.providerType)) : connection.providerName)
                        .lineLimit(1)
                    Text(subtitle(connection))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                BankConsentBadge(isActive: connection.isActive, status: status)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func subtitle(_ connection: BankConnectionSummary) -> String {
        var parts = [connection.bankName ?? BankSyncText.providerName(connection.providerType)]
        parts.append(String(localized: "\(connection.accountsCount) accounts"))
        if let last = connection.lastSyncAt {
            parts.append(String(localized: "synced \(last.formatted(.relative(presentation: .named)))"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Active, expiring soon, expired, or inactive.
struct BankConsentBadge: View {
    let isActive: Bool
    let status: BankSyncStatus.ConnectionStatus?

    var body: some View {
        let (text, color) = content
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule)
    }

    private var content: (String, Color) {
        if !(status?.isActive ?? isActive) { return (String(localized: "Inactive"), .red) }
        if status?.consentExpired == true { return (String(localized: "Expired"), .red) }
        if status?.consentExpiringSoon == true {
            if let days = status?.daysRemaining { return (String(localized: "\(days) days left"), .orange) }
            return (String(localized: "Expiring"), .orange)
        }
        return (String(localized: "Active"), .green)
    }
}
