import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("Settings: backup, billing, admin")
struct SettingsBackupBillingAdminTests {
    private let server = try! ServerEndpoint(validating: "https://budget.example.com")

    private func decode<Value>(_ endpoint: Endpoint<Value>, _ json: String) throws -> Value {
        try endpoint.decodeBody(Data(json.utf8), JSONCoding.makeDecoder())
    }

    private func request<Value>(_ endpoint: Endpoint<Value>) throws -> URLRequest {
        try APIClient(server: server).makeRequest(for: endpoint).0
    }

    private func body<Value>(_ endpoint: Endpoint<Value>) throws -> [String: Any] {
        let data = try #require(try request(endpoint).httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Backup

    @Test("Restore status decodes progress, summary, and unknown values leniently")
    func restoreStatusDecoding() throws {
        let json = """
        {"status":"success","response":{"jobId":"job-1","status":"processing",
        "progress":{"phase":"preparing-securities","tier":2,"table":"transactions","insertedRows":120},
        "summary":{"insertedByTable":{"accounts":3,"transactions":120,"tags":0},
        "warnings":[{"code":"shares_skipped","message":"Shares were skipped","count":2},{"code":"new_code","message":"x"}]}}}
        """
        let status = try decode(Endpoints.settingsBackupRestoreStatus(jobId: "job-1"), json)
        #expect(status.jobId == "job-1")
        #expect(status.status == .processing)
        #expect(status.progress?.phase == .preparingSecurities)
        #expect(status.progress?.insertedRows == 120)
        #expect(status.summary?.warnings.count == 2)
        #expect(status.summary?.restoredTables.map(\.table) == ["transactions", "accounts"])

        let odd = try decode(
            Endpoints.settingsBackupRestoreStatus(jobId: "j"),
            #"{"status":"success","response":{"jobId":"j","status":"exploded","progress":{"phase":"teleporting"}}}"#
        )
        #expect(odd.status == .unknown)
        #expect(odd.progress?.phase == .unknown)
    }

    @Test("Active restore reports whether a job is in flight")
    func activeRestoreDecoding() throws {
        let running = try decode(
            Endpoints.settingsBackupActiveRestore(),
            #"{"status":"success","response":{"state":"running","jobId":"j2","phase":"wiping","insertedRows":5}}"#
        )
        #expect(running.isInFlight)
        #expect(running.phase == .wiping)
        let idle = try decode(Endpoints.settingsBackupActiveRestore(), #"{"status":"success","response":{"state":"idle"}}"#)
        #expect(!idle.isInFlight)
    }

    @Test("Restore sends base64 content and only sends the acknowledgement when set")
    func restoreEncoding() throws {
        let plain = Endpoints.settingsBackupRestore(fileContent: "UEsDBA==")
        #expect(try request(plain).url?.path == "/api/v1/user/backup/restore")
        let plainBody = try body(plain)
        #expect(plainBody["fileContent"] as? String == "UEsDBA==")
        #expect(plainBody["acknowledgeSharing"] == nil)

        let acknowledged = try body(Endpoints.settingsBackupRestore(fileContent: "UEsDBA==", acknowledgeSharing: true))
        #expect(acknowledged["acknowledgeSharing"] as? Bool == true)

        let job = try decode(plain, #"{"status":"success","response":{"jobId":"abc"}}"#)
        #expect(job == "abc")
    }

    @Test("Backup export is a POST to /user/backup")
    func exportRequest() throws {
        let request = try request(Endpoints.settingsBackupExport())
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v1/user/backup")
    }

    @Test("Content-Disposition filenames are parsed and sanitized")
    func contentDisposition() {
        #expect(SettingsUploadFilename.parse(contentDisposition: #"attachment; filename="moneymatter-backup-2026.zip""#) == "moneymatter-backup-2026.zip")
        #expect(SettingsUploadFilename.parse(contentDisposition: "attachment; filename*=UTF-8''back%20up.zip") == "back up.zip")
        #expect(SettingsUploadFilename.parse(contentDisposition: #"attachment; filename="../../etc/passwd""#) == "passwd")
        #expect(SettingsUploadFilename.parse(contentDisposition: nil) == nil)
    }

    @Test("Table names are humanized")
    func humanize() {
        #expect(SettingsBackupSummary.humanize(table: "account_groups") == "Account Groups")
        #expect(SettingsBackupSummary.humanize(table: "user-settings") == "User Settings")
    }

    // MARK: Billing

    private static let subscribedJSON = """
    {"status":"success","response":{"id":1,"username":"u","role":"common","entitlements":{
    "features":["backup_export"],"readOnly":false,"seats":5,"plan":null,"trialEndsAt":"2026-09-01T00:00:00.000Z",
    "subscriptions":[{"externalSubscriptionId":"sub_1","tier":"plus","status":"active","billingCycle":"month",
    "currentPeriodEndsAt":"2026-11-01T00:00:00.000Z","scheduledChange":{"action":"cancel","effectiveAt":"2026-11-01T00:00:00.000Z"}}]}}}
    """

    @Test("Billing account decodes subscriptions and drives tier actions")
    func billingDecoding() throws {
        let account = try decode(Endpoints.settingsBillingAccount(), Self.subscribedJSON)
        let entitlements = try #require(account.entitlements)
        #expect(entitlements.seats == 5)
        #expect(entitlements.subscriptions.first?.scheduledChange?.action == .cancel)
        #expect(SettingsBillingOverview.canSeeBilling(account: account))

        let overview = SettingsBillingOverview(entitlements: entitlements, now: Date.iso("2026-10-09T12:00:00.000Z"))
        #expect(overview.activeTier == .plus)
        #expect(overview.trialDaysLeft == nil)
        #expect(overview.action(for: .plus, cycle: .month) == .current)
        #expect(overview.action(for: .plus, cycle: .year) == .portal(switchPlan: true))
        #expect(overview.action(for: .essential, cycle: .month) == .portal(switchPlan: true))
    }

    @Test("Trial users get checkout, the recommended tier, and days left")
    func trialOverview() {
        let entitlements = SettingsBillingEntitlements(
            features: [], readOnly: false, seats: 5, plan: nil,
            trialEndsAt: Date.iso("2026-10-19T12:00:00.000Z"), subscriptions: []
        )
        let overview = SettingsBillingOverview(entitlements: entitlements, now: Date.iso("2026-10-09T12:00:00.000Z"))
        #expect(overview.trialDaysLeft == 10)
        #expect(overview.showsTrialProgress)
        #expect(overview.isRecommended(.plus))
        #expect(!overview.isRecommended(.essential))
        #expect(overview.action(for: .essential, cycle: .year) == .checkout(tier: .essential, cycle: .year))
    }

    @Test("Billing is hidden for demo users and self-hosted servers")
    func canSeeBilling() {
        let selfHost = SettingsBillingAccount(role: .common, entitlements: SettingsBillingEntitlements(seats: 10))
        let demo = SettingsBillingAccount(role: .demo, entitlements: SettingsBillingEntitlements(seats: 5))
        let missing = SettingsBillingAccount(role: .common, entitlements: nil)
        #expect(!SettingsBillingOverview.canSeeBilling(account: selfHost))
        #expect(!SettingsBillingOverview.canSeeBilling(account: demo))
        #expect(!SettingsBillingOverview.canSeeBilling(account: missing))
    }

    @Test("Checkout and portal bodies match the web payloads")
    func billingRequests() throws {
        let checkout = try body(Endpoints.settingsBillingCheckout(tier: .plus, cycle: .year))
        #expect(checkout["tier"] as? String == "plus")
        #expect(checkout["cycle"] as? String == "year")

        let switchPlan = try body(Endpoints.settingsBillingPortal(switchPlan: true))
        #expect(switchPlan["flow"] as? String == "subscription_update")
        let manage = try body(Endpoints.settingsBillingPortal())
        #expect(manage["flow"] == nil)

        let url = try decode(
            Endpoints.settingsBillingCheckout(tier: .plus, cycle: .month),
            #"{"status":"success","response":{"url":"https://checkout.stripe.com/c/pay/cs_1"}}"#
        )
        #expect(url.host == "checkout.stripe.com")
    }

    @Test("Tier prices and savings match the web headline amounts")
    func prices() {
        #expect(SettingsBillingTier.essential.displayPrice(cycle: .month) == 5)
        #expect(SettingsBillingTier.plus.displayPrice(cycle: .year) == 55)
        #expect(SettingsBillingTier.plus.yearlySavings == 41)
    }

    // MARK: Admin

    @Test("CSV parsing handles quotes, escaped quotes, CRLF, and blank lines")
    func csvParsing() throws {
        let csv = "Date,\"Close, USD\",Note\r\n01/02/2024,\"1,234.5\",\"say \"\"hi\"\"\"\r\n\r\n02/02/2024,10\n"
        let file = try SettingsAdminPriceFile.parse(data: Data(csv.utf8), isJSON: false)
        #expect(file.fields == ["Date", "Close, USD", "Note"])
        #expect(file.rows.count == 2)
        #expect(file.rows[0]["Close, USD"] == "1,234.5")
        #expect(file.rows[0]["Note"] == "say \"hi\"")
        #expect(file.rows[1]["Note"] == "")
        #expect(throws: SettingsAdminPriceFile.ParseError.empty) {
            try SettingsAdminPriceFile.parse(data: Data("Date,Price\n".utf8), isJSON: false)
        }
    }

    @Test("JSON price files are read as rows")
    func jsonParsing() throws {
        let json = #"[{"date":"2024-01-02","price":12.5},{"date":"2024-01-03","price":13}]"#
        let file = try SettingsAdminPriceFile.parse(data: Data(json.utf8), isJSON: true)
        #expect(file.fields == ["date", "price"])
        #expect(file.rows[0]["price"] == "12.5")
    }

    @Test("Mapping auto-detects columns and transforms rows to YYYY-MM-DD")
    func mappingTransform() throws {
        let file = SettingsAdminPriceFile(
            fields: ["Trade Date", "Close Value"],
            rows: [["Trade Date": "31/01/2024", "Close Value": "101.25"], ["Trade Date": "01/02/2024", "Close Value": "99"]]
        )
        var mapping = SettingsAdminPriceMapping.autoDetect(fields: file.fields)
        #expect(mapping.columns[.date] == "Trade Date")
        #expect(mapping.columns[.price] == "Close Value")
        #expect(mapping.isComplete)

        let rows = try mapping.rows(from: file, currency: "USD")
        #expect(rows == [
            SettingsAdminPriceRow(price: Decimal(string: "101.25")!, date: "2024-01-31", currency: "USD"),
            SettingsAdminPriceRow(price: 99, date: "2024-02-01", currency: "USD"),
        ])

        mapping.dateFormat = .isoDash
        #expect(throws: SettingsAdminPriceMapping.TransformError.invalidDate(row: 1, value: "31/01/2024")) {
            try mapping.rows(from: file, currency: "USD")
        }
    }

    @Test("Bulk upload body echoes the search result and price rows")
    func bulkUploadEncoding() throws {
        let security = try decode(
            Endpoints.settingsAdminSearchSecurities(query: "VWCE"),
            """
            {"status":"success","response":[{"symbol":"VWCE","providerSymbol":"VWCE.DE","name":"Vanguard FTSE All-World",
            "assetClass":"stocks","providerName":"yahoo","exchangeMic":"XETR","currencyCode":"EUR","logoUrl":null,"isInPortfolio":false}]}
            """
        )
        let result = try #require(security.first)
        #expect(result.providerSymbol == "VWCE.DE")

        let endpoint = Endpoints.settingsAdminBulkUploadPrices(SettingsAdminBulkUploadRequest(
            searchResult: result,
            prices: [SettingsAdminPriceRow(price: Decimal(string: "101.25")!, date: "2024-01-31", currency: "EUR")],
            autoFilter: true,
            override: false
        ))
        let json = try body(endpoint)
        let searchResult = try #require(json["searchResult"] as? [String: Any])
        #expect(searchResult["providerName"] as? String == "yahoo")
        #expect(searchResult["exchangeMic"] as? String == "XETR")
        #expect(searchResult["isInPortfolio"] == nil)
        let prices = try #require(json["prices"] as? [[String: Any]])
        #expect((prices.first?["price"] as? NSNumber)?.doubleValue == 101.25)
        #expect(prices.first?["date"] as? String == "2024-01-31")
        #expect(json["autoFilter"] as? Bool == true)
        #expect(json["override"] as? Bool == false)

        let searchURL = try request(Endpoints.settingsAdminSearchSecurities(query: "VWCE")).url
        #expect(searchURL?.query == "query=VWCE")
    }

    @Test("Upload info and results decode")
    func uploadInfoAndResult() throws {
        let info = try decode(
            Endpoints.settingsAdminPriceUploadInfo(currencyCode: "EUR"),
            #"{"status":"success","response":{"oldestDate":"2000-01-03","newestDate":"2026-10-08","currencyCode":"EUR","minAllowedDate":"1999-01-01T00:00:00.000Z"}}"#
        )
        #expect(SettingsAdminPriceUploadInfo.day(info.minAllowedDate) == "1999-01-01")
        #expect(try body(Endpoints.settingsAdminPriceUploadInfo(currencyCode: "EUR"))["currencyCode"] as? String == "EUR")

        let result = try decode(
            Endpoints.settingsAdminBulkUploadPrices(SettingsAdminBulkUploadRequest(
                searchResult: SettingsAdminSecurity(symbol: "A", providerSymbol: "A", name: "A", assetClass: "stocks", providerName: "fmp", currencyCode: "USD"),
                prices: [], autoFilter: false, override: false
            )),
            #"{"status":"success","response":{"newOldestDate":null,"newNewestDate":"2026-10-08","summary":{"inserted":3,"duplicates":1,"filtered":0}}}"#
        )
        #expect(result.summary.inserted == 3)
        #expect(result.newOldestDate == nil)
    }
}
