import MoneyMatterKit
import SwiftUI

/// Transaction detail, pushed from any tab: the amount header and every field, with Edit and
/// Delete in the toolbar.
struct TransactionDetailScreen: View {
    let transactionID: String
    /// The row the list already has, shown while the fresh copy loads. Its tags fill in for
    /// `GET /transactions/:id`, which doesn't return them.
    var initial: Transaction?

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState<Transaction?> = .idle
    @State private var editing: Transaction?
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var errorAlert: ErrorAlert?
    /// The status after a review action, shown until the refreshed row arrives.
    @State private var reviewStatusOverride: ReviewStatus?
    @State private var isUpdatingReview = false

    init(transactionID: String, initial: Transaction? = nil) {
        self.transactionID = transactionID
        self.initial = initial
    }

    private var transaction: Transaction? {
        state.value ?? initial
    }

    var body: some View {
        content
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let transaction {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Delete", systemImage: "trash") {
                            isConfirmingDelete = true
                        }
                        .disabled(isDeleting)
                        Button("Edit") {
                            editing = transaction
                        }
                    }
                }
            }
            .task {
                if state.value == nil { await load() }
            }
            .onChange(of: TransactionChangeFeed.shared.latest) { _, event in
                guard let change = event?.change else { return }
                switch change {
                case .deleted(let id, let transferId):
                    if id == transactionID || (transferId != nil && transferId == transaction?.transferId) {
                        dismiss()
                    }
                case .saved, .invalidated:
                    Task { await load() }
                }
            }
            .sheet(item: $editing) { transaction in
                TransactionEditorSheet(mode: .edit(transaction))
            }
            .confirmationDialog("Delete this transaction?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Transaction", role: .destructive) {
                    Task { await delete() }
                }
            } message: {
                Text(transaction?.transferId != nil
                    ? "Both sides of the transfer are deleted. This can't be undone."
                    : "This can't be undone.")
            }
            .errorAlert($errorAlert)
    }

    @ViewBuilder
    private var content: some View {
        if let transaction {
            details(transaction)
        } else {
            switch state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                LoadFailedView(error: error) { await load() }
            case .loaded:
                ContentUnavailableView(
                    "Transaction Not Found",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("It may have been deleted.")
                )
            }
        }
    }

    private func details(_ transaction: Transaction) -> some View {
        let category = referenceData.category(id: transaction.categoryId)
        let account = referenceData.account(id: transaction.accountId)
        let payee = referenceData.payee(id: transaction.payeeId)
        let tags = transaction.tags ?? initial?.tags ?? []
        return List {
            Section {
                VStack(spacing: 10) {
                    CategoryIcon(category: category, isTransfer: transaction.isTransfer, size: 56)
                    AmountText(transaction: transaction, digits: referenceData.digits(for: transaction.currencyCode))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(payee?.name ?? category?.name ?? (transaction.isTransfer ? String(localized: "Transfer") : String(localized: "Transaction")))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if transaction.isFraud {
                        FraudBadge()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                LabeledContent("Account", value: account?.name ?? "—")
                if transaction.isTransfer {
                    LabeledContent("Type", value: transferTitle(transaction.transferNature))
                } else {
                    LabeledContent("Category") {
                        HStack(spacing: 8) {
                            CategoryIcon(category: category, size: 22)
                            Text(category?.name ?? "—")
                        }
                    }
                }
                LabeledContent("Date", value: transaction.time.formatted(date: .long, time: .shortened))
                if let payee {
                    LabeledContent("Payee", value: payee.name)
                }
                if !tags.isEmpty {
                    LabeledContent("Tags", value: tags.map(\.name).formatted(.list(type: .and)))
                }
                if let refCode = transaction.refCurrencyCode, refCode != transaction.currencyCode {
                    LabeledContent("In \(refCode)") {
                        AmountText(transaction.signedRefAmount, currencyCode: refCode, digits: referenceData.digits(for: refCode))
                    }
                }
            }

            reviewSection(transaction)

            if let note = transaction.note, !note.isEmpty {
                Section("Note") {
                    Text(note)
                        .textSelection(.enabled)
                }
            }
        }
        .refreshable { await load() }
    }

    private func transferTitle(_ nature: TransferNature) -> String {
        switch nature {
        case .outOfWallet: String(localized: "Transfer out of wallet")
        case .toPortfolio: String(localized: "Transfer to portfolio")
        case .toVenture: String(localized: "Transfer to venture")
        case .toLoan: String(localized: "Transfer to loan")
        case .betweenUserAccounts, .notTransfer, .unknown: String(localized: "Transfer between accounts")
        }
    }

    private func reviewSection(_ transaction: Transaction) -> some View {
        let status = reviewStatusOverride ?? transaction.reviewStatus
        return Section("Review") {
            LabeledContent("Status") {
                Text(reviewTitle(status))
                    .foregroundStyle(status == .fraud ? .red : .secondary)
            }
            ForEach(reviewActions(for: status), id: \.action) { item in
                Button(item.title, role: item.action == .fraud ? .destructive : nil) {
                    Task { await updateReview(transaction, action: item.action) }
                }
                .disabled(isUpdatingReview)
            }
        }
    }

    private func reviewActions(for status: ReviewStatus) -> [(title: LocalizedStringKey, action: ReviewAction)] {
        switch status {
        case .unreviewed: [("Looks Good", .reviewed), ("Fraud", .fraud)]
        case .reviewed: [("Mark as Fraud", .fraud), ("Move to Unreviewed", .unreviewed)]
        case .fraud: [("Not Fraud", .reviewed), ("Move to Unreviewed", .unreviewed)]
        case .notRequired, .unknown: [("Mark as Fraud", .fraud)]
        }
    }

    private func updateReview(_ transaction: Transaction, action: ReviewAction) async {
        isUpdatingReview = true
        defer { isUpdatingReview = false }
        do {
            _ = try await services.review.updateReviewStatus(transactionIds: [transaction.id], action: action)
            switch action {
            case .reviewed: reviewStatusOverride = .reviewed
            case .fraud: reviewStatusOverride = .fraud
            case .unreviewed, .checkLater: reviewStatusOverride = .unreviewed
            }
            NotificationCenter.default.post(name: .reviewStatusesDidChange, object: nil)
            if let fresh = try? await services.transactions.transaction(id: transaction.id) {
                state = .loaded(fresh)
                reviewStatusOverride = nil
                TransactionChangeFeed.shared.publish(.saved([fresh]))
            }
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func reviewTitle(_ status: ReviewStatus) -> String {
        switch status {
        case .unreviewed: String(localized: "Unreviewed")
        case .reviewed: String(localized: "Reviewed")
        case .fraud: String(localized: "Fraud")
        case .notRequired, .unknown: String(localized: "Not required")
        }
    }

    private func load() async {
        if state.value == nil, initial == nil { state = .loading }
        do {
            state = .loaded(try await services.transactions.transaction(id: transactionID))
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if state.value == nil { state = .failed(apiError) }
        }
    }

    private func delete() async {
        guard let transaction else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await services.transactions.deleteTransaction(id: transaction.id)
            TransactionChangeFeed.shared.publish(.deleted(id: transaction.id, transferId: transaction.transferId))
            await referenceData.refreshAccounts()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}
