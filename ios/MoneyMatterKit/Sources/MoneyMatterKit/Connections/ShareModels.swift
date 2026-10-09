import Foundation

// Sharing models and endpoints, following `packages/frontend/src/api/share.ts`.

public enum ShareResourceType: String, LenientEnum, CaseIterable {
    case account
    case household
    case budget
    case unknown
}

public enum SharePermission: String, LenientEnum, CaseIterable {
    case read
    case write
    case manage
    case unknown

    /// What can be granted on a resource. Households never take `manage`.
    public static func grantable(for resourceType: ShareResourceType) -> [SharePermission] {
        resourceType == .household ? [.read, .write] : [.read, .write, .manage]
    }
}

public enum ShareInvitationStatus: String, LenientEnum, CaseIterable {
    case pending
    case accepted
    case declined
    case revoked
    case expired
    case unknown
}

public enum ShareAccessSource: String, LenientEnum, CaseIterable {
    case owner
    case share
    case household
    case budget
    case unknown
}

public enum ShareEmailOutcome: String, LenientEnum, CaseIterable {
    case sent
    case skipped
    case failed
    case unknown
}

public enum ShareMemberRole: String, LenientEnum, CaseIterable {
    case owner
    case recipient
    case unknown
}

public enum ShareTransactionsWriteScope: String, LenientEnum, CaseIterable {
    case all
    case own
    case unknown
}

/// Limits on what a `write` recipient may change.
public struct SharePolicy: Sendable, Hashable, Codable {
    public let transactionsWriteScope: ShareTransactionsWriteScope?

    public init(transactionsWriteScope: ShareTransactionsWriteScope?) {
        self.transactionsWriteScope = transactionsWriteScope
    }
}

public struct ShareUserSummary: Sendable, Hashable, Decodable, Identifiable {
    public let id: Int
    public let username: String
    public let avatar: String?

    private enum CodingKeys: String, CodingKey { case id, username, avatar }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let number = try? container.decode(Int.self, forKey: .id) {
            id = number
        } else {
            id = Int(try container.decode(String.self, forKey: .id)) ?? 0
        }
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
    }
}

/// An invitation row: from the received or sent lists, or returned by create and resend.
public struct ShareInvitation: Sendable, Hashable, Decodable, Identifiable {
    public let id: String
    public let ownerUserId: Int?
    public let inviteeEmail: String
    public let inviteeUserId: Int?
    public let resourceType: ShareResourceType
    public let resourceId: String
    public let permission: SharePermission
    public let token: String
    public let status: ShareInvitationStatus
    public let expiresAt: Date?
    public let createdAt: Date?
    public let resourceName: String?
    public let owner: ShareUserSummary?
    public let invitee: ShareUserSummary?
    /// `false` when the server has no email provider, so the invitee gets no email.
    public let emailConfigured: Bool?
    /// Only on create and resend.
    public let emailOutcome: ShareEmailOutcome?

    private enum CodingKeys: String, CodingKey {
        case id, ownerUserId, inviteeEmail, inviteeUserId, resourceType, resourceId, permission, token, status
        case expiresAt, createdAt, resourceName, owner, invitee, emailConfigured, emailOutcome
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.e1DecodeID(forKey: .id)
        ownerUserId = try? container.decodeIfPresent(Int.self, forKey: .ownerUserId)
        inviteeEmail = try container.decodeIfPresent(String.self, forKey: .inviteeEmail) ?? ""
        inviteeUserId = try? container.decodeIfPresent(Int.self, forKey: .inviteeUserId)
        resourceType = try container.decodeLenient(ShareResourceType.self, forKey: .resourceType, default: .unknown)
        resourceId = container.e1DecodeIDIfPresent(forKey: .resourceId) ?? ""
        permission = try container.decodeLenient(SharePermission.self, forKey: .permission, default: .unknown)
        token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        status = try container.decodeLenient(ShareInvitationStatus.self, forKey: .status, default: .unknown)
        expiresAt = container.e1DecodeDate(forKey: .expiresAt)
        createdAt = container.e1DecodeDate(forKey: .createdAt)
        resourceName = try container.decodeIfPresent(String.self, forKey: .resourceName)
        owner = try? container.decodeIfPresent(ShareUserSummary.self, forKey: .owner)
        invitee = try? container.decodeIfPresent(ShareUserSummary.self, forKey: .invitee)
        emailConfigured = try? container.decodeIfPresent(Bool.self, forKey: .emailConfigured)
        emailOutcome = try? container.decodeIfPresent(ShareEmailOutcome.self, forKey: .emailOutcome)
    }
}

