import MoneyMatterKit
import SwiftUI

/// Household: the people you share all your accounts with, invitations you've sent, and the
/// households you belong to.
struct HouseholdScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var members: LoadState<[ShareMember]> = .idle
    @State private var pending: [ShareInvitation] = []
    @State private var memberships: [SharedWithMeItem] = []
    @State private var isInvitePresented = false
    @State private var memberToRemove: ShareMember?
    @State private var membershipToLeave: SharedWithMeItem?
    @State private var manualLink: URL?
    @State private var errorAlert: ErrorAlert?

    private var householdID: String? { session.user.map { String($0.id) } }

    var body: some View {
        List {
            switch members {
            case .idle, .loading:
                Section("Members") {
                    ForEach(0..<2, id: \.self) { _ in
                        LabeledContent("@username", value: "Can view")
                    }
                }
                .redactedWhileLoading(true)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await load() }
            case .loaded(let list):
                membersSection(list.filter { $0.role == .recipient })
                pendingSection
                membershipsSection
            }
            if let manualLink {
                Section {
                    ShareLink(item: manualLink) {
                        Label("Share Invitation Link", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text("Your server can't send email, so send this link to the person yourself.")
                }
            }
        }
        .navigationTitle("Household")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Invite Member", systemImage: "person.badge.plus") { isInvitePresented = true }
                    .disabled(householdID == nil)
            }
        }
        .refreshable { await load() }
        .task { if case .idle = members { await load() } }
        .sheet(isPresented: $isInvitePresented) {
            if let householdID {
                HouseholdInviteSheet(householdID: householdID) { created in
                    if created.emailOutcome == .skipped {
                        manualLink = ShareText.inviteLink(token: created.token, resourceType: .household, server: services.client?.server)
                    } else if created.emailOutcome == .failed {
                        errorAlert = ErrorAlert(
                            title: String(localized: "Email Not Sent"),
                            message: String(localized: "The invitation was created, but the email failed. Resend it or share the link.")
                        )
                    }
                    Task { await load() }
                }
            }
        }
        .confirmationDialog(
            "Remove from household?",
            isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }),
            titleVisibility: .visible,
            presenting: memberToRemove
        ) { member in
            Button("Remove @\(member.user.username)", role: .destructive) { Task { await remove(member) } }
        } message: { member in
            Text("@\(member.user.username) will no longer see your accounts.")
        }
        .confirmationDialog(
            "Leave this household?",
            isPresented: Binding(get: { membershipToLeave != nil }, set: { if !$0 { membershipToLeave = nil } }),
            titleVisibility: .visible,
            presenting: membershipToLeave
        ) { membership in
            Button("Leave", role: .destructive) { Task { await leave(membership) } }
        } message: { membership in
            Text("You'll stop seeing @\(membership.owner.username)'s accounts.")
        }
        .errorAlert($errorAlert)
    }

    @ViewBuilder
    private func membersSection(_ recipients: [ShareMember]) -> some View {
        Section {
            if recipients.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No one is in your household yet.")
                        .foregroundStyle(.secondary)
                    Button("Invite Member") { isInvitePresented = true }
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
            ForEach(recipients) { member in
                HStack(spacing: 12) {
                    InitialsBadge(String(member.user.username.prefix(2)).uppercased(), size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "@\(member.user.username)")
                        Text(memberDetail(member))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Picker("Access", selection: Binding(
                            get: { member.permission },
                            set: { value in Task { await update(member, permission: value, scope: member.policy?.transactionsWriteScope) } }
                        )) {
                            ForEach(SharePermission.grantable(for: .household), id: \.self) { option in
                                Text(ShareText.permission(option)).tag(option)
                            }
                        }
                        if member.permission == .write {
                            Picker("Can edit", selection: Binding(
                                get: { member.policy?.transactionsWriteScope ?? .all },
                                set: { value in Task { await update(member, permission: .write, scope: value) } }
                            )) {
                                Text(ShareText.writeScope(.all)).tag(ShareTransactionsWriteScope.all)
                                Text(ShareText.writeScope(.own)).tag(ShareTransactionsWriteScope.own)
                            }
                        }
                        Button("Remove from Household", systemImage: "person.badge.minus", role: .destructive) {
                            memberToRemove = member
                        }
                    } label: {
                        Label("Manage @\(member.user.username)", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) { memberToRemove = member }
                }
            }
        } header: {
            Text("My Household")
        } footer: {
            Text("Members see all your accounts and their transactions. Budgets are shared separately.")
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        if !pending.isEmpty {
            Section("Pending Invitations") {
                ForEach(pending) { invitation in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invitation.inviteeEmail)
                        Text(ShareText.permission(invitation.permission))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Cancel", role: .destructive) { Task { await cancel(invitation) } }
                        Button("Resend") { Task { await resend(invitation) } }
                            .tint(.blue)
                    }
                    .contextMenu {
                        Button("Resend", systemImage: "arrow.clockwise") { Task { await resend(invitation) } }
                        if let link = ShareText.inviteLink(token: invitation.token, resourceType: .household, server: services.client?.server) {
                            ShareLink(item: link) { Label("Share Link", systemImage: "square.and.arrow.up") }
                        }
                        Button("Cancel Invitation", systemImage: "xmark", role: .destructive) { Task { await cancel(invitation) } }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var membershipsSection: some View {
        if !memberships.isEmpty {
            Section {
                ForEach(memberships) { membership in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "@\(membership.owner.username)")
                            Text(ShareText.permission(membership.permission))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Leave", role: .destructive) { membershipToLeave = membership }
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Households I'm In")
            }
        }
    }

    private func memberDetail(_ member: ShareMember) -> String {
        if member.permission == .write, let scope = member.policy?.transactionsWriteScope, scope != .unknown {
            return "\(ShareText.permission(member.permission)) · \(ShareText.writeScope(scope))"
        }
        return ShareText.permission(member.permission)
    }

    private func load() async {
        guard let client = services.client, let householdID else { return }
        if members.value == nil { members = .loading }
        async let sent = client.send(Endpoints.sentShareInvitations())
        async let shared = client.send(Endpoints.sharedWithMe())
        do {
            let list = try await client.send(Endpoints.shareMembers(resourceType: .household, resourceID: householdID))
            members = .loaded(list.members)
        } catch {
            if members.value == nil { members = .failed(APIError(error)) } else { errorAlert = ErrorAlert(error) }
        }
        pending = ((try? await sent) ?? []).filter {
            $0.resourceType == .household && $0.resourceId == householdID && $0.status == .pending
        }
        memberships = ((try? await shared) ?? []).filter { $0.resourceType == .household }
    }

    private func update(_ member: ShareMember, permission: SharePermission, scope: ShareTransactionsWriteScope?) async {
        guard let client = services.client, let householdID else { return }
        let policy = permission == .write ? SharePolicy(transactionsWriteScope: scope ?? .all) : nil
        do {
            _ = try await client.send(Endpoints.updateShareMember(
                resourceType: .household,
                resourceID: householdID,
                userID: member.user.id,
                ShareMemberUpdateRequest(permission: permission, policy: policy)
            ))
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func remove(_ member: ShareMember) async {
        guard let client = services.client, let householdID else { return }
        do {
            _ = try await client.send(Endpoints.revokeShareMember(resourceType: .household, resourceID: householdID, userID: member.user.id))
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func leave(_ membership: SharedWithMeItem) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.leaveShare(resourceType: .household, resourceID: membership.resourceId))
            await referenceData.refreshAccounts()
            TransactionChangeFeed.shared.publish(.invalidated)
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func resend(_ invitation: ShareInvitation) async {
        guard let client = services.client else { return }
        do {
            let resent = try await client.send(Endpoints.resendShareInvitation(id: invitation.id))
            if resent.emailOutcome == .skipped {
                manualLink = ShareText.inviteLink(token: resent.token, resourceType: .household, server: client.server)
            }
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func cancel(_ invitation: ShareInvitation) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.cancelShareInvitation(id: invitation.id))
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

/// Invite someone to your household by email, with read or write access.
private struct HouseholdInviteSheet: View {
    let householdID: String
    let onCreated: (ShareInvitation) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var permission: SharePermission = .read
    @State private var scope: ShareTransactionsWriteScope = .all
    @State private var isSending = false
    @State private var errorAlert: ErrorAlert?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Picker("Access", selection: $permission) {
                        ForEach(SharePermission.grantable(for: .household), id: \.self) { option in
                            Text(ShareText.permission(option)).tag(option)
                        }
                    }
                    if permission == .write {
                        Picker("Can edit", selection: $scope) {
                            Text(ShareText.writeScope(.all)).tag(ShareTransactionsWriteScope.all)
                            Text(ShareText.writeScope(.own)).tag(ShareTransactionsWriteScope.own)
                        }
                    }
                } footer: {
                    Text(ShareText.permissionDetail(permission))
                }
            }
            .navigationTitle("Invite to Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await send() } }
                            .disabled(!email.contains("@"))
                    }
                }
            }
            .errorAlert($errorAlert)
        }
    }

    private func send() async {
        guard let client = services.client else { return }
        isSending = true
        defer { isSending = false }
        do {
            let created = try await client.send(Endpoints.createShareInvitation(ShareInvitationCreateRequest(
                inviteeEmail: email,
                resourceType: .household,
                resourceId: householdID,
                permission: permission,
                policy: permission == .write ? SharePolicy(transactionsWriteScope: scope) : nil
            )))
            onCreated(created)
            dismiss()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}
