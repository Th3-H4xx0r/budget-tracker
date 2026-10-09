import Foundation

public enum InboxNotificationStatus: String, LenientEnum, CaseIterable {
    case unread
    case read
    case dismissed
    case unknown
}

public enum InboxNotificationPriority: String, LenientEnum, CaseIterable {
    case low
    case normal
    case high
    case urgent
    case unknown
}

public enum InboxNotificationType: String, LenientEnum, CaseIterable {
    case budgetAlert = "budget_alert"
    case system
    case changelog
    case tagReminder = "tag_reminder"
    case subscriptionReminder = "subscription_reminder"
    case plannedConfirmed = "planned_confirmed"
    case shareInvitationReceived = "share_invitation_received"
    case shareInvitationSendFailed = "share_invitation_send_failed"
    case shareAccepted = "share_accepted"
    case shareDeclined = "share_declined"
    case shareRevoked = "share_revoked"
    case shareLeft = "share_left"
    case shareExpired = "share_expired"
    case shareOwnerAccountDeleted = "share_owner_account_deleted"
    case shareOwnerBudgetDeleted = "share_owner_budget_deleted"
    case householdInvitationReceived = "household_invitation_received"
    case householdInvitationSendFailed = "household_invitation_send_failed"
    case householdAccepted = "household_accepted"
    case householdDeclined = "household_declined"
    case householdPermissionChanged = "household_permission_changed"
    case householdRevoked = "household_revoked"
    case householdLeft = "household_left"
    case householdExpired = "household_expired"
    case householdOwnerAccountDeleted = "household_owner_account_deleted"
    case householdMemberAccountDeleted = "household_member_account_deleted"
    case unknown

    /// Invitations the person can accept or decline from the notification.
    public var isInvitation: Bool {
        self == .shareInvitationReceived || self == .householdInvitationReceived
    }
}

/// The parts of a notification payload the app acts on. Payloads vary by type, so every
/// field is optional.
public struct InboxNotificationPayload: Sendable, Hashable, Decodable {
    public let token: String?
    public let invitationId: String?
    public let resourceType: ShareResourceType?
    public let resourceId: String?
    public let resourceName: String?
    public let permission: SharePermission?
    public let ownerUsername: String?
    public let counterpartUsername: String?
    public let budgetId: String?

    public static let empty = InboxNotificationPayload()

    init(
        token: String? = nil,
        invitationId: String? = nil,
        resourceType: ShareResourceType? = nil,
        resourceId: String? = nil,
        resourceName: String? = nil,
        permission: SharePermission? = nil,
        ownerUsername: String? = nil,
        counterpartUsername: String? = nil,
        budgetId: String? = nil
    ) {
        self.token = token
        self.invitationId = invitationId
        self.resourceType = resourceType
        self.resourceId = resourceId
        self.resourceName = resourceName
        self.permission = permission
        self.ownerUsername = ownerUsername
        self.counterpartUsername = counterpartUsername
        self.budgetId = budgetId
    }

    private enum CodingKeys: String, CodingKey {
        case token, invitationId, resourceType, resourceId, resourceName, permission, owner, counterpartUser, budgetId
    }

    private struct UserRef: Decodable { let username: String? }

    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        self.init(
            token: try? container.decodeIfPresent(String.self, forKey: .token),
            invitationId: container.e1DecodeIDIfPresent(forKey: .invitationId),
            resourceType: try? container.decodeIfPresent(ShareResourceType.self, forKey: .resourceType),
            resourceId: container.e1DecodeIDIfPresent(forKey: .resourceId),
            resourceName: try? container.decodeIfPresent(String.self, forKey: .resourceName),
            permission: try? container.decodeIfPresent(SharePermission.self, forKey: .permission),
            ownerUsername: (try? container.decodeIfPresent(UserRef.self, forKey: .owner))?.username,
            counterpartUsername: (try? container.decodeIfPresent(UserRef.self, forKey: .counterpartUser))?.username,
            budgetId: container.e1DecodeIDIfPresent(forKey: .budgetId)
        )
    }
}

/// `GET /notifications` row.
public struct InboxNotification: Sendable, Hashable, Decodable, Identifiable {
    public let id: String
    public let type: InboxNotificationType
    public let title: String
    public let message: String?
    public let payload: InboxNotificationPayload
    public let status: InboxNotificationStatus
    public let priority: InboxNotificationPriority
    public let createdAt: Date?
    public let readAt: Date?

    public var isUnread: Bool { status == .unread }

    private enum CodingKeys: String, CodingKey {
        case id, type, title, message, payload, status, priority, createdAt, readAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.e1DecodeID(forKey: .id)
        type = try container.decodeLenient(InboxNotificationType.self, forKey: .type, default: .unknown)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message)
        payload = (try? container.decodeIfPresent(InboxNotificationPayload.self, forKey: .payload)) ?? .empty
        status = try container.decodeLenient(InboxNotificationStatus.self, forKey: .status, default: .unknown)
        priority = try container.decodeLenient(InboxNotificationPriority.self, forKey: .priority, default: .normal)
        createdAt = container.e1DecodeDate(forKey: .createdAt)
        readAt = container.e1DecodeDate(forKey: .readAt)
    }
}

private struct InboxNotificationListEnvelope: Decodable, Sendable {
    let data: [InboxNotification]

    private enum CodingKeys: String, CodingKey { case data }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeLossyArrayIfPresent([InboxNotification].self, forKey: .data) ?? []
    }
}

private struct InboxUnreadCountEnvelope: Decodable, Sendable { let count: Int }
private struct InboxUpdatedEnvelope: Decodable, Sendable { let updated: Int? }

extension Endpoints {
    /// `GET /notifications`. The server caps `limit` at 100.
    public static func inboxNotifications(
        status: InboxNotificationStatus? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) -> Endpoint<[InboxNotification]> {
        var query = QueryBuilder()
        if let status, status != .unknown { query.add("status", status.rawValue) }
        query.add("limit", limit)
        query.add("offset", offset)
        return Endpoint<InboxNotificationListEnvelope>(.get, "/notifications", query: query.items).map(\.data)
    }

    /// `GET /notifications/unread-count`.
    public static func inboxUnreadCount() -> Endpoint<Int> {
        Endpoint<InboxUnreadCountEnvelope>(.get, "/notifications/unread-count").map(\.count)
    }

    /// `POST /notifications/:id/read`.
    public static func markInboxNotificationRead(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/notifications/\(id)/read")
    }

    /// `POST /notifications/read-all`: the number marked read.
    public static func markAllInboxNotificationsRead() -> Endpoint<Int> {
        Endpoint<InboxUpdatedEnvelope>(.post, "/notifications/read-all").map { $0.updated ?? 0 }
    }

    /// `POST /notifications/:id/dismiss`.
    public static func dismissInboxNotification(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/notifications/\(id)/dismiss")
    }
}