/// One person with access to a resource, owner included.
public struct ShareMember: Sendable, Hashable, Decodable, Identifiable {
    public let user: ShareUserSummary
    public let role: ShareMemberRole
    public let permission: SharePermission
    public let policy: SharePolicy?
    public let acceptedAt: Date?
    public let shareId: String?

    public var id: Int { user.id }

    private enum CodingKeys: String, CodingKey { case user, role, permission, policy, acceptedAt, shareId }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decode(ShareUserSummary.self, forKey: .user)
        role = try container.decodeLenient(ShareMemberRole.self, forKey: .role, default: .unknown)
        permission = try container.decodeLenient(SharePermission.self, forKey: .permission, default: .unknown)
        policy = try? container.decodeIfPresent(SharePolicy.self, forKey: .policy)
        acceptedAt = container.e1DecodeDate(forKey: .acceptedAt)
        shareId = container.e1DecodeIDIfPresent(forKey: .shareId)
    }
}

/// `GET /share/resources/:type/:id/members`.
public struct ShareMembersList: Sendable, Hashable, Decodable {
    public let resourceName: String?
    public let members: [ShareMember]

    private enum CodingKeys: String, CodingKey { case resourceName, members }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resourceName = try container.decodeIfPresent(String.self, forKey: .resourceName)
        members = try container.decodeLossyArrayIfPresent([ShareMember].self, forKey: .members) ?? []
    }
}

/// `GET /share/shared-with-me` row.
public struct SharedWithMeItem: Sendable, Hashable, Decodable, Identifiable {
    public let shareId: String
    public let resourceType: ShareResourceType
    public let resourceId: String
    public let resourceName: String?
    public let permission: SharePermission
    public let policy: SharePolicy?
    public let acceptedAt: Date?
    public let owner: ShareUserSummary
    public let accessSource: ShareAccessSource

    public var id: String { shareId }

    private enum CodingKeys: String, CodingKey {
        case shareId, resourceType, resourceId, resourceName, permission, policy, acceptedAt, owner, accessSource
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shareId = try container.e1DecodeID(forKey: .shareId)
        resourceType = try container.decodeLenient(ShareResourceType.self, forKey: .resourceType, default: .unknown)
        resourceId = container.e1DecodeIDIfPresent(forKey: .resourceId) ?? ""
        resourceName = try container.decodeIfPresent(String.self, forKey: .resourceName)
        permission = try container.decodeLenient(SharePermission.self, forKey: .permission, default: .unknown)
        policy = try? container.decodeIfPresent(SharePolicy.self, forKey: .policy)
        acceptedAt = container.e1DecodeDate(forKey: .acceptedAt)
        owner = try container.decode(ShareUserSummary.self, forKey: .owner)
        accessSource = try container.decodeLenient(ShareAccessSource.self, forKey: .accessSource, default: .share)
    }
}

/// `POST /share/invitations/:token/accept`.
public struct ShareAcceptResult: Sendable, Hashable, Decodable {
    public struct Share: Sendable, Hashable, Decodable {
        public let resourceType: ShareResourceType
        public let resourceId: String

        private enum CodingKeys: String, CodingKey { case resourceType, resourceId }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            resourceType = try container.decodeLenient(ShareResourceType.self, forKey: .resourceType, default: .unknown)
            resourceId = container.e1DecodeIDIfPresent(forKey: .resourceId) ?? ""
        }
    }

    public let invitationId: String?
    public let share: Share?
    /// Household accepts only: the recipient can invite the inviter back into their own household.
    public let canBackInvite: Bool

    private enum CodingKeys: String, CodingKey { case invitation, share, canBackInvite }
    private struct InvitationRef: Decodable {
        let id: String?
        private enum CodingKeys: String, CodingKey { case id }
        init(from decoder: any Decoder) throws {
            id = try decoder.container(keyedBy: CodingKeys.self).e1DecodeIDIfPresent(forKey: .id)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        invitationId = (try? container.decodeIfPresent(InvitationRef.self, forKey: .invitation))?.id
        share = try? container.decodeIfPresent(Share.self, forKey: .share)
        canBackInvite = (try? container.decodeIfPresent(Bool.self, forKey: .canBackInvite)) ?? false
    }
}

