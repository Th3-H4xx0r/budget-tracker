import MoneyMatterKit
import SwiftUI

/// Refund and transfer links on the detail screen: what this row refunds, what refunds it,
/// linking two rows as a transfer, and unlinking either kind.
struct TransactionLinksSection: View {
    let transaction: Transaction
    var canEdit = true

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var refunds: LoadState<[TransactionRefundLink]> = .idle
    @State private var isWorking = false
    @State private var pendingRefundUnlink: TransactionRefundLink?
    @State private var isConfirmingTransferUnlink = false
    @State private var errorAlert: ErrorAlert?

    /// Only transfers between the user's own accounts can be unlinked; loan payments keep their link.
    private var isTwoLegTransfer: Bool { transaction.transferNature == .betweenUserAccounts }

    var body: some View {
        Group {
            if !transaction.isTransfer, !transaction.isPlanned {
                refundSection
            }
            if canEdit, !transaction.isPlanned, transaction.transferNature == .notTransfer || isTwoLegTransfer {
                transferSection
            }
        }
        .task(id: "\(transaction.id)-\(transaction.refundLinked)") { await loadRefunds() }
        .confirmationDialog(
            "Remove this refund link?",
            isPresented: Binding(get: { pendingRefundUnlink != nil }, set: { if !$0 { pendingRefundUnlink = nil } }),
            titleVisibility: .visible,
            presenting: pendingRefundUnlink
        ) { link in
            Button("Remove Link", role: .destructive) {
                Task { await unlinkRefund(link) }
            }
        } message: { _ in
            Text("Both transactions stay; they're just no longer linked.")
        }
        .confirmationDialog("Unlink this transfer?", isPresented: $isConfirmingTransferUnlink, titleVisibility: .visible) {
            Button("Unlink Transfer", role: .destructive) {
                Task { await unlinkTransfer() }
            }
        } message: {
            Text("The two sides become separate income and expense transactions.")
        }
        .errorAlert($errorAlert)
    }

    // MARK: Refunds

    private var originalLinks: [TransactionRefundLink] {
        (refunds.value ?? []).filter { $0.refundTxId == transaction.id }
    }

    private var refundedByLinks: [TransactionRefundLink] {
        (refunds.value ?? []).filter { $0.originalTxId == transaction.id }
    }

    @ViewBuilder
    private var refundSection: some View {
        Section("Refunds") {
            switch refunds {
            case .idle, .loading:
                if transaction.refundLinked {
                    Text("Loading refunds")
                        .redacted(reason: .placeholder)
                }
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await loadRefunds() }
            case .loaded:
                ForEach(originalLinks) { link in
                    linkRow(title: "Refund of", other: link.originalTransaction, link: link)
                }
                ForEach(refundedByLinks) { link in
                    linkRow(title: "Refunded by", other: link.refundTransaction, link: link)
                }
            }
            if canEdit {
                if originalLinks.isEmpty, refundedByLinks.isEmpty {
                    NavigationLink {
                        TransactionPickScreen(purpose: .refundOriginal(
                            transactionId: transaction.id,
                            type: transaction.transactionType,
                            amount: transaction.amount,
                            accountId: transaction.accountId
                        )) { original in
                            Task { await linkRefund(originalId: original.id, refundId: transaction.id) }
                        }
                    } label: {
                        Label("Mark as Refund Of…", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(isWorking)
                }
                if originalLinks.isEmpty {
                    NavigationLink {
                        TransactionPickScreen(purpose: .refundFor(transaction)) { refund in
                            Task { await linkRefund(originalId: transaction.id, refundId: refund.id) }
                        }
                    } label: {
                        Label("Add Refund…", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(isWorking)
                }
            }
        }
    }

    private func linkRow(title: LocalizedStringKey, other: Transaction?, link: TransactionRefundLink) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let other {
                NavigationLink {
                    TransactionDetailScreen(transactionID: other.id, initial: other)
                } label: {
                    ResolvedTransactionRow(transaction: other, showsDate: true)
                }
            } else {
                Text("A transaction that isn't tracked")
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEdit {
                Button("Unlink", systemImage: "link.badge.minus", role: .destructive) {
                    pendingRefundUnlink = link
                }
            }
        }
        .contextMenu {
            if canEdit {
                Button("Remove Link", systemImage: "link.badge.minus", role: .destructive) {
                    pendingRefundUnlink = link
                }
            }
        }
    }

    // MARK: Transfers

    @ViewBuilder
    private var transferSection: some View {
        Section {
            if isTwoLegTransfer {
                Button("Unlink Transfer", systemImage: "link.badge.minus", role: .destructive) {
                    isConfirmingTransferUnlink = true
                }
                .disabled(isWorking)
            } else {
                NavigationLink {
                    TransactionPickScreen(purpose: .transferCounterpart(transaction)) { other in
                        Task { await linkTransfer(with: other) }
                    }
                } label: {
                    Label("Link as Transfer…", systemImage: "link")
                }
                .disabled(isWorking)
            }
        } footer: {
            if !isTwoLegTransfer {
                Text("Pair this transaction with the matching one on another account to record a transfer.")
            }
        }
    }

    // MARK: Actions

    private func loadRefunds() async {
        guard let client = services.client, !transaction.isTransfer else { return }
        if refunds.value == nil { refunds = .loading }
        do {
            refunds = .loaded(try await client.send(Endpoints.transactionRefunds(transactionId: transaction.id)))
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if refunds.value == nil { refunds = .failed(apiError) }
        }
    }

    private func linkRefund(originalId: String, refundId: String) async {
        await perform {
            _ = try await $0.send(Endpoints.linkRefund(TransactionRefundLinkRequest(originalTxId: originalId, refundTxId: refundId)))
            await loadRefunds()
        }
    }

    private func unlinkRefund(_ link: TransactionRefundLink) async {
        await perform {
            _ = try await $0.send(Endpoints.unlinkRefund(TransactionRefundLinkRequest(
                originalTxId: link.originalTxId ?? "",
                refundTxId: link.refundTxId
            )))
            refunds = .loaded((refunds.value ?? []).filter { $0.id != link.id })
        }
    }

    private func linkTransfer(with other: Transaction) async {
        await perform {
            _ = try await $0.send(Endpoints.linkTransfer(TransactionLinkRequest(
                baseTransactionId: transaction.id,
                oppositeTransactionId: other.id
            )))
        }
    }

    private func unlinkTransfer() async {
        guard let transferId = transaction.transferId else { return }
        await perform {
            _ = try await $0.send(Endpoints.unlinkTransfer(TransactionUnlinkRequest(transferIds: [transferId])))
        }
    }

    private func perform(_ action: (APIClient) async throws -> Void) async {
        guard let client = services.client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await action(client)
            TransactionChangeFeed.shared.publish(.invalidated)
            await referenceData.refreshAccounts()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}
