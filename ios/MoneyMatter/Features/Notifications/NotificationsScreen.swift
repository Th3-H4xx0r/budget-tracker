import MoneyMatterKit
import SwiftUI

/// Notifications: the inbox (unread and read), unread only, or dismissed. Tapping marks a
/// notification read; invitations open the accept or decline sheet.
struct NotificationsScreen: View {
    private enum Filter: Hashable, CaseIterable {
        case inbox, unread, dismissed

        var status: InboxNotificationStatus? {
            switch self {
            case .inbox: nil
            case .unread: .unread
            case .dismissed: .dismissed
            }
        }
    }

    private struct InvitationTarget: Identifiable {
        let token: String
        var id: String { token }
    }

    private enum LinkedScreen: Hashable {
        case account(String)
        case household
        case sharedWithMe
    }

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var linkedScreen: LinkedScreen?
    @State private var filter: Filter = .inbox
    @State private var notifications: LoadState<[InboxNotification]> = .idle
    @State private var counter = NotificationsUnreadCounter.shared
    @State private var invitation: InvitationTarget?
    @State private var errorAlert: ErrorAlert?

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    Text("Inbox").tag(Filter.inbox)
                    Text("Unread").tag(Filter.unread)
                    Text("Dismissed").tag(Filter.dismissed)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            switch notifications {
            case .idle, .loading:
                ForEach(0..<5, id: \.self) { _ in
                    NotificationRow.placeholder
                }
                .redactedWhileLoading(true)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await load() }
            case .loaded(let list):
                ForEach(list) { notification in
                    Button {
                        Task { await open(notification) }
                    } label: {
                        NotificationRow(notification: notification)
                    }
                    .swipeActions(edge: .trailing) {
                        if notification.status != .dismissed {
                            Button("Dismiss", systemImage: "xmark") {
                                Task { await dismiss(notification) }
                            }
                            .tint(.gray)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if notification.isUnread {
                            Button("Mark as Read", systemImage: "envelope.open") {
                                Task { await markRead(notification) }
                            }
                            .tint(.blue)
                        }
                    }
                    .contextMenu {
                        if notification.isUnread {
                            Button("Mark as Read", systemImage: "envelope.open") {
                                Task { await markRead(notification) }
                            }
                        }
                        if notification.status != .dismissed {
                            Button("Dismiss", systemImage: "xmark") {
                                Task { await dismiss(notification) }
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if case .loaded(let list) = notifications, list.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "bell.slash")
                } description: {
                    Text("Budget alerts, sharing invitations, and updates appear here.")
                } actions: {
                    if filter != .inbox {
                        Button("Show Inbox") { filter = .inbox }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark All as Read", systemImage: "checkmark.circle") {
                    Task { await markAllRead() }
                }
                .disabled(counter.count == 0)
            }
        }
        .refreshable { await load() }
        .task(id: filter) { await load(showPlaceholder: true) }
        .sheet(item: $invitation, onDismiss: { Task { await load() } }) { target in
            ShareInvitationReviewSheet(token: target.token)
        }
        .navigationDestination(item: $linkedScreen) { screen in
            switch screen {
            case .account(let id): AccountDetailScreen(accountID: id)
            case .household: HouseholdScreen()
            case .sharedWithMe: SharedWithMeScreen()
            }
        }
        .errorAlert($errorAlert)
    }

    private var emptyTitle: LocalizedStringKey {
        switch filter {
        case .inbox: "No Notifications"
        case .unread: "All Caught Up"
        case .dismissed: "Nothing Dismissed"
        }
    }

    private func load(showPlaceholder: Bool = false) async {
        guard let client = services.client else { return }
        if showPlaceholder || notifications.value == nil { notifications = .loading }
        do {
            let list = try await client.send(Endpoints.inboxNotifications(status: filter.status, limit: 100))
            notifications = .loaded(list)
        } catch {
            if notifications.value == nil || showPlaceholder {
                notifications = .failed(APIError(error))
            } else {
                errorAlert = ErrorAlert(error)
            }
        }
        await counter.refresh(client: client)
    }

    private func open(_ notification: InboxNotification) async {
        if notification.isUnread { await markRead(notification) }
        let payload = notification.payload
        if notification.type.isInvitation, let token = payload.token {
            invitation = InvitationTarget(token: token)
        } else if notification.type.rawValue.hasPrefix("household_") {
            linkedScreen = .household
        } else if payload.resourceType == .account, let id = payload.resourceId, referenceData.account(id: id) != nil {
            linkedScreen = .account(id)
        } else if notification.type.rawValue.hasPrefix("share_") {
            linkedScreen = .sharedWithMe
        }
    }

    private func markRead(_ notification: InboxNotification) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.markInboxNotificationRead(id: notification.id))
            counter.set(counter.count - 1)
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func dismiss(_ notification: InboxNotification) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.dismissInboxNotification(id: notification.id))
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func markAllRead() async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.markAllInboxNotificationsRead())
            counter.set(0)
            await load()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

/// Icon by type, title, message, and time; bold with a dot while unread.
private struct NotificationRow: View {
    let notification: InboxNotification?

    static var placeholder: some View {
        NotificationRow(notification: nil)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(notification?.title ?? "Placeholder notification title")
                    .font(.body.weight(notification?.isUnread == true ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let message = notification?.message ?? (notification == nil ? "Placeholder message text" : nil), !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                }
                if notification?.type.isInvitation == true, notification?.payload.token != nil {
                    Text("Tap to review the invitation")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                }
                if let date = notification?.createdAt {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if notification?.isUnread == true {
                Circle()
                    .fill(.tint)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        guard let type = notification?.type else { return "bell" }
        switch type {
        case .budgetAlert: return "chart.pie"
        case .changelog: return "sparkles"
        case .tagReminder: return "tag"
        case .subscriptionReminder: return "calendar.badge.clock"
        case .plannedConfirmed: return "checkmark.seal"
        case .shareInvitationReceived, .householdInvitationReceived: return "envelope.badge"
        case .shareInvitationSendFailed, .householdInvitationSendFailed: return "exclamationmark.bubble"
        case .shareAccepted, .householdAccepted: return "person.crop.circle.badge.checkmark"
        case .shareDeclined, .householdDeclined: return "person.crop.circle.badge.xmark"
        case .shareRevoked, .shareLeft, .shareExpired, .householdRevoked, .householdLeft, .householdExpired:
            return "person.crop.circle.badge.minus"
        case .shareOwnerAccountDeleted, .shareOwnerBudgetDeleted, .householdOwnerAccountDeleted, .householdMemberAccountDeleted:
            return "trash"
        case .householdPermissionChanged: return "house"
        case .system, .unknown: return "bell"
        }
    }

    private var tint: Color {
        switch notification?.priority {
        case .high, .urgent: .orange
        default: .accentColor
        }
    }
}
