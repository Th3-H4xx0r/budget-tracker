import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Inbox notifications")
struct InboxNotificationsKitTests {
    private typealias Support = ConnectionsTestSupport

    @Test("List decodes from the data envelope, with invitation payloads")
    func list() throws {
        let json = """
        {"status":"success","response":{"data":[
          {"id":"n1","type":"share_invitation_received","title":"Invitation","message":"@ann shared Joint",
           "payload":{"invitationId":"i1","token":"tok-1","resourceType":"account","resourceId":"42",
             "resourceName":"Joint","permission":"write","owner":{"id":7,"username":"ann","avatar":null}},
           "status":"unread","priority":"normal","createdAt":"2026-10-09T08:15:00.000Z","readAt":null,"expiresAt":null},
          {"id":"n2","type":"brand_new_type","title":"Hi","message":null,"payload":{},
           "status":"read","priority":"high","createdAt":"2026-10-08T08:15:00.000Z","readAt":"2026-10-08T09:00:00.000Z"},
          {"id":"n3","type":"budget_alert","title":"Budget","payload":{"budgetId":12,"thresholdPercent":80},
           "status":"dismissed","priority":"urgent","createdAt":"2026-10-07T08:15:00.000Z"}
        ],"meta":{"total":3}}}
        """
        let list = try Support.decode(Endpoints.inboxNotifications(), json)
        #expect(list.count == 3)
        #expect(list[0].type.isInvitation)
        #expect(list[0].isUnread)
        #expect(list[0].payload.token == "tok-1")
        #expect(list[0].payload.resourceType == .account)
        #expect(list[0].payload.permission == .write)
        #expect(list[0].payload.ownerUsername == "ann")
        #expect(list[1].type == .unknown)
        #expect(list[1].priority == .high)
        #expect(list[1].readAt == Date.iso("2026-10-08T09:00:00.000Z"))
        #expect(list[2].payload.budgetId == "12")
        #expect(list[2].status == .dismissed)
    }

    @Test("List query sends status only when filtered")
    func listQuery() throws {
        let inbox = try Support.request(Endpoints.inboxNotifications())
        #expect(inbox.url?.query() == "limit=50&offset=0")
        let dismissed = try Support.request(Endpoints.inboxNotifications(status: .dismissed, limit: 100))
        #expect(dismissed.url?.query() == "status=dismissed&limit=100&offset=0")
    }

    @Test("Unread count, read, read-all, and dismiss")
    func mutations() throws {
        #expect(try Support.decode(Endpoints.inboxUnreadCount(), #"{"status":"success","response":{"count":4}}"#) == 4)
        #expect(try Support.decode(Endpoints.markAllInboxNotificationsRead(), #"{"status":"success","response":{"updated":3}}"#) == 3)

        let read = try Support.request(Endpoints.markInboxNotificationRead(id: "n1"))
        #expect(read.httpMethod == "POST")
        #expect(read.url?.path() == "/api/v1/notifications/n1/read")
        let dismiss = try Support.request(Endpoints.dismissInboxNotification(id: "n1"))
        #expect(dismiss.url?.path() == "/api/v1/notifications/n1/dismiss")
        _ = try Support.decode(Endpoints.dismissInboxNotification(id: "n1"), #"{"status":"success","response":{"success":true}}"#)
    }
}

@Suite("Sharing")
struct SharingKitTests {
    private typealias Support = ConnectionsTestSupport

    private let invitationJSON = """
    {"id":"i1","ownerUserId":7,"inviteeEmail":"bob@example.com","inviteeUserId":9,"resourceType":"household",
     "resourceId":"7","permission":"read","policy":null,"token":"tok-1","status":"pending",
     "expiresAt":"2026-10-16T00:00:00.000Z","acceptedAt":null,"declinedAt":null,"revokedAt":null,"resendCount":0,
     "recentResendsAt":[],"createdAt":"2026-10-09T00:00:00.000Z","updatedAt":"2026-10-09T00:00:00.000Z",
     "resourceName":null,"owner":{"id":7,"username":"ann","avatar":null},"invitee":null,"emailConfigured":true}
    """

