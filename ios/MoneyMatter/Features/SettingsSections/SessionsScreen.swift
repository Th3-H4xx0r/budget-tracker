import MoneyMatterKit
import SwiftUI

/// Settings > Security > Sessions: every signed-in device, with this one first. Other
/// sessions can be revoked one at a time or all at once.
struct SessionsScreen: View {
    @Environment(AppServices.self) private var services

    @State private var state: LoadState<Snapshot> = .idle
    @State private var alert: ErrorAlert?
    @State private var revoking: String?
    @State private var sessionToRevoke: SettingsAuthSessionEntry?
    @State private var confirmsRevokeAll = false

    private struct Snapshot: Equatable {
        var current: SettingsAuthSessionEntry?
        var others: [SettingsAuthSessionEntry]
    }

    var body: some View {
        content
            .navigationTitle("Sessions")
            .task { if case .idle = state { await load() } }
            .refreshable { await load() }
            .errorAlert($alert)
            .confirmationDialog(
                "Sign out this device?",
                isPresented: Binding(get: { sessionToRevoke != nil }, set: { if !$0 { sessionToRevoke = nil } }),
                titleVisibility: .visible,
                presenting: sessionToRevoke
            ) { entry in
                Button("Sign Out Device", role: .destructive) { Task { await revoke(entry) } }
            }
            .confirmationDialog("Sign out all other devices?", isPresented: $confirmsRevokeAll, titleVisibility: .visible) {
                Button("Sign Out Other Devices", role: .destructive) { Task { await revokeOthers() } }
            } message: {
                Text("Every session except this one ends. Those devices need to sign in again.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let snapshot):
            list(snapshot)
        case .idle, .loading:
            list(Snapshot(
                current: SettingsAuthSessionEntry(id: "c", token: "c", ipAddress: "127.0.0.1", userAgent: "iPhone", updatedAt: .now),
                others: [SettingsAuthSessionEntry(id: "o", token: "o", ipAddress: "127.0.0.1", userAgent: "Chrome/120", updatedAt: .now)]
            ))
            .redactedWhileLoading(true)
        }
    }

    private func list(_ snapshot: Snapshot) -> some View {
        List {
            if let current = snapshot.current {
                Section("This Device") {
                    sessionRow(current, isCurrent: true)
                }
            }
            Section {
                if snapshot.others.isEmpty {
                    ContentUnavailableView {
                        Label("No Other Sessions", systemImage: "checkmark.shield")
                    } description: {
                        Text("You're only signed in here.")
                    } actions: {
                        Button("Refresh") { Task { await load() } }
                    }
                }
                ForEach(snapshot.others) { entry in
                    sessionRow(entry, isCurrent: false)
                        .swipeActions {
                            Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                sessionToRevoke = entry
                            }
                        }
                        .contextMenu {
                            Button("Sign Out Device", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                sessionToRevoke = entry
                            }
                        }
                }
            } header: {
                Text("Other Sessions")
            }
            if snapshot.others.count > 1 {
                Section {
                    Button("Sign Out All Other Devices", role: .destructive) { confirmsRevokeAll = true }
                }
            }
        }
    }

    private func sessionRow(_ entry: SettingsAuthSessionEntry, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(for: entry.deviceKind))
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.clientName ?? String(localized: "Unknown Device"))
                    .font(.body)
                if let ip = entry.ipAddress, !ip.isEmpty {
                    Text(ip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if isCurrent {
                    Text("Active now")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if let active = entry.updatedAt ?? entry.createdAt {
                    Text("Last active \(active, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if revoking == entry.token {
                ProgressView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(for kind: SettingsSessionDeviceKind) -> String {
        switch kind {
        case .phone: "iphone"
        case .tablet: "ipad"
        case .computer, .unknown: "desktopcomputer"
        }
    }

    // MARK: Actions

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let client = try settingsSectionsClient(services)
            async let sessions = client.send(Endpoints.settingsSessions())
            async let currentSession = client.send(Endpoints.session())
            let all = try await sessions
            let currentID = try await currentSession?.session.id
            let current = all.first { $0.id == currentID }
            let others = all
                .filter { $0.id != currentID }
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            state = .loaded(Snapshot(current: current, others: others))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(error) }
        }
    }

    private func revoke(_ entry: SettingsAuthSessionEntry) async {
        revoking = entry.token
        defer { revoking = nil }
        do {
            let client = try settingsSectionsClient(services)
            _ = try await client.send(Endpoints.settingsRevokeSession(token: entry.token))
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func revokeOthers() async {
        do {
            let client = try settingsSectionsClient(services)
            _ = try await client.send(Endpoints.settingsRevokeOtherSessions())
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
