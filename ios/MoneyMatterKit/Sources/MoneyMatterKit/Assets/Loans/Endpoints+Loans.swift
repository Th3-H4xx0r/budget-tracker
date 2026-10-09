import Foundation

extension Endpoints {
    /// `GET /loans`: every loan, active, paid off, and archived.
    public static func loans() -> Endpoint<[Loan]> {
        Endpoint(.get, "/loans")
    }

    /// `GET /loans/:id`.
    public static func loan(id: String) -> Endpoint<Loan> {
        Endpoint(.get, "/loans/\(id)")
    }

    /// `GET /loans/:id/balance-history`: the anchor snapshot, then one point per payment day.
    public static func loanBalanceHistory(id: String) -> Endpoint<[LoanBalancePoint]> {
        Endpoint(.get, "/loans/\(id)/balance-history")
    }

    /// `POST /loans`.
    public static func loanCreate(_ request: LoanCreateRequest) -> Endpoint<Loan> {
        Endpoint(.post, "/loans", body: request)
    }

    /// `PATCH /loans/:id`.
    public static func loanUpdate(id: String, _ request: LoanUpdateRequest) -> Endpoint<Loan> {
        Endpoint(.patch, "/loans/\(id)", body: request)
    }

    /// `DELETE /loans/:id`. Refused while the loan has recorded payments.
    public static func loanDelete(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/loans/\(id)")
    }

    /// `POST /loans/:id/events`: appends a user note to the timeline.
    public static func loanAddNote(id: String, text: String) -> Endpoint<Loan> {
        Endpoint(.post, "/loans/\(id)/events", body: LoanNoteRequest(text: text))
    }

    /// The `422` code `loanLinkPayments` returns when linking would overpay the loan; retry
    /// with `confirmOverpay: true` after the user agrees.
    public static let loanOverpayConfirmationCode = "LOAN_PAYMENT_OVERPAY_CONFIRMATION_REQUIRED"

    /// `POST /loans/:id/link-payments`: turns expense transactions into loan payments.
    public static func loanLinkPayments(id: String, _ request: LoanLinkPaymentsRequest) -> Endpoint<LoanLinkPaymentsResult> {
        Endpoint(.post, "/loans/\(id)/link-payments", body: request)
    }

    /// `POST /loans/:id/unlink-payment`: removes the loan leg and restores the original expense.
    public static func loanUnlinkPayment(id: String, transactionId: String) -> Endpoint<LoanUnlinkPaymentResult> {
        Endpoint(.post, "/loans/\(id)/unlink-payment", body: LoanUnlinkPaymentRequest(transactionId: transactionId))
    }

    /// `POST /transactions`: a payment from `fromAccountId` into the loan, as a
    /// `transfer_to_loan` pair. `loanAmount` is in the loan currency.
    public static func loanPayment(
        loanId: String,
        fromAccountId: String,
        amount: Decimal,
        loanAmount: Decimal,
        time: Date
    ) -> Endpoint<[Transaction]> {
        createTransaction(loanPaymentRequest(
            loanId: loanId,
            fromAccountId: fromAccountId,
            amount: amount,
            loanAmount: loanAmount,
            time: time
        ))
    }

    /// The body `loanPayment` sends.
    public static func loanPaymentRequest(
        loanId: String,
        fromAccountId: String,
        amount: Decimal,
        loanAmount: Decimal,
        time: Date
    ) -> TransactionCreateRequest {
        TransactionCreateRequest(
            amount: amount,
            transactionType: .expense,
            accountId: fromAccountId,
            transferNature: .toLoan,
            paymentType: .creditCard,
            destinationAccountId: loanId,
            destinationAmount: loanAmount,
            time: time
        )
    }
}