// MARK: - Requests

public struct ShareInvitationCreateRequest: Sendable, Hashable, Encodable {
    public let inviteeEmail: String
    public let resourceType: ShareResourceType
    public let resourceId: String
    public let permission: SharePermission
    public let policy: SharePolicy?

    public init(inviteeEmail: String, resourceType: ShareResourceType, resourceId: String, permission: SharePermission, policy: SharePolicy? = nil) {
        self.inviteeEmail = inviteeEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.resourceType = resourceType
        self.resourceId = resourceId
        self.permission = permission
        self.policy = policy
    }
}

public struct ShareMemberUpdateRequest: Sendable, Hashable, Encodable {
    public let permission: SharePermission?
    public let policy: SharePolicy?

    public init(permission: SharePermission? = nil, policy: SharePolicy? = nil) {
        self.permission = permission
        self.policy = policy
    }
}

public struct ShareBackInviteRequest: Sendable, Hashable, Encodable {
    public let permission: SharePermission
    public let policy: SharePolicy?

    public init(permission: SharePermission, policy: SharePolicy? = nil) {
        self.permission = permission
        self.policy = policy
    }
}

// MARK: - Endpoints

extension Endpoints {
    private static func shareResourcePath(_ type: ShareResourceType, _ id: String) -> String {
        "/share/resources/\(type.rawValue)/\(id)"
    }

    /// `POST /share/invitations`.
    public static func createShareInvitation(_ request: ShareInvitationCreateRequest) -> Endpoint<ShareInvitation> {
        Endpoint(.post, "/share/invitations", body: request)
    }

    /// `GET /share/invitations/received`.
    public static func receivedShareInvitations() -> Endpoint<[ShareInvitation]> {
        Endpoint(.get, "/share/invitations/received")
    }

    /// `GET /share/invitations/sent`.
    public static func sentShareInvitations() -> Endpoint<[ShareInvitation]> {
        Endpoint(.get, "/share/invitations/sent")
    }

    /// `POST /share/invitations/:token/accept`.
    public static func acceptShareInvitation(token: String) -> Endpoint<ShareAcceptResult> {
        Endpoint(.post, "/share/invitations/\(token)/accept")
    }

    /// `POST /share/invitations/:token/decline`.
    public static func declineShareInvitation(token: String) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/share/invitations/\(token)/decline")
    }

    /// `POST /share/invitations/:id/resend`.
    public static func resendShareInvitation(id: String) -> Endpoint<ShareInvitation> {
        Endpoint(.post, "/share/invitations/\(id)/resend")
    }

    /// `DELETE /share/invitations/:id`: cancels a pending invitation.
    public static func cancelShareInvitation(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/share/invitations/\(id)")
    }

    /// `POST /share/invitations/:id/back-invite`: shares the recipient's household back.
    public static func backInviteShareInvitation(id: String, _ request: ShareBackInviteRequest) -> Endpoint<ShareInvitation> {
        Endpoint(.post, "/share/invitations/\(id)/back-invite", body: request)
    }

    /// `GET /share/resources/:type/:id/members`.
    public static func shareMembers(resourceType: ShareResourceType, resourceID: String) -> Endpoint<ShareMembersList> {
        Endpoint(.get, "\(shareResourcePath(resourceType, resourceID))/members")
    }

    /// `PATCH /share/resources/:type/:id/members/:userId`.
    public static func updateShareMember(
        resourceType: ShareResourceType,
        resourceID: String,
        userID: Int,
        _ request: ShareMemberUpdateRequest
    ) -> Endpoint<EmptyResponse> {
        Endpoint(.patch, "\(shareResourcePath(resourceType, resourceID))/members/\(userID)", body: request)
    }

    /// `DELETE /share/resources/:type/:id/members/:userId`.
    public static func revokeShareMember(resourceType: ShareResourceType, resourceID: String, userID: Int) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "\(shareResourcePath(resourceType, resourceID))/members/\(userID)")
    }

    /// `GET /share/shared-with-me`.
    public static func sharedWithMe() -> Endpoint<[SharedWithMeItem]> {
        Endpoint(.get, "/share/shared-with-me")
    }

    /// `POST /share/shared-with-me/:type/:id/leave`.
    public static func leaveShare(resourceType: ShareResourceType, resourceID: String) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/share/shared-with-me/\(resourceType.rawValue)/\(resourceID)/leave")
    }
}
