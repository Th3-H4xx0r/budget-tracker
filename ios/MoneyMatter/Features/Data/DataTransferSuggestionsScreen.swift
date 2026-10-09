import MoneyMatterKit
import SwiftUI

/// Scans a period for expense/income pairs that look like one transfer, and links or
/// dismisses each suggested pair.
struct DataTransferSuggestionsScreen: View {
    @Environment(AppServices.self) private var services
    @State private var from = Calendar.current.date(byAdding: .month, value: -2, to: Self.startOfMonth) ?? .now
    @State private var to = Date.now
    @State private var includeOutOfWallet = false
    @State private var state: LoadState<[DataTransferSuggestion]> = .idle
    @State private var total = 0
    @State private var hasMore = false
    @State private var busyPair: String?
    @State private var alert: ErrorAlert?

    private let pageSize = 20

    private static var startOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    }

    var body: some View {
        List {
            Section {
                DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                Toggle("Include out-of-wallet accounts", isOn: $includeOutOfWallet)
            } footer: {
                Text("Matches are incomes on another account within 14 days and 10% of the expense amount.")
            }
            results
        }
        .navigationTitle("Transfer Suggestions")
        .refreshable { await scan() }
        .task(id: ScanKey(from: from, to: to, includeOutOfWallet: includeOutOfWallet)) { await scan() }
        .errorAlert($alert)
    }

    private struct ScanKey: Equatable {
        let from: Date
        let to: Date
        let includeOutOfWallet: Bool
    }

    @ViewBuilder
    private var results: some View {
        switch state {
        case .idle, .loading:
            Section {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Expense placeholder row")
                        Text("Matching income placeholder row")
                    }
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            Section {
                InlineRetryView(ErrorMessage.message(for: error)) { await scan() }
            }
        case .loaded(let suggestions) where suggestions.isEmpty:
            Section {
                ContentUnavailableView {
                    Label("No Suggestions", systemImage: "checkmark.seal")
                } description: {
                    Text("No unlinked transfers found in this period.")
                } actions: {
                    Button("Scan Further Back") {
                        from = Calendar.current.date(byAdding: .month, value: -3, to: from) ?? from
                    }
                    .buttonStyle(.bordered)
                }
            }
        case .loaded(let suggestions):
            Section {
                ForEach(suggestions) { suggestion in
                    suggestionView(suggestion)
                }
                if hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await loadMore() }
                }
            } header: {
                Text("\(total) expenses with possible transfers")
            }
        }
    }

    private func suggestionView(_ suggestion: DataTransferSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ResolvedTransactionRow(transaction: suggestion.expense, showsDate: true)
            ForEach(suggestion.matches) { match in
                let key = suggestion.expense.id + match.id
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("\(match.confidence)% match")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(match.confidence >= 80 ? .green : .secondary)
                    }
                    ResolvedTransactionRow(transaction: match.transaction, showsDate: true)
                    HStack {
                        Button {
                            Task { await link(suggestion.expense, match.transaction) }
                        } label: {
                            Label("Link as Transfer", systemImage: "link")
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Dismiss") {
                            Task { await dismiss(suggestion.expense, match.transaction) }
                        }
                        .buttonStyle(.bordered)
                        if busyPair == key { ProgressView() }
                    }
                    .controlSize(.small)
                    .disabled(busyPair != nil)
                }
                .padding(.leading, 8)
            }
        }
        .padding(.vertical, 4)
    }

    private func request(offset: Int) -> DataTransferScanRequest {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: from)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: to)) ?? to
        return DataTransferScanRequest(from: start, to: end, limit: pageSize, offset: offset, includeOutOfWallet: includeOutOfWallet)
    }

    private func scan() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            let page = try await client.send(Endpoints.dataTransferScan(request(offset: 0)))
            state = .loaded(page.items)
            total = page.total
            hasMore = page.items.count < page.total
        } catch {
            if !APIError(error).isCancellation { state = .failed(APIError(error)) }
        }
    }

    private func loadMore() async {
        guard let client = services.client, let current = state.value else { return }
        do {
            let page = try await client.send(Endpoints.dataTransferScan(request(offset: current.count)))
            let items = current + page.items
            state = .loaded(items)
            hasMore = !page.items.isEmpty && items.count < page.total
        } catch {
            hasMore = false
        }
    }

    private func link(_ expense: Transaction, _ income: Transaction) async {
        guard let client = services.client else { return }
        busyPair = expense.id + income.id
        defer { busyPair = nil }
        do {
            _ = try await client.send(Endpoints.dataLinkTransfer(expenseId: expense.id, incomeId: income.id))
            await scan()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func dismiss(_ expense: Transaction, _ income: Transaction) async {
        guard let client = services.client else { return }
        busyPair = expense.id + income.id
        defer { busyPair = nil }
        do {
            _ = try await client.send(Endpoints.dataDismissTransfer(expenseId: expense.id, incomeId: income.id))
            await scan()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
