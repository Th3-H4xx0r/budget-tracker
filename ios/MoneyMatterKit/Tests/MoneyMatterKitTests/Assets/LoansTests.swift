import Foundation
import Testing
@testable import MoneyMatterKit

struct LoanKitTests {
    static let loanJSON = """
    {
      "id": "acc-1", "name": "Car loan", "initialBalance": -20000, "refInitialBalance": -20000,
      "currentBalance": -12000.5, "refCurrentBalance": -12000.5, "creditLimit": 0, "refCreditLimit": 0,
      "type": "system", "accountCategory": "loan", "currencyCode": "USD", "userId": 1,
      "status": "active", "excludeFromStats": false,
      "paymentsCount": 4,
      "loanDetails": {
        "id": "ld-1", "loanType": "auto", "originalPrincipal": 20000, "refOriginalPrincipal": 20000,
        "interestRate": 6.5, "termMonths": 60, "startDate": "2024-01-15", "balanceAnchorDate": "2024-01-15",
        "minPayment": 391.32, "refMinPayment": 391.32, "plannedPayment": 450, "refPlannedPayment": 450,
        "paymentDayOfMonth": 15, "lenderName": "Bank", "accountNumber": null,
        "events": [
          {"type": "rate_change", "at": "2025-02-01T10:00:00.000Z", "from": 7, "to": 6.5},
          {"type": "note", "at": "2025-03-01T10:00:00Z", "text": "Refi talk"},
          {"type": "brand_new", "at": "2025-04-01T10:00:00Z"}
        ],
        "createdAt": "2024-01-15T00:00:00.000Z", "updatedAt": "2025-01-15T00:00:00.000Z"
      },
      "projection": {
        "isPaidOff": false, "warning": null, "payoffDate": "2027-06-15", "monthsRemaining": 30,
        "totalInterestRemaining": 1100.25, "estimatedInterestPaid": 900, "monthlyPrincipal": 385,
        "paidToDate": 7999.5, "paidToDatePercent": 39.99, "monthlyInterest": 65
      }
    }
    """

    static func envelope(_ body: String) -> Data {
        Data("{\"status\":\"success\",\"response\":\(body)}".utf8)
    }

    @Test func decodesLoanWithAccountSpreadAtTopLevel() throws {
        let loan = try Endpoints.loan(id: "acc-1").decodeBody(Self.envelope(Self.loanJSON), JSONCoding.makeDecoder())
        #expect(loan.id == "acc-1")
        #expect(loan.name == "Car loan")
        #expect(loan.outstanding == Decimal(string: "12000.5"))
        #expect(loan.paymentsCount == 4)
        #expect(loan.loanDetails.loanType == .auto)
        #expect(loan.loanDetails.startDate == CalendarDate(year: 2024, month: 1, day: 15))
        #expect(loan.loanDetails.accountNumber == nil)
        #expect(loan.loanDetails.events.count == 3)
        #expect(loan.loanDetails.events[0].kind == .rateChange)
        #expect(loan.loanDetails.events[0].to == Decimal(string: "6.5"))
        #expect(loan.loanDetails.events[1].text == "Refi talk")
        #expect(loan.loanDetails.events[2].kind == .unknown)
        #expect(loan.projection.payoffDate == CalendarDate(year: 2027, month: 6, day: 15))
        #expect(loan.projection.totalInterestRemaining == Decimal(string: "1100.25"))
    }

    @Test func decodesStalledProjectionAndUnknownLoanType() throws {
        let json = Self.loanJSON
            .replacingOccurrences(of: "\"loanType\": \"auto\"", with: "\"loanType\": \"spaceship\"")
            .replacingOccurrences(
                of: "\"warning\": null, \"payoffDate\": \"2027-06-15\", \"monthsRemaining\": 30",
                with: "\"warning\": \"no_planned_payment\", \"payoffDate\": null, \"monthsRemaining\": null"
            )
        let loans = try Endpoints.loans().decodeBody(Self.envelope("[\(json)]"), JSONCoding.makeDecoder())
        #expect(loans.first?.loanDetails.loanType == .unknown)
        #expect(loans.first?.projection.warning == .noPlannedPayment)
        #expect(loans.first?.projection.payoffDate == nil)
    }

    @Test func decodesBalanceHistory() throws {
        let body = #"[{"date":"2024-01-15","amount":-20000},{"date":"2024-02-15","amount":-19600.25}]"#
        let points = try Endpoints.loanBalanceHistory(id: "acc-1").decodeBody(Self.envelope(body), JSONCoding.makeDecoder())
        #expect(points.count == 2)
        #expect(points[1].amount == Decimal(string: "-19600.25"))
    }

