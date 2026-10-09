import MoneyMatterKit
import SwiftUI

/// Reviews a saved rule's matches among past transactions and applies it to the ones the
/// user picks, matching the web's apply-to-history dialog.
struct OrgAutomationApplySheet: View {
    let rule: OrgAutomation
    let onApplied: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState<OrgAutomationPreview> = .idle
    @State private var selection: Set<String> = []
    @State private var isConfirming = false
    @State private var isApplying = false
    @State private var resultMessage: String?
    @State private var alert: ErrorAlert?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Run on Past Transactions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .disabled(isApplying)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isApplying {
                            ProgressView()
                        } else {
                            Button("Apply") { isConfirming = true }
                                .disabled(selection.isEmpty)
                        }
                    }
                }
                .confirmationDialog(
                    "Apply to \(selection.count) Transactions?",
                    isPresented: $isConfirming,
                    titleVisibility: .visible
                ) {
                    Button("Apply") { Task { await apply() } }
                } message: {
                    Text("The rule's actions change these transactions. Categories you set by hand are kept.")
                }
                .alert(
                    "Rule Applied",
                    isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })
                ) {
                    Button("OK") { dismiss() }
                } message: {
                    Text(resultMessage ?? "")
                }
                .errorAlert($alert)
                .task {
                    if state.value == nil { await load() }
                }
        }
        .interactiveDismissDisabled(isApplying)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            List {
                TransactionRowsPlaceholder(count: 6)
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let preview):
            if preview.matches.isEmpty {
                ContentUnavailableView {
                    Label("No Matches", systemImage: "checkmark.circle")
                } description: {
                    if preview.settledCount > 0 {
                        Text("Every matching transaction already has this rule's changes.")
                    } else {
                        Text("None of your recent transactions match this rule.")
                    }
                } actions: {
                    Button("Close") { dismiss() }
                }
            } else {
                List {
                    Section {
                        Button(selection.count == preview.matches.count ? LocalizedStringKey("Deselect All") : LocalizedStringKey("Select All")) {
                            if selection.count == preview.matches.count {
                                selection = []
                            } else {
                                selection = Set(preview.matches.map(\.id))
                            }
                        }
                    } footer: {
                        Text("\(preview.matchedCount) matching transactions found in the last \(preview.scannedCount).")
                    }
                    Section {
                        ForEach(preview.matches) { transaction in
                            let isSelected = selection.contains(transaction.id)
                            Button {
                                if isSelected {
                                    selection.remove(transaction.id)
                                } else {
                                    selection.insert(transaction.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                        .font(.title3)
                                        .accessibilityHidden(true)
                                    ResolvedTransactionRow(transaction: transaction, showsDate: true)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    } header: {
                        Text("\(selection.count) selected")
                    }
                }
            }
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        state = .loading
        do {
            state = .loaded(try await client.send(
                Endpoints.orgPreviewAutomation(automationId: rule.id, limit: OrgAutomationLimits.maxApplyIds)
            ))
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation { state = .failed(apiError) }
        }
    }

    private func apply() async {
        guard let client = services.client, !selection.isEmpty else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let result = try await client.send(Endpoints.orgApplyAutomation(id: rule.id, transactionIds: Array(selection)))
            await onApplied()
            if result.skippedIds.isEmpty {
                resultMessage = String(localized: "Updated \(result.appliedCount) transactions.")
            } else {
                resultMessage = String(localized: "Updated \(result.appliedCount) transactions. Skipped \(result.skippedIds.count) that no longer match.")
            }
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