    @Test("Received invitations decode")
    func received() throws {
        let list = try Support.decode(Endpoints.receivedShareInvitations(), #"{"status":"success","response":[\#(invitationJSON)]}"#)
        let invitation = try #require(list.first)
        #expect(invitation.resourceType == .household)
        #expect(invitation.status == .pending)
        #expect(invitation.owner?.username == "ann")
        #expect(invitation.expiresAt == Date.iso("2026-10-16T00:00:00.000Z"))
        #expect(invitation.emailOutcome == nil)
    }

    @Test("Create sends email, resource, and permission, and reads the email outcome")
    func create() throws {
        let endpoint = Endpoints.createShareInvitation(ShareInvitationCreateRequest(
            inviteeEmail: "  bob@example.com ",
            resourceType: .account,
            resourceId: "42",
            permission: .manage
        ))
        let body = try Support.body(endpoint)
        #expect(body["inviteeEmail"] as? String == "bob@example.com")
        #expect(body["resourceType"] as? String == "account")
        #expect(body["resourceId"] as? String == "42")
        #expect(body["permission"] as? String == "manage")
        #expect(body["policy"] == nil)

        let created = try Support.decode(
            endpoint,
            #"{"status":"success","response":\#(invitationJSON.dropLast()),"emailOutcome":"skipped"}}"#
        )
        #expect(created.emailOutcome == .skipped)
    }

    @Test("Household invitations carry the write scope policy")
    func householdPolicy() throws {
        let body = try Support.body(Endpoints.createShareInvitation(ShareInvitationCreateRequest(
            inviteeEmail: "bob@example.com",
            resourceType: .household,
            resourceId: "7",
            permission: .write,
            policy: SharePolicy(transactionsWriteScope: .own)
        )))
        #expect((body["policy"] as? [String: String]) == ["transactionsWriteScope": "own"])
        #expect(SharePermission.grantable(for: .household) == [.read, .write])
        #expect(SharePermission.grantable(for: .account) == [.read, .write, .manage])
    }

    @Test("Members decode owner and recipients")
    func members() throws {
        let json = """
        {"status":"success","response":{"resourceType":"account","resourceId":"42","resourceName":"Joint","members":[
          {"user":{"id":7,"username":"ann","avatar":null},"role":"owner","permission":"manage","policy":null,"acceptedAt":null,"shareId":null},
          {"user":{"id":9,"username":"bob","avatar":null},"role":"recipient","permission":"write",
           "policy":{"transactionsWriteScope":"own"},"acceptedAt":"2026-10-09T00:00:00.000Z","shareId":"s1"}
        ]}}
        """
        let list = try Support.decode(Endpoints.shareMembers(resourceType: .account, resourceID: "42"), json)
        #expect(list.resourceName == "Joint")
        #expect(list.members.map(\.role) == [.owner, .recipient])
        #expect(list.members[1].policy?.transactionsWriteScope == .own)
        #expect(list.members[1].shareId == "s1")
        let request = try Support.request(Endpoints.shareMembers(resourceType: .account, resourceID: "42"))
        #expect(request.url?.path() == "/api/v1/share/resources/account/42/members")
    }

    @Test("Member update, revoke, and leave hit the resource routes")
    func memberRoutes() throws {
        let update = Endpoints.updateShareMember(resourceType: .household, resourceID: "7", userID: 9, ShareMemberUpdateRequest(permission: .read))
        #expect(try Support.request(update).httpMethod == "PATCH")
        #expect(try Support.request(update).url?.path() == "/api/v1/share/resources/household/7/members/9")
        #expect(try Support.body(update)["permission"] as? String == "read")

        let revoke = try Support.request(Endpoints.revokeShareMember(resourceType: .account, resourceID: "42", userID: 9))
        #expect(revoke.httpMethod == "DELETE")

        let leave = try Support.request(Endpoints.leaveShare(resourceType: .budget, resourceID: "b1"))
        #expect(leave.url?.path() == "/api/v1/share/shared-with-me/budget/b1/leave")
        #expect(leave.httpMethod == "POST")
    }

    @Test("Shared with me rows decode access source")
    func sharedWithMe() throws {
        let json = """
        {"status":"success","response":[
          {"shareId":"s1","resourceType":"account","resourceId":"42","resourceName":"Joint","permission":"read",
           "policy":null,"acceptedAt":"2026-10-09T00:00:00.000Z","owner":{"id":7,"username":"ann","avatar":null},"accessSource":"household"},
          {"shareId":"s2","resourceType":"budget","resourceId":"b1","resourceName":null,"permission":"write",
           "policy":null,"acceptedAt":"2026-10-09T00:00:00.000Z","owner":{"id":7,"username":"ann","avatar":null},"accessSource":"share"}
        ]}
        """
        let rows = try Support.decode(Endpoints.sharedWithMe(), json)
        #expect(rows.map(\.accessSource) == [.household, .share])
        #expect(rows[1].resourceName == nil)
    }

    @Test("Accept reads the share and the back-invite flag")
    func accept() throws {
        let json = """
        {"status":"success","response":{"invitation":{"id":"i1","status":"accepted"},
          "share":{"id":"s1","ownerUserId":7,"sharedWithUserId":9,"resourceType":"household","resourceId":"7",
            "permission":"read","policy":null,"acceptedAt":"2026-10-09T00:00:00.000Z"},"canBackInvite":true}}
        """
        let result = try Support.decode(Endpoints.acceptShareInvitation(token: "tok-1"), json)
        #expect(result.canBackInvite)
        #expect(result.invitationId == "i1")
        #expect(result.share?.resourceType == .household)
        let request = try Support.request(Endpoints.acceptShareInvitation(token: "tok-1"))
        #expect(request.url?.path() == "/api/v1/share/invitations/tok-1/accept")

        let back = try Support.body(Endpoints.backInviteShareInvitation(id: "i1", ShareBackInviteRequest(permission: .write)))
        #expect(back["permission"] as? String == "write")
    }
}