    @Test func encodesCreateRequestOmittingNils() throws {
        let request = LoanCreateRequest(
            name: "Car",
            currencyCode: "USD",
            initialBalance: 1000,
            loanType: .auto,
            originalPrincipal: 1200,
            interestRate: Decimal(string: "5.5")!,
            termMonths: 24,
            startDate: CalendarDate(year: 2025, month: 3, day: 1)
        )
        let json = try String(decoding: JSONCoding.makeEncoder().encode(request), as: UTF8.self)
        #expect(json.contains("\"startDate\":\"2025-03-01\""))
        #expect(json.contains("\"loanType\":\"auto\""))
        #expect(json.contains("\"termMonths\":24"))
        #expect(!json.contains("lenderName"))
        #expect(!json.contains("plannedPayment"))
    }

    @Test func encodesUpdateRequestWithClearsAndPairedAnchor() throws {
        let request = LoanUpdateRequest(
            currentBalanceAsOf: CalendarDate(year: 2025, month: 1, day: 1),
            plannedPayment: .clear,
            lenderName: .set("New bank")
        )
        let json = try String(decoding: JSONCoding.makeEncoder().encode(request), as: UTF8.self)
        #expect(json == #"{"lenderName":"New bank","plannedPayment":null}"#)

        let withBalance = LoanUpdateRequest(currentBalance: 500, currentBalanceAsOf: CalendarDate(year: 2025, month: 1, day: 1))
        let balanceJSON = try String(decoding: JSONCoding.makeEncoder().encode(withBalance), as: UTF8.self)
        #expect(balanceJSON == #"{"currentBalance":500,"currentBalanceAsOf":"2025-01-01"}"#)
        #expect(LoanUpdateRequest().isEmpty)
    }

    @Test func paymentRequestIsTransferToLoan() throws {
        let request = Endpoints.loanPaymentRequest(
            loanId: "loan-1",
            fromAccountId: "acc-2",
            amount: 100,
            loanAmount: 90,
            time: Date(timeIntervalSince1970: 0)
        )
        let json = try String(decoding: JSONCoding.makeEncoder().encode(request), as: UTF8.self)
        #expect(json.contains("\"transferNature\":\"transfer_to_loan\""))
        #expect(json.contains("\"destinationAccountId\":\"loan-1\""))
        #expect(json.contains("\"destinationAmount\":90"))
        #expect(json.contains("\"transactionType\":\"expense\""))
        #expect(Endpoints.loanPayment(loanId: "loan-1", fromAccountId: "acc-2", amount: 1, loanAmount: 1, time: .now).path == "/transactions")
    }

    @Test func noteAndUpdateEndpointsUseLoanRoutes() {
        #expect(Endpoints.loanAddNote(id: "x", text: "hi").path == "/loans/x/events")
        #expect(Endpoints.loanUpdate(id: "x", LoanUpdateRequest(name: "n")).method == .patch)
        #expect(Endpoints.loanDelete(id: "x").method == .delete)
    }

    @Test func linkAndUnlinkPayments() throws {
        let request = LoanLinkPaymentsRequest(transactionIds: ["t1", "t2"])
        let json = try String(decoding: JSONCoding.makeEncoder().encode(request), as: UTF8.self)
        #expect(json == #"{"transactionIds":["t1","t2"]}"#)
        let confirmed = LoanLinkPaymentsRequest(transactionIds: ["t1"], confirmOverpay: true)
        let confirmedJSON = try String(decoding: JSONCoding.makeEncoder().encode(confirmed), as: UTF8.self)
        #expect(confirmedJSON.contains("\"confirmOverpay\":true"))

        let linkBody = "{\"loan\":\(Self.loanJSON),\"linkedCount\":2}"
        let linked = try Endpoints.loanLinkPayments(id: "acc-1", request).decodeBody(Self.envelope(linkBody), JSONCoding.makeDecoder())
        #expect(linked.linkedCount == 2)
        #expect(linked.loan.id == "acc-1")

        let unlinkBody = "{\"loan\":\(Self.loanJSON),\"restoredTransactionId\":\"t9\"}"
        let endpoint = Endpoints.loanUnlinkPayment(id: "acc-1", transactionId: "t1")
        let unlinked = try endpoint.decodeBody(Self.envelope(unlinkBody), JSONCoding.makeDecoder())
        #expect(unlinked.restoredTransactionId == "t9")
        #expect(endpoint.path == "/loans/acc-1/unlink-payment")
    }

