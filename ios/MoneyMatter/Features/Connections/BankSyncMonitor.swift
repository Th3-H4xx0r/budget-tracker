import MoneyMatterKit
import Observation
import SwiftUI

/// Bank sync state shared by the Accounts tab and the connection screens: the latest
/// `/sync/status`, manual and automatic sync, and polling while a sync runs.
@Observable
final class BankSyncMonitor {
    static let shared = BankSyncMonitor()

    private(set) var status: BankSyncStatus?
    private(set) var isTriggering = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastAutoCheck: Date?

    var isSyncing: Bool { isTriggering || status?.isInProgress == true }

    /// Connections the server deactivated after an auth failure, or whose consent ran out.
    var connectionIDsNeedingAttention: Set<String> {
        var ids = Set(status?.connectionsNeedingReauth.map(\.connectionId) ?? [])
        for connection in status?.connectionStatuses ?? [] where !connection.isActive || connection.consentExpired {
            ids.insert(connection.connectionId)
        }
        return ids
    }

    func needsRelink(_ account: Account) -> Bool {
        if account.needsRelink == true { return true }
        guard let connectionID = account.bankDataProviderConnectionId else { return false }
        return connectionIDsNeedingAttention.contains(connectionID)
    }

    func refresh(client: APIClient?) async {
        guard let client else { return }
        guard let latest = try? await client.send(Endpoints.bankSyncStatus()) else { return }
        status = latest
        if latest.isInProgress { startPolling(client: client) }
    }

    /// Runs the server's stale-sync check at most every few minutes, the way the web app
    /// does on load.
    func checkAutoSync(client: APIClient?) async {
        guard let client else { return }
        if let lastAutoCheck, Date.now.timeIntervalSince(lastAutoCheck) < 300 {
            await refresh(client: client)
            return
        }
        lastAutoCheck = .now
        _ = try? await client.send(Endpoints.checkBankSync())
        await refresh(client: client)
    }

    /// Syncs every bank-connected account. Throws for the caller's error alert.
    func syncNow(client: APIClient?) async throws {
        guard let client else { return }
        isTriggering = true
        defer { isTriggering = false }
        _ = try await client.send(Endpoints.triggerBankSync())
        await refresh(client: client)
        startPolling(client: client)
    }

    private func startPolling(client: APIClient) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            defer { self?.pollTask = nil }
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                guard let latest = try? await client.send(Endpoints.bankSyncStatus()) else { continue }
                self.status = latest
                if !latest.isInProgress {
                    TransactionChangeFeed.shared.publish(.invalidated)
                    return
                }
            }
        }
    }
}

/// The Accounts tab toolbar control, shown when any account is bank-connected: a spinner
/// while syncing, else a menu with the last sync time and Sync Now.
struct BankSyncToolbarMenu: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var monitor = BankSyncMonitor.shared
    @State private var errorAlert: ErrorAlert?

    var body: some View {
        Menu {
            Section {
                Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await syncNow() }
                }
                .disabled(monitor.isSyncing)
            } header: {
                Text(BankSyncText.summary(monitor.status, isSyncing: monitor.isSyncing))
            }
            if let failed = monitor.status?.summary.failed, failed > 0 {
                Text("\(failed) accounts failed to sync")
            }
            if !monitor.connectionIDsNeedingAttention.isEmpty {
                Text("Some bank connections need reconnecting")
            }
        } label: {
            if monitor.isSyncing {
                ProgressView()
                    .accessibilityLabel("Syncing bank accounts")
            } else {
                Label("Bank Sync", systemImage: syncSymbol)
            }
        }
        .task {
            await monitor.checkAutoSync(client: services.client)
        }
        .onChange(of: monitor.isSyncing) { wasSyncing, isSyncing in
            if wasSyncing, !isSyncing {
                Task { await referenceData.refreshAccounts() }
            }
        }
        .errorAlert($errorAlert)
    }

    private var syncSymbol: String {
        if !monitor.connectionIDsNeedingAttention.isEmpty || (monitor.status?.summary.failed ?? 0) > 0 {
            return "exclamationmark.arrow.triangle.2.circlepath"
        }
        return "arrow.triangle.2.circlepath"
    }

    private func syncNow() async {
        do {
            try await monitor.syncNow(client: services.client)
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

/// A small warning glyph for accounts whose bank connection needs reconnecting.
struct BankRelinkIndicator: View {
    let account: Account
    @State private var monitor = BankSyncMonitor.shared

    var body: some View {
        if monitor.needsRelink(account) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.small)
                .accessibilityLabel("Bank connection needs reconnecting")
        } else if monitor.status?.status(forAccountID: account.id)?.status == .syncing {
            ProgressView()
                .controlSize(.mini)
                .accessibilityLabel("Syncing")
        }
    }
}

/// Copy for sync state.
enum BankSyncText {
    static func summary(_ status: BankSyncStatus?, isSyncing: Bool) -> String {
        if isSyncing {
            let summary = status?.summary
            let done = (summary?.completed ?? 0) + (summary?.failed ?? 0)
            if let total = summary?.total, total > 0 {
                return String(localized: "Syncing \(done) of \(total) accounts…")
            }
            return String(localized: "Syncing…")
        }
        if let last = status?.lastSyncAt {
            return String(localized: "Last synced \(last.formatted(.relative(presentation: .named)))")
        }
        return String(localized: "Not synced yet")
    }

    static func state(_ state: BankSyncState) -> String {
        switch state {
        case .idle: String(localized: "Idle")
        case .queued: String(localized: "Queued")
        case .syncing: String(localized: "Syncing")
        case .completed: String(localized: "Synced")
        case .failed: String(localized: "Failed")
        case .unknown: String(localized: "Unknown")
        }
    }

    static func providerName(_ type: BankProviderType) -> String {
        switch type {
        case .monobank: "Monobank"
        case .enableBanking: "Enable Banking"
        case .lunchflow: "LunchFlow"
        case .walutomat: "Walutomat"
        case .simplefin: "SimpleFIN"
        case .unknown: String(localized: "Bank")
        }
    }

    static func providerSymbol(_ type: BankProviderType) -> String {
        switch type {
        case .monobank: "creditcard"
        case .enableBanking: "building.columns"
        case .lunchflow: "arrow.down.circle"
        case .walutomat: "dollarsign.arrow.circlepath"
        case .simplefin: "link"
        case .unknown: "building.columns"
        }
    }
}
