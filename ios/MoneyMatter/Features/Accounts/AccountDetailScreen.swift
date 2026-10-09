import MoneyMatterKit
import SwiftUI

/// Account detail, pushed from any tab: the balance header and the account's transactions,
/// with Edit, Archive/Unarchive, and Delete.
struct AccountDetailScreen: View {
    let accountID: String

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model: TransactionListModel
    @State private var isEditPresented = false
    @State private var isAddTransactionPresented = false
    @State private var isSharePresented = false
    @State private var pendingDeleteCount: Int?
    @State private var isWorking = false
    @State private var errorAlert: ErrorAlert?

    init(accountID: String) {
        self.accountID = accountID
        _model = State(initialValue: TransactionListModel(scopeAccountIds: [accountID]))
    }

    private var account: Account? {
        referenceData.account(id: accountID)
    }

    var body: some View {
        Group {
            if let account {
                TransactionListView(
                    model: model,
                    emptyTitle: "No Transactions",
                    emptyDescription: "Transactions on this account appear here."
                ) {
                    Section {
                        header(account)
                    }
                    if let connectionID = account.bankDataProviderConnectionId {
                        bankConnectionSection(account, connectionID: connectionID)
                    }
                }
                .toolbar { toolbar(account) }
            } else if referenceData.hasLoaded {
                ContentUnavailableView(
                    "Account Not Found",
                    systemImage: "wallet.bifold",
                    description: Text("It may have been deleted.")
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(account?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditPresented) {
            if let account {
                AccountFormSheet(mode: .edit(account))
            }
        }
        .sheet(isPresented: $isSharePresented) {
            ShareResourceSheet(resourceType: .account, resourceID: accountID)
        }
        .sheet(isPresented: $isAddTransactionPresented) {
            TransactionEditorSheet(mode: .create(accountId: accountID))
        }
        .confirmationDialog(
            "Delete \(account?.name ?? "")?",
            isPresented: Binding(get: { pendingDeleteCount != nil }, set: { if !$0 { pendingDeleteCount = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeleteCount
        ) { _ in
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: { count in
            Text("This also deletes its \(count) transactions. This can't be undone.")
        }
        .errorAlert($errorAlert)
    }

    private func header(_ account: Account) -> some View {
        VStack(spacing: 8) {
            InitialsBadge(AccountInitials.text(for: account), colorHex: account.logoColor, size: 52)
            Text("Current Balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AmountText(account.currentBalance, currencyCode: account.currencyCode, digits: referenceData.digits(for: account.currencyCode))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let base = session.baseCurrency?.currencyCode, base != account.currencyCode {
                AmountText(account.refCurrentBalance, currencyCode: base, digits: referenceData.digits(for: base))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if account.accountCategory == .creditCard, account.creditLimit > 0 {
                HStack(spacing: 4) {
                    Text("Credit Limit")
                    AmountText(account.creditLimit, currencyCode: account.currencyCode, digits: referenceData.digits(for: account.currencyCode))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(AccountCategoryLabel.text(for: account.accountCategory))
                if account.isArchived { Text("· Archived") }
                if account.excludeFromStats { Text("· Excluded from stats") }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func bankConnectionSection(_ account: Account, connectionID: String) -> some View {
        Section {
            NavigationLink {
                BankConnectionDetailScreen(connectionID: connectionID)
            } label: {
                if BankSyncMonitor.shared.needsRelink(account) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reconnect Bank")
                            Text("Syncing stopped. Reconnect to resume.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Label("Bank Connection", systemImage: "building.columns")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ account: Account) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if account.isSystem, !account.isArchived {
                Button("Add Transaction", systemImage: "plus") {
                    isAddTransactionPresented = true
                }
            }
            Button("Edit") {
                isEditPresented = true
            }
            Menu {
                if !account.isSharedWithMe || account.share?.permission == "manage" {
                    Button("Share", systemImage: "person.badge.plus") {
                        isSharePresented = true
                    }
                }
                Button(
                    account.isArchived ? "Unarchive" : "Archive",
                    systemImage: account.isArchived ? "archivebox.fill" : "archivebox"
                ) {
                    Task { await toggleArchived(account) }
                }
                Button("Delete Account", systemImage: "trash", role: .destructive) {
                    Task { await prepareDelete() }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .disabled(isWorking)
        }
    }

    private func toggleArchived(_ account: Account) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let updated = try await services.accounts.updateAccount(
                id: account.id,
                AccountUpdateRequest(status: account.isArchived ? .active : .archived)
            )
            referenceData.upsert(updated)
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func prepareDelete() async {
        isWorking = true
        defer { isWorking = false }
        do {
            pendingDeleteCount = try await services.accounts.transactionCount(accountID: accountID)
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.accounts.deleteAccount(id: accountID)
            dismiss()
            referenceData.removeAccount(id: accountID)
            TransactionChangeFeed.shared.publish(.invalidated)
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}
