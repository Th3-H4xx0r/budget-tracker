import MoneyMatterKit
import SwiftUI

/// What other people share with you: pending invitations to accept or decline, then the
/// accounts, budgets, and households you can see, each of which you can leave.
struct SharedWithMeScreen: View {
    private struct InvitationTarget: Identifiable {
        let token: String
        var id: String { token }
    }

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var shares: LoadState<[SharedWithMeItem]> = .idle
    @State private var invitations: [ShareInvitation] = []
    @State private var reviewing: InvitationTarget?
    @State private var leaving: SharedWithMeItem?
    @State private var errorAlert: ErrorAlert?

    var body: some View {
        List {
            switch shares {
            case .idle, .loading:
                Section {
                    ForEach(0..<3, id: \.self) { _ in
                        LabeledContent("Shared account", value: "Can view")
                    }
                }
                .redactedWhileLoading(true)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await load() }
            case .loaded(let rows):
                if !invitations.isEmpty {
                    Section("Pending Invitations") {
                        ForEach(invitations) { invitation in
                            Button {
                                reviewing = InvitationTarget(token: invitation.token)
                            } label: {
                                HStack {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ShareText.invitationHeadline(invitation))
                                                .foregroundStyle(.primary)
                                            Text(ShareText.permission(invitation.permission))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: "envelope.badge")
                                    }
                                    Spacer()
                                    Text("Review")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
                ForEach(grouped(rows), id: \.type) { group in
                    Section(sectionTitle(group.type)) {
                        ForEach(group.rows) { row in
                            shareRow(row)
                        }
                    }
                }
            }
        }
        .overlay {
            if case .loaded(let rows) = shares, rows.isEmpty, invitations.isEmpty {
                ContentUnavailableView(
                    "Nothing Shared with You",
                    systemImage: "person.2",
                    description: Text("When someone shares an account, budget, or household with you, it appears here.")
                )
            }
        }
        .navigationTitle("Shared with Me")
        .refreshable { await load() }
        .task { if case .idle = shares { await load() } }
        .sheet(item: $reviewing, onDismiss: { Task { await load() } }) { target in
            ShareInvitationReviewSheet(token: target.token)
        }
        .confirmationDialog(
            "Leave this share?",
            isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
            titleVisibility: .visible,
            presenting: leaving
        ) { row in
            Button("Leave", role: .destructive) { Task { await leave(row) } }
        } message: { row in
            Text("You'll lose access to \(row.resourceName ?? ShareText.resourceType(row.resourceType)). @\(row.owner.username) can invite you again.")
        }
        .errorAlert($errorAlert)
    }

    @ViewBuilder
    private func shareRow(_ row: SharedWithMeItem) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(row.resourceName ?? String(localized: "Unnamed"))
            Group {
                if row.accessSource == .household, row.resourceType != .household {
                    Text("Via @\(row.owner.username)'s household · \(ShareText.permission(row.permission))")
                } else {
                    Text("From @\(row.owner.username) · \(ShareText.permission(row.permission))")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Group {
            if row.resourceType == .account, referenceData.account(id: row.resourceId) != nil {
                NavigationLink {
                    AccountDetailScreen(accountID: row.resourceId)
                } label: {
                    label
                }
            } else if row.resourceType == .household || row.accessSource == .household {
                NavigationLink {
                    HouseholdScreen()
                } label: {
                    label
                }
            } else {
                label
            }
        }
        .swipeActions {
            if row.accessSource == .share || row.resourceType == .household {
                Button("Leave", role: .destructive) { leaving = row }
            }
        }
        .contextMenu {
            if row.accessSource == .share || row.resourceType == .household {
                Button("Leave", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { leaving = row }
            }
        }
    }

    private func grouped(_ rows: [SharedWithMeItem]) -> [(type: ShareResourceType, rows: [SharedWithMeItem])] {
        [ShareResourceType.household, .account, .budget, .unknown].compactMap { type in
            let matching = rows.filter { $0.resourceType == type }
            return matching.isEmpty ? nil : (type, matching)
        }
    }

    private func sectionTitle(_ type: ShareResourceType) -> LocalizedStringKey {
        switch type {
        case .household: "Households"
        case .account: "Accounts"
        case .budget: "Budgets"
        case .unknown: "Other"
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        if shares.value == nil { shares = .loading }
        do {
            async let rows = client.send(Endpoints.sharedWithMe())
            async let received = client.send(Endpoints.receivedShareInvitations())
            shares = .loaded(try await rows)
            invitations = ((try? await received) ?? []).filter { $0.status == .pending }
        } catch {
            if shares.value == nil { shares = .failed(APIError(error)) } else { errorAlert = ErrorAlert(error) }
        }
    }

    private func leave(_ row: SharedWithMeItem) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.leaveShare(resourceType: row.resourceType, resourceID: row.resourceId))
            await referenceData.refreshAccounts()
            TransactionChangeFeed.shared.publish(.invalidated)
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}
