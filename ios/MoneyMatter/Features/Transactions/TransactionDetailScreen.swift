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

    /// The entity name for the inline title: payee, else category, else the kind.
    private var screenTitle: String {
        guard let transaction else { return String(localized: "Transaction") }
        if let payee = referenceData.payee(id: transaction.payeeId) { return payee.name }
        if let category = referenceData.category(id: transaction.categoryId) { return category.name }
        return transaction.isTransfer ? String(localized: "Transfer") : String(localized: "Transaction")
    }

    var body: some View {
        content
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let transaction {
                    ToolbarItem(placement: .topBarTrailing) {
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
                List {
                    Section {
                        HeroValueHeader("$000.00", status: "Placeholder date")
                            .padding(.vertical, 6)
                    }
                    Section {
                        StatGrid(columns: 2) {
                            StatCell(label: "Account", value: "Placeholder")
                            StatCell(label: "Category", value: "Placeholder")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .redactedWhileLoading(true)
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
            heroSection(transaction, category: category)

            Section("Details") {
                StatGrid(columns: 2) {
                    StatCell(label: String(localized: "Account"), value: account?.name ?? "—")
                    if transaction.isTransfer {
                        StatCell(label: String(localized: "Type"), value: transferTitle(transaction.transferNature))
                    } else {
                        StatCell(label: String(localized: "Category"), value: category?.name ?? "—")
                    }
                    StatCell(
                        label: String(localized: "Date"),
                        value: transaction.time.formatted(date: .abbreviated, time: .omitted),
                        footnote: transaction.time.formatted(date: .omitted, time: .shortened)
                    )
                    StatCell(label: String(localized: "Payee"), value: payee?.name ?? "—")
                    if !transaction.isTransfer, transaction.paymentType != .unknown {
                        StatCell(label: String(localized: "Payment type"), value: TransactionPaymentTypeLabel.title(transaction.paymentType))
                    }
                    if let original = transaction.originalAmount, let code = transaction.originalCurrencyCode {
                        StatCell(
                            label: String(localized: "Original amount"),
                            value: MoneyFormat.string(original, currencyCode: code, digits: referenceData.digits(for: code))
                        )
                    }
                    if let refCode = transaction.refCurrencyCode, refCode != transaction.currencyCode {
                        StatCell(
                            label: String(localized: "In \(refCode)"),
                            value: MoneyFormat.string(transaction.signedRefAmount, currencyCode: refCode, digits: referenceData.digits(for: refCode))
                        )
                    }
                }
                .padding(.vertical, DS.Space.xs)
                if !tags.isEmpty {
                    LabeledContent("Tags", value: tags.map(\.name).formatted(.list(type: .and)))
                }
            }

            if let splits = transaction.splits, !splits.isEmpty {
                splitsSection(transaction, splits: splits)
            }

            if let note = transaction.note, !note.isEmpty {
                Section("Note") {
                    Text(note)
                        .textSelection(.enabled)
                }
            }

            TransactionLinksSection(transaction: transaction, canEdit: transaction.canEdit ?? true)

            TransactionAttachmentsSection(transactionId: transaction.id, canEdit: transaction.canEdit ?? true)

            if let location = transaction.location {
                Section("Location") {
                    TransactionLocationPreview(location: location)
                        .listRowInsets(EdgeInsets())
                }
            }

            reviewSection(transaction)

            Section {
                InlineActionRow(String(localized: "Edit transaction"), systemImage: "pencil") {
                    editing = transaction
                }
                InlineActionRow(String(localized: "Delete transaction"), systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .disabled(isDeleting)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    /// The signed amount at hero size (income green, expense primary with a minus), with the
    /// date and any planned or fraud badge as its status line.
    private func heroSection(_ transaction: Transaction, category: Category?) -> some View {
        let style = AmountStyle(transaction)
        let digits = referenceData.digits(for: transaction.currencyCode)
        let shown: Decimal = switch style {
        case .expense: -abs(transaction.signedAmount)
        case .income: abs(transaction.signedAmount)
        case .transfer, .neutral: transaction.signedAmount
        }
        return Section {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                CategoryIconTile(category: category, isTransfer: transaction.isTransfer, size: 44)
                HeroValueHeader(MoneyFormat.string(shown, currencyCode: transaction.currencyCode, digits: digits)) {
                    HStack(spacing: DS.Space.s) {
                        Text(transaction.time.formatted(date: .long, time: .shortened))
                            .monospacedDigit()
                        if transaction.isPlanned {
                            StatusBadge(label: String(localized: "Planned"), color: DS.Palette.warning)
                        }
                        if transaction.isFraud {
                            FraudBadge()
                        }
                    }
                }
                .foregroundStyle(style.color)
            }
            .padding(.vertical, 6)
        }
    }

    private func splitsSection(_ transaction: Transaction, splits: [TransactionSplit]) -> some View {
        let digits = referenceData.digits(for: transaction.currencyCode)
        let remaining = transaction.amount - splits.reduce(0) { $0 + $1.amount }
        return Section("Splits") {
            ForEach(splits) { split in
                let category = referenceData.category(id: split.categoryId)
                EntityRow(category?.name ?? "—", subtitle: split.note) {
                    CategoryIconTile(category: category)
                } trailing: {
                    EntityRowValue(MoneyFormat.string(split.amount, currencyCode: transaction.currencyCode, digits: digits))
                }
            }
            LabeledContent("On \(referenceData.category(id: transaction.categoryId)?.name ?? String(localized: "main category"))") {
                AmountText(remaining, currencyCode: transaction.currencyCode, digits: digits)
            }
        }
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
                StatusBadge(label: reviewTitle(status), color: reviewColor(status))
            }
            ForEach(reviewActions(for: status), id: \.action) { item in
                InlineActionRow(
                    item.title,
                    systemImage: reviewSymbol(item.action),
                    role: item.action == .fraud ? .destructive : nil
                ) {
                    Task { await updateReview(transaction, action: item.action) }
                }
                .disabled(isUpdatingReview)
            }
        }
    }

    private func reviewColor(_ status: ReviewStatus) -> Color {
        switch status {
        case .unreviewed: DS.Palette.warning
        case .reviewed: DS.Palette.success
        case .fraud: DS.Palette.danger
        case .notRequired, .unknown: .gray
        }
    }

    private func reviewSymbol(_ action: ReviewAction) -> String {
        switch action {
        case .reviewed: "checkmark.shield"
        case .fraud: "exclamationmark.shield"
        case .unreviewed, .checkLater: "arrow.uturn.backward"
        }
    }

    private func reviewActions(for status: ReviewStatus) -> [(title: String, action: ReviewAction)] {
        switch status {
        case .unreviewed: [(String(localized: "Looks good"), .reviewed), (String(localized: "Fraud"), .fraud)]
        case .reviewed: [(String(localized: "Mark as fraud"), .fraud), (String(localized: "Move to unreviewed"), .unreviewed)]
        case .fraud: [(String(localized: "Not fraud"), .reviewed), (String(localized: "Move to unreviewed"), .unreviewed)]
        case .notRequired, .unknown: [(String(localized: "Mark as fraud"), .fraud)]
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
            if let client = services.client {
                state = .loaded(try await client.send(Endpoints.transactionWithSplits(id: transactionID)))
            } else {
                state = .loaded(try await services.transactions.transaction(id: transactionID))
            }
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
