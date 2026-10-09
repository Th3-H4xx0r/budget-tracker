import MoneyMatterKit
import SwiftUI

/// Picks existing expense transactions (since the loan started) and links them to the loan
/// as payments. The server asks for confirmation when the total would overpay the loan.
struct LoanLinkPaymentsSheet: View {
    let loan: Loan
    let onLinked: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var transactions: [Transaction]?
    @State private var loadError: APIError?
    @State private var selection = Set<String>()
    @State private var isLinking = false
    @State private var isConfirmingOverpay = false
    @State private var overpayMessage = ""
    @State private var alert: ErrorAlert?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Link Payments")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isLinking {
                            ProgressView()
                        } else {
                            Button("Link (\(selection.count))") { Task { await link(confirmOverpay: false) } }
                                .disabled(selection.isEmpty)
                        }
                    }
                }
                .errorAlert($alert)
                .confirmationDialog("Overpay this loan?", isPresented: $isConfirmingOverpay, titleVisibility: .visible) {
                    Button("Link Anyway") { Task { await link(confirmOverpay: true) } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(overpayMessage)
                }
                .task {
                    if transactions == nil { await load() }
                }
        }
    }

    @ViewBuilder private var content: some View {
        if let transactions {
            if transactions.isEmpty {
                ContentUnavailableView {
                    Label("No Expenses to Link", systemImage: "link")
                } description: {
                    Text("Expenses recorded since the loan started will appear here.")
                } actions: {
                    Button("Refresh") { Task { await load() } }
                }
            } else {
                List(transactions, selection: $selection) { transaction in
                    ResolvedTransactionRow(transaction: transaction, showsDate: true)
                        .tag(transaction.id)
                }
                .environment(\.editMode, .constant(.active))
                .safeAreaInset(edge: .top) {
                    if let anchor = loan.loanDetails.balanceAnchorDate {
                        Text("Payments before \(anchor.startDate().formatted(date: .abbreviated, time: .omitted)) are kept as history and don't lower the balance.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.bar)
                    }
                }
            }
        } else if let loadError {
            LoadFailedView(error: loadError) { await load() }
        } else {
            List { TransactionRowsPlaceholder(count: 6) }
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        var query = TransactionListQuery(limit: 100)
        query.transactionType = .expense
        query.transferFilter = .exclude
        query.from = loan.loanDetails.startDate.startDate()
        query.order = .descending
        do {
            transactions = try await client.send(Endpoints.transactions(query))
            loadError = nil
        } catch {
            if transactions == nil { loadError = APIError(error) }
        }
    }

    private func link(confirmOverpay: Bool) async {
        guard let client = services.client, !selection.isEmpty else { return }
        isLinking = true
        defer { isLinking = false }
        do {
            _ = try await client.send(Endpoints.loanLinkPayments(
                id: loan.id,
                LoanLinkPaymentsRequest(transactionIds: Array(selection), confirmOverpay: confirmOverpay ? true : nil)
            ))
            onLinked()
            dismiss()
        } catch {
            let apiError = APIError(error)
            if case .validation(let message, _, let code) = apiError, code == Endpoints.loanOverpayConfirmationCode {
                overpayMessage = message.isEmpty
                    ? String(localized: "These payments add up to more than the loan's outstanding balance.")
                    : message
                isConfirmingOverpay = true
            } else {
                alert = ErrorAlert(error)
            }
        }
    }
}
