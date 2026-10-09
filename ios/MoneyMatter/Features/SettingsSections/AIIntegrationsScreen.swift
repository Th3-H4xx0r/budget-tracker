import MoneyMatterKit
import SwiftUI
import UIKit

/// Settings > AI > Integrations: the MCP server URL to paste into Claude, ChatGPT, or another
/// MCP client, and the apps already connected through it, which can be revoked.
struct AIIntegrationsScreen: View {
    @Environment(AppServices.self) private var services
    @State private var state: LoadState<[SettingsMCPConnectedApp]> = .idle
    @State private var alert: ErrorAlert?
    @State private var pendingRevoke: SettingsMCPConnectedApp?
    @State private var didCopy = false
    @State private var revokingID: String?

    var body: some View {
        List {
            serverSection
            quickConnectSection
            connectedAppsSection
        }
        .navigationTitle("Integrations")
        .task {
            if case .idle = state { await load() }
        }
        .refreshable { await load() }
        .confirmationDialog(
            "Revoke access?",
            isPresented: Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } }),
            titleVisibility: .visible,
            presenting: pendingRevoke
        ) { app in
            Button("Revoke \(app.name ?? String(localized: "App"))", role: .destructive) { revoke(app) }
        } message: { _ in
            Text("The app loses access to your MoneyMatter data right away. You can connect it again later.")
        }
        .errorAlert($alert)
    }

    // MARK: Sections

    private var serverURL: URL? {
        services.client.map { Endpoints.settingsMCPServerURL(server: $0.server) }
    }

    @ViewBuilder
    private var serverSection: some View {
        if let serverURL {
            Section {
                Text(serverURL.absoluteString)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                Button {
                    UIPasteboard.general.url = serverURL
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        didCopy = false
                    }
                } label: {
                    Label(didCopy ? "Copied" : "Copy URL", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .sensoryFeedback(.success, trigger: didCopy) { _, copied in copied }
                ShareLink(item: serverURL) {
                    Label("Share URL", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("MCP Server")
            } footer: {
                Text("Add this URL as a custom connector in an AI assistant that supports the Model Context Protocol, then sign in to let it read your MoneyMatter data.")
            }
        }
    }

    private var quickConnectSection: some View {
        Section {
            if let claude = URL(string: "https://claude.ai/customize/connectors") {
                Link(destination: claude) {
                    Label("Open Claude Connectors", systemImage: "arrow.up.forward.app")
                }
            }
            if let chatGPT = URL(string: "https://chatgpt.com/settings#settings/Connectors") {
                Link(destination: chatGPT) {
                    Label("Open ChatGPT Connectors", systemImage: "arrow.up.forward.app")
                }
            }
        } header: {
            Text("Quick Connect")
        } footer: {
            Text("Add a custom connector, paste the server URL, then approve access when MoneyMatter asks.")
        }
    }

    @ViewBuilder
    private var connectedAppsSection: some View {
        Section {
            switch state {
            case .idle, .loading:
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading) {
                        Text("Connected app name")
                        Text("Connected on a date")
                            .font(.caption)
                    }
                }
                .redactedWhileLoading(true)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await load() }
            case .loaded(let apps):
                if apps.isEmpty {
                    ContentUnavailableView {
                        Label("No Connected Apps", systemImage: "puzzlepiece.extension")
                    } description: {
                        Text("Apps you connect through the MCP server appear here.")
                    } actions: {
                        if let serverURL {
                            Button("Copy Server URL") { UIPasteboard.general.url = serverURL }
                                .buttonStyle(.bordered)
                        }
                    }
                } else {
                    ForEach(apps) { app in
                        appRow(app)
                    }
                }
            }
        } header: {
            Text("Connected Apps")
        } footer: {
            if case .loaded(let apps) = state, !apps.isEmpty {
                Text("Swipe an app to revoke its access.")
            }
        }
    }

    private func appRow(_ app: SettingsMCPConnectedApp) -> some View {
        HStack(alignment: .top, spacing: 12) {
            appIcon(app)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name ?? String(localized: "Unknown App"))
                    .font(.body.weight(.medium))
                if let connectedAt = app.connectedAt {
                    Text("Connected \(connectedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastUsedAt = app.lastUsedAt {
                    Text("Last used \(lastUsedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !app.scopes.isEmpty {
                    Text("Access: \(app.scopes.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if revokingID == app.clientId {
                ProgressView()
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button("Revoke", systemImage: "xmark.circle", role: .destructive) { pendingRevoke = app }
        }
        .contextMenu {
            Button("Revoke Access", systemImage: "xmark.circle", role: .destructive) { pendingRevoke = app }
        }
    }

    @ViewBuilder
    private func appIcon(_ app: SettingsMCPConnectedApp) -> some View {
        let placeholder = Image(systemName: "app.connected.to.app.below.fill")
            .font(.title3)
            .foregroundStyle(.tint)
            .frame(width: 32, height: 32)
        if let icon = app.icon, let url = URL(string: icon), url.scheme == "https" {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                placeholder
            }
            .frame(width: 32, height: 32)
            .clipShape(.rect(cornerRadius: 7))
            .accessibilityHidden(true)
        } else {
            placeholder.accessibilityHidden(true)
        }
    }

    // MARK: Data

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await services.settingsAIClient().send(Endpoints.settingsMCPConnectedApps()))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(apiError) }
        }
    }

    private func revoke(_ app: SettingsMCPConnectedApp) {
        revokingID = app.clientId
        Task {
            defer { revokingID = nil }
            do {
                _ = try await services.settingsAIClient().send(Endpoints.settingsMCPRevokeConnectedApp(clientID: app.clientId))
            } catch {
                alert = ErrorAlert(error)
            }
            await load()
        }
    }
}
