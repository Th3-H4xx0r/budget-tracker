import MoneyMatterKit
import SwiftUI

/// Accept or decline one invitation, found by its token. Opened from notifications, Shared
/// with Me, and `?invitation_token=` links. A household accept can offer to share the
/// recipient's own household back.
struct ShareInvitationReviewSheet: View {
    let token: String

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var invitation: LoadState<ShareInvitation?> = .idle
    @State private var outcome: Outcome?
    @State private var isWorking = false
    @State private var isDeclineConfirmPresented = false
    @State private var backInvitePermission: SharePermission = .read
    @State private var backInviteSent = false
    @State private var errorAlert: ErrorAlert?

    private enum Outcome {
        case accepted(ShareAcceptResult)
        case declined
    }

    var body: some View {
        NavigationStack {
            Form {
                switch invitation {
                case .idle, .loading:
                    Section {
                        LabeledContent("Resource", value: "Placeholder account")
                        LabeledContent("From", value: "@username")
                        LabeledContent("Access", value: "Can edit")
                    }
                    .redactedWhileLoading(true)
                case .failed(let error):
                    InlineRetryView(ErrorMessage.message(for: error)) { await load() }
                case .loaded(let found):
                    if let outcome {
                        outcomeSection(outcome, invitation: found)
                    } else if let found {
                        details(found)
                    } else {
                        ContentUnavailableView(
                            "Invitation Unavailable",
                            systemImage: "envelope.badge.shield.half.filled",
                            description: Text("This invitation was already answered, was cancelled, or expired.")
                        )
                    }
                }
            }
            .navigationTitle("Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(outcome == nil ? "Close" : "Done") { dismiss() }
                }
            }
            .task { if case .idle = invitation { await load() } }
            .confirmationDialog("Decline this invitation?", isPresented: $isDeclineConfirmPresented, titleVisibility: .visible) {
                Button("Decline", role: .destructive) { Task { await decline() } }
            } message: {
                Text("The sender is notified. They can invite you again later.")
            }
            .errorAlert($errorAlert)
            .disabled(isWorking)
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func details(_ invitation: ShareInvitation) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(ShareText.invitationHeadline(invitation))
                    .font(.headline)
                if invitation.resourceType == .household {
                    Text("You'll see their accounts and transactions. Budgets stay private unless shared separately.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            if invitation.resourceType != .household {
                LabeledContent("Shared", value: invitation.resourceName ?? String(localized: "Unnamed"))
            }
            LabeledContent("Type", value: ShareText.resourceType(invitation.resourceType))
            LabeledContent("Access", value: ShareText.permission(invitation.permission))
            if let expires = invitation.expiresAt {
                LabeledContent("Expires", value: expires.formatted(date: .abbreviated, time: .omitted))
            }
        }
        Section {
            Button {
                Task { await accept() }
            } label: {
                HStack {
                    Spacer()
                    if isWorking { ProgressView() } else { Text("Accept").bold() }
                    Spacer()
                }
            }
            Button("Decline", role: .destructive) { isDeclineConfirmPresented = true }
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func outcomeSection(_ outcome: Outcome, invitation: ShareInvitation?) -> some View {
        switch outcome {
        case .declined:
            ContentUnavailableView("Invitation Declined", systemImage: "xmark.circle", description: Text("Nothing was shared with you."))
        case .accepted(let result):
            Section {
                Label("Invitation accepted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if result.share?.resourceType == .account {
                    Text("The account now appears in your Accounts list.")
                        .foregroundStyle(.secondary)
                } else if result.share?.resourceType == .budget {
                    Text("The budget now appears in Planning.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("You've joined the household.")
                        .foregroundStyle(.secondary)
                }
            }
            if result.canBackInvite, let invitationID = result.invitationId ?? invitation?.id {
                Section {
                    if backInviteSent {
                        Label("Invitation sent", systemImage: "paperplane.fill")
                    } else {
                        Picker("Their access", selection: $backInvitePermission) {
                            ForEach(SharePermission.grantable(for: .household), id: \.self) { permission in
                                Text(ShareText.permission(permission)).tag(permission)
                            }
                        }
                        Button("Invite Them to Your Household") {
                            Task { await backInvite(invitationID: invitationID) }
                        }
                    }
                } header: {
                    Text("Share Your Household Back")
                } footer: {
                    Text("Optional. They'll get an invitation to see your accounts too.")
                }
            }
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        invitation = .loading
        do {
            let received = try await client.send(Endpoints.receivedShareInvitations())
            invitation = .loaded(received.first { $0.token == token && $0.status == .pending })
        } catch {
            invitation = .failed(APIError(error))
        }
    }

    private func accept() async {
        guard let client = services.client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await client.send(Endpoints.acceptShareInvitation(token: token))
            outcome = .accepted(result)
            await referenceData.refreshAccounts()
            TransactionChangeFeed.shared.publish(.invalidated)
            await NotificationsUnreadCounter.shared.refresh(client: client)
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func decline() async {
        guard let client = services.client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.send(Endpoints.declineShareInvitation(token: token))
            outcome = .declined
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func backInvite(invitationID: String) async {
        guard let client = services.client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.send(Endpoints.backInviteShareInvitation(
                id: invitationID,
                ShareBackInviteRequest(permission: backInvitePermission)
            ))
            backInviteSent = true
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

/// Copy shared by the sharing screens.
enum ShareText {
    static func permission(_ permission: SharePermission) -> String {
        switch permission {
        case .read: String(localized: "Can view")
        case .write: String(localized: "Can edit")
        case .manage: String(localized: "Can manage")
        case .unknown: String(localized: "Unknown")
        }
    }

    static func permissionDetail(_ permission: SharePermission) -> String {
        switch permission {
        case .read: String(localized: "View balances and transactions.")
        case .write: String(localized: "View, add, and edit transactions.")
        case .manage: String(localized: "Edit, and manage who else has access.")
        case .unknown: ""
        }
    }

    static func resourceType(_ type: ShareResourceType) -> String {
        switch type {
        case .account: String(localized: "Account")
        case .budget: String(localized: "Budget")
        case .household: String(localized: "Household")
        case .unknown: String(localized: "Item")
        }
    }

    static func invitationHeadline(_ invitation: ShareInvitation) -> String {
        let sender = invitation.owner.map { "@\($0.username)" } ?? String(localized: "Someone")
        if invitation.resourceType == .household {
            return String(localized: "\(sender) invited you to their household")
        }
        let name = invitation.resourceName ?? String(localized: "an item")
        return String(localized: "\(sender) shared \(name) with you")
    }

    static func writeScope(_ scope: ShareTransactionsWriteScope) -> String {
        switch scope {
        case .all: String(localized: "All transactions")
        case .own: String(localized: "Only their own transactions")
        case .unknown: String(localized: "Unknown")
        }
    }

    /// The web link that opens an invitation, for sharing by hand when the server can't email.
    static func inviteLink(token: String, resourceType: ShareResourceType, server: ServerEndpoint?) -> URL? {
        guard let server else { return nil }
        let path = resourceType == .budget ? "budgets" : "accounts"
        var components = URLComponents(url: server.origin.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "invitation_token", value: token)]
        return components?.url
    }
}
