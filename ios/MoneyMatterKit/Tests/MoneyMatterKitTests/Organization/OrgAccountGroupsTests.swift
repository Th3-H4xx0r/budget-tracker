import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Organization: account groups")
struct OrgAccountGroupsTests {
    private let server = try! ServerEndpoint(validating: "https://budget.example.com")

    private func request<Response>(_ endpoint: Endpoint<Response>) throws -> URLRequest {
        try APIClient(server: server).makeRequest(for: endpoint).0
    }

    private func body<Response>(_ endpoint: Endpoint<Response>) throws -> [String: Any] {
        let data = try #require(try request(endpoint).httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Groups decode logo fields, nested children, and accounts")
    func decodeGroups() throws {
        let groups = try Fixture.decode(Endpoints.orgAccountGroups(), from: "account-groups")
        #expect(!groups.isEmpty)
        let root = try #require(groups.first { $0.id == "g-root" })
        #expect(root.parentGroupId == nil)
        #expect(root.logoDomain == nil)
        #expect(!root.accounts.isEmpty)
        #expect(OrgAccountGroup.roots(of: groups).contains { $0.id == "g-root" })
    }

    @Test("A group with logo fields and a bad account row still decodes")
    func decodeLenient() throws {
        let json = """
        {"status":"success","response":[
          {"id":"g1","name":"Bank","userId":1,"parentGroupId":null,"bankDataProviderConnectionId":"conn-1",
           "logoDomain":"chase.com","logoInitials":null,"logoColor":null,
           "accounts":[{"id":"broken"}],
           "childGroups":[{"id":"g2","name":"Cards","parentGroupId":"g1","logoInitials":"CC","logoColor":"#112233"}]}
        ]}
        """
        let groups = try Endpoints.orgAccountGroups().decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
        let group = try #require(groups.first)
        #expect(group.bankDataProviderConnectionId == "conn-1")
        #expect(group.logoDomain == "chase.com")
        #expect(group.accounts.isEmpty)
        #expect(group.childGroups.first?.logoInitials == "CC")
        #expect(group.descendantIDs == ["g2"])
    }

    @Test("includeArchived is only sent when true")
    func listQuery() throws {
        #expect(try request(Endpoints.orgAccountGroups()).url?.query == nil)
        #expect(try request(Endpoints.orgAccountGroups(includeArchived: true)).url?.query == "includeArchived=true")
    }

    @Test("Create sends parent and initials logo without nulls")
    func createGroup() throws {
        let endpoint = Endpoints.orgCreateAccountGroup(
            OrgAccountGroupRequest(name: "Savings", parentGroupId: "g1", logo: .initials("SV", color: "#00ff00"), isUpdate: false)
        )
        let request = try request(endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v1/account-group")
        let json = try body(endpoint)
        #expect(json["name"] as? String == "Savings")
        #expect(json["parentGroupId"] as? String == "g1")
        #expect(json["logoInitials"] as? String == "SV")
        #expect(json["logoColor"] as? String == "#00ff00")
        #expect(json["logoDomain"] == nil)

        let plain = try body(Endpoints.orgCreateAccountGroup(OrgAccountGroupRequest(name: "Plain", isUpdate: false)))
        #expect(plain.keys.sorted() == ["name"])
    }

    @Test("Update clears the logo fields the chosen style doesn't use")
    func updateGroup() throws {
        let endpoint = Endpoints.orgUpdateAccountGroup(
            id: "g1",
            OrgAccountGroupRequest(name: "Chase", logo: .domain("chase.com"), isUpdate: true)
        )
        let request = try request(endpoint)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/v1/account-group/g1")
        let json = try body(endpoint)
        #expect(json["logoDomain"] as? String == "chase.com")
        #expect(json["logoInitials"] is NSNull)
        #expect(json["logoColor"] is NSNull)
        #expect(json["parentGroupId"] == nil)

        let cleared = try body(Endpoints.orgUpdateAccountGroup(id: "g1", OrgAccountGroupRequest(name: "Chase", isUpdate: true)))
        #expect(cleared["logoDomain"] is NSNull)
        #expect(cleared["logoInitials"] is NSNull)
    }

    @Test("Move always sends newParentGroupId, null for the top level")
    func moveGroup() throws {
        let toRoot = Endpoints.orgMoveAccountGroup(id: "g2", newParentGroupId: nil)
        #expect(try request(toRoot).httpMethod == "PUT")
        #expect(try request(toRoot).url?.path == "/api/v1/account-group/g2/move")
        #expect(try body(toRoot)["newParentGroupId"] is NSNull)
        #expect(try body(Endpoints.orgMoveAccountGroup(id: "g2", newParentGroupId: "g1"))["newParentGroupId"] as? String == "g1")
    }

    @Test("Account membership paths and bodies")
    func membership() throws {
        let add = try request(Endpoints.orgAddAccountToGroup(groupId: "g1", accountId: "a1"))
        #expect(add.httpMethod == "POST")
        #expect(add.url?.path == "/api/v1/account-group/g1/add-account/a1")
        #expect(add.httpBody == nil)

        let remove = Endpoints.orgRemoveAccountsFromGroup(groupId: "g1", accountIds: ["a1", "a2"])
        #expect(try request(remove).httpMethod == "DELETE")
        #expect(try request(remove).url?.path == "/api/v1/account-group/g1/accounts")
        #expect(try body(remove)["accountIds"] as? [String] == ["a1", "a2"])

        let delete = try request(Endpoints.orgDeleteAccountGroup(id: "g1"))
        #expect(delete.httpMethod == "DELETE")
        #expect(delete.url?.path == "/api/v1/account-group/g1")
    }
}
