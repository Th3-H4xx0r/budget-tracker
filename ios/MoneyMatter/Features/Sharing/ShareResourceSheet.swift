import MoneyMatterKit
import SwiftUI

/// Share an account or budget: invite by email with a permission, see who has access,
/// change or revoke it, and resend or cancel pending invitations.
struct ShareResourceSheet: View {
    let resourceType: ShareResourceType
    let resourceID: String

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var members: LoadState<ShareMembersList> = .idle
    @State private var pending: [ShareInvitation] = []
    @State private var email = ""
    @State private var permission: SharePermission = .read
    @State private var isInviting = false
    @State private var memberToRevoke: ShareMember?
    @State private var manualLink: URL?
    @State private var errorAlert: ErrorAlert?

    init(resourceType: ShareResourceType, resourceID: String) {
        self.resourceType = resourceType
        self.resourceID = resourceID
    }

    var body: some View {
        NavigationStack {
            Form {
                inviteSection
                switch members {
                case .idle, .loading:
                    Section("People with Access") {
                        LabeledContent("@username", value: "Owner")
                        LabeledContent("@username", value: "Can view")
                    }
                    .redactedWhileLoading(true)
                case .failed(let error):
                    Section {
                        InlineRetryView(ErrorMessage.message(for: error)) { await load() }
                    }
                case .loaded(let list):
                    membersSection(list)
                    pendingSection
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await load() }
            .task { if case .idle = members { await load() } }
            .confirmationDialog(
                "Remove access?",
                isPresented: Binding(get: { memberToRevoke != nil }, set: { if !$0 { memberToRevoke = nil } }),
                titleVisibility: .visible,
                presenting: memberToRevoke
            ) { member in
                Button("Remove @\(member.user.username)", role: .destructive) {
                    Task { await revoke(member) }
                }
            } message: { member in
                Text("@\(member.user.username) will no longer see this \(ShareText.resourceType(resourceType).lowercased()).")
            }
            .errorAlert($errorAlert)
        }
    }

    private var title: String {
        if let name = members.value?.resourceName, !name.isEmpty {
            return String(localized: "Share \(name)")
        }
        return String(localized: "Share")
    }

    private var inviteSection: some View {
        Section {
            TextField("Email address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Picker("Access", selection: $permission) {
                ForEach(SharePermission.grantable(for: resourceType), id: \.self) { option in
                    Text(ShareText.permission(option)).tag(option)
                }
            }
            Button {
                Task { await invite() }
            } label: {
                if isInviting {
                    ProgressView()
                } else {
                    Text("Send Invitation")
                }
            }
            .disabled(!isEmailValid || isInviting)
        } header: {
            Text("Invite")
        } footer: {
            Text(ShareText.permissionDetail(permission))
        }
    }

    private func membersSection(_ list: ShareMembersList) -> some View {
        Section("People with Access") {
            ForEach(list.members) { member in
                HStack(spacing: 12) {
                    InitialsBadge(String(member.user.username.prefix(2)).uppercased(), size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "@\(member.user.username)")
                        Text(member.role == .owner ? String(localized: "Owner") : ShareText.permission(member.permission))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if member.role == .recipient {
                        Menu {
                            Picker("Access", selection: Binding(
                                get: { member.permission },
                                set: { newValue in Task { await update(member, permission: newValue) } }
                            )) {
                                ForEach(SharePermission.grantable(for: resourceType), id: \.self) { option in
                                    Text(ShareText.permission(option)).tag(option)
                                }
                            }
                            Button("Remove Access", systemImage: "person.badge.minus", role: .destructive) {
                                memberToRevoke = member
                            }
                        } label: {
                            Label("Manage @\(member.user.username)", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                .swipeActions {
                    if member.role == .recipient {
                        Button("Remove", role: .destructive) { memberToRevoke = member }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        if !pending.isEmpty {
            Section("Pending Invitations") {
                ForEach(pending) { invitation in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invitation.inviteeEmail)
                        HStack(spacing: 4) {
                            Text(ShareText.permission(invitation.permission))
                            if let expires = invitation.expiresAt {
                                Text(verbatim: "·")
                                Text("Expires \(expires.formatted(date: .abbreviated, time: .omitted))")
                            }
                        }
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
                        if let link = ShareText.inviteLink(token: invitation.token, resourceType: resourceType, server: services.client?.server) {
                            ShareLink(item: link) { Label("Share Link", systemImage: "square.and.arrow.up") }
                        }
                        Button("Cancel Invitation", systemImage: "xmark", role: .destructive) { Task { await cancel(invitation) } }
                    }
                }
            }
        }
    }

    private var isEmailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        return trimmed.distance(from: trimmed.startIndex, to: at) > 0 && trimmed[at...].contains(".")
    }

    private func load() async {
        guard let client = services.client else { return }
        if members.value == nil { members = .loading }
        do {
            async let list = client.send(Endpoints.shareMembers(resourceType: resourceType, resourceID: resourceID))
            async let sent = client.send(Endpoints.sentShareInvitations())
            members = .loaded(try await list)
            pending = (try? await sent)?.filter {
                $0.resourceType == resourceType && $0.resourceId == resourceID && $0.status == .pending
            } ?? []
        } catch {
            if members.value == nil { members = .failed(APIError(error)) } else { errorAlert = ErrorAlert(error) }
        }
    }

    private func invite() async {
        guard let client = services.client else { return }
        isInviting = true
        defer { isInviting = false }
        do {
            let created = try await client.send(Endpoints.createShareInvitation(ShareInvitationCreateRequest(
                inviteeEmail: email,
                resourceType: resourceType,
                resourceId: resourceID,
                permission: permission
            )))
            handleEmailOutcome(created)
            email = ""
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func handleEmailOutcome(_ invitation: ShareInvitation) {
        switch invitation.emailOutcome {
        case .skipped:
            manualLink = ShareText.inviteLink(token: invitation.token, resourceType: resourceType, server: services.client?.server)
        case .failed:
            errorAlert = ErrorAlert(
                title: String(localized: "Email Not Sent"),
                message: String(localized: "The invitation was created, but the email failed. Resend it or share the link.")
            )
        default:
            break
        }
    }

    private func update(_ member: ShareMember, permission: SharePermission) async {
        guard let client = services.client, permission != member.permission else { return }
        do {
            _ = try await client.send(Endpoints.updateShareMember(
                resourceType: resourceType,
                resourceID: resourceID,
                userID: member.user.id,
                ShareMemberUpdateRequest(permission: permission)
            ))
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func revoke(_ member: ShareMember) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.revokeShareMember(resourceType: resourceType, resourceID: resourceID, userID: member.user.id))
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func resend(_ invitation: ShareInvitation) async {
        guard let client = services.client else { return }
        do {
            let resent = try await client.send(Endpoints.resendShareInvitation(id: invitation.id))
            handleEmailOutcome(resent)
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