    @Test func minimumPaymentMatchesAmortizationFormula() {
        #expect(LoanMath.minimumPayment(principal: 12000, interestRate: 0, termMonths: 12) == 1000)
        #expect(LoanMath.minimumPayment(principal: 20000, interestRate: Decimal(string: "6.5")!, termMonths: 60) == Decimal(string: "391.32"))
        #expect(LoanMath.minimumPayment(principal: 1000, interestRate: 5, termMonths: nil) == nil)
    }

    @Test func payoffScenarioZeroRateAndStalled() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let zero = LoanMath.payoffScenario(balance: 1000, interestRate: 0, payment: 250, today: today)
        #expect(zero.paysOff)
        #expect(zero.monthsRemaining == 4)
        #expect(zero.totalInterest == 0)
        #expect(zero.points.last?.balance == 0)
        #expect(zero.points.count == 5)

        let stalled = LoanMath.payoffScenario(balance: 10000, interestRate: 12, payment: 100, today: today)
        #expect(!stalled.paysOff)
        #expect(stalled.monthsRemaining == nil)

        let settled = LoanMath.payoffScenario(balance: 0, interestRate: 5, payment: 100, today: today)
        #expect(settled.paysOff)
        #expect(settled.monthsRemaining == 0)
    }

    @Test func payoffScenarioAccruesInterest() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let scenario = LoanMath.payoffScenario(balance: 1000, interestRate: 12, payment: 100, today: today)
        #expect(scenario.paysOff)
        #expect(scenario.monthsRemaining == 11)
        #expect((scenario.totalInterest ?? 0) > 0)
    }

    @Test func costSplitWithAndWithoutInterest() {
        let split = LoanMath.costSplit(principal: 1000, estimatedInterest: 250)
        #expect(split.total == 1250)
        #expect(split.hasInterest)
        #expect(split.interestPerUnitCents == 25)
        #expect(abs(split.interestPercent - 20) < 0.0001)

        let none = LoanMath.costSplit(principal: 1000, estimatedInterest: nil)
        #expect(!none.hasInterest)
        #expect(none.principalPercent == 100)
        #expect(none.interestPerUnitCents == nil)
    }

    @Test func partitionAndAggregate() throws {
        let decoder = JSONCoding.makeDecoder()
        let active = try decoder.decode(Loan.self, from: Data(Self.loanJSON.utf8))
        let archived = try decoder.decode(
            Loan.self,
            from: Data(Self.loanJSON.replacingOccurrences(of: "\"status\": \"active\"", with: "\"status\": \"archived\"")
                .replacingOccurrences(of: "\"id\": \"acc-1\"", with: "\"id\": \"acc-2\"").utf8)
        )
        let partition = LoanMath.partition([active, archived])
        #expect(partition.active.map(\.id) == ["acc-1"])
        #expect(partition.archived.map(\.id) == ["acc-2"])

        let aggregate = LoanMath.aggregate(partition.tracked)
        #expect(aggregate.totalOutstanding == Decimal(string: "12000.5"))
        #expect(aggregate.monthlyObligation == 450)
        #expect(aggregate.debtFreeDate == CalendarDate(year: 2027, month: 6, day: 15))
        #expect(abs((aggregate.weightedAPR ?? 0) - 6.5) < 0.0001)
        #expect(abs((aggregate.principalRepaidPercent ?? 0) - 39.9975) < 0.001)
        #expect(aggregate.interestRemaining == Decimal(string: "1100.25"))
    }

    @Test func actualBalanceSeriesCarriesForwardAndEndsAtZero() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let start = CalendarDate(year: 2024, month: 1, day: 1).startDate(in: calendar)
        let end = CalendarDate(year: 2024, month: 4, day: 1).startDate(in: calendar)
        let history = [
            LoanBalancePoint(date: CalendarDate(year: 2024, month: 1, day: 20), amount: -800),
            LoanBalancePoint(date: CalendarDate(year: 2024, month: 3, day: 1), amount: -300),
        ]
        let series = LoanMath.actualBalanceSeries(history: history, startDate: start, closedDate: end, openingBalance: 1000, calendar: calendar)
        #expect(series.map(\.balance) == [1000, 800, 300, 0])
        #expect(LoanMath.monthsEarly(startDate: start, termMonths: 12, closedDate: end, calendar: calendar) == 9)
    }
}
