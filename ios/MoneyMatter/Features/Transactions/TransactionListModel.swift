import Foundation
import MoneyMatterKit
import Observation

/// What the filter sheet can narrow the transaction list by.
struct TransactionFilter: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case all
        case expense
        case income
        case transfer

        var id: Self { self }

        var title: String {
            switch self {
            case .all: String(localized: "All")
            case .expense: String(localized: "Expense")
            case .income: String(localized: "Income")
            case .transfer: String(localized: "Transfer")
            }
        }
    }

    var kind: Kind = .all
    var accountIds: Set<String> = []
    var categoryIds: Set<String> = []
    var limitsDates = false
    var from: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    var to: Date = .now

    var activeCount: Int {
        [kind != .all, !accountIds.isEmpty, !categoryIds.isEmpty, limitsDates].filter(\.self).count
    }

    func apply(to query: inout TransactionListQuery) {
        switch kind {
        case .all:
            break
        case .expense:
            query.transactionType = .expense
            query.transferFilter = .exclude
        case .income:
            query.transactionType = .income
            query.transferFilter = .exclude
        case .transfer:
            query.transferFilter = .only
        }
        query.accountIds = accountIds.sorted()
        query.categoryIds = categoryIds.sorted()
        if limitsDates {
            let calendar = Calendar.current
            query.from = calendar.startOfDay(for: from)
            // Exclusive: the start of the day after the last selected day.
            let endDay = calendar.startOfDay(for: max(from, to))
            query.to = calendar.date(byAdding: .day, value: 1, to: endDay)
        }
    }
}

/// A transaction write that open lists and detail screens should reflect.
enum TransactionChange: Equatable {
    /// Rows returned by a create or update: one row, or both legs of a transfer.
    case saved([Transaction])
    /// Deleting either leg of a transfer deletes both, so the transfer id is carried along.
    case deleted(id: String, transferId: String?)
    /// Something changed that a local patch can't express, e.g. an account was deleted.
    case invalidated
}

/// Broadcasts transaction writes across tabs, so a save in one sheet updates every list.
@Observable
final class TransactionChangeFeed {
    struct Event: Equatable {
        let id = UUID()
        let change: TransactionChange
    }

    static let shared = TransactionChangeFeed()

    private(set) var latest: Event?

    func publish(_ change: TransactionChange) {
        latest = Event(change: change)
    }
}

/// One day of transactions, newest first.
struct TransactionDay: Identifiable {
    let id: Date
    var transactions: [Transaction]
}

/// A paginated, filterable transaction list. Shared by the Transactions tab and account
/// detail, which fixes `scopeAccountIds` to its account.
@Observable
final class TransactionListModel {
    static let pageSize = 50

    /// Fixed account scope, e.g. on account detail. Overrides the filter's accounts.
    let scopeAccountIds: [String]
    /// Change with `update(filter:searchText:using:)`, which reloads atomically.
    private(set) var filter = TransactionFilter()
    /// Applied search text; sent as `noteSearch`.
    private(set) var searchText = ""

    private(set) var transactions: [Transaction] = []
    /// Pending plans (`isPlanned`), soonest first, shown above the list on the unscoped,
    /// unfiltered list.
    private(set) var planned: [Transaction] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var hasLoaded = false
    /// A failed first page. Rows already shown stay when a refresh fails.
    private(set) var error: APIError?
    /// A failed next page; the loaded rows stay.
    private(set) var pageError: APIError?
    /// Bumps after every page request settles, so a still-visible pagination row fires again.
    private(set) var pageLoads = 0

    @ObservationIgnored private var generation = 0
    /// Rows the server has returned for the current query. Local patches don't move it,
    /// except removing a loaded row, which shifts the server's later rows up by one.
    @ObservationIgnored private var serverOffset = 0

    init(scopeAccountIds: [String] = []) {
        self.scopeAccountIds = scopeAccountIds
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let plannedLimit = 20

    /// Plans get their own section on the main list, without filters or search.
    var showsPlannedSection: Bool {
        scopeAccountIds.isEmpty && filter.activeCount == 0 && !isSearching
    }

    var days: [TransactionDay] {
        let calendar = Calendar.current
        var result: [TransactionDay] = []
        // Rows in the Planned section aren't repeated below, so every row id is unique.
        let plannedIds = showsPlannedSection ? Set(planned.map(\.id)) : []
        for transaction in transactions where !plannedIds.contains(transaction.id) {
            let day = calendar.startOfDay(for: transaction.time)
            if result.last?.id == day {
                result[result.count - 1].transactions.append(transaction)
            } else {
                result.append(TransactionDay(id: day, transactions: [transaction]))
            }
        }
        return result
    }

    private func makeQuery(offset: Int) -> TransactionListQuery {
        var query = TransactionListQuery(limit: Self.pageSize, offset: offset)
        query.sortBy = .time
        query.order = .descending
        query.includeTags = true
        filter.apply(to: &query)
        if !scopeAccountIds.isEmpty {
            query.accountIds = scopeAccountIds
        }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            query.noteSearch = [term]
        }
        return query
    }

    /// Sets the filter and/or search and reloads. The generation bump happens in the same
    /// main-actor turn as the change, so an in-flight `loadMore` can't append to the new list.
    func update(filter: TransactionFilter? = nil, searchText: String? = nil, using service: any TransactionsServicing) async {
        if let filter { self.filter = filter }
        if let searchText { self.searchText = searchText }
        await reload(using: service)
    }

    func reload(using service: any TransactionsServicing) async {
        generation += 1
        let current = generation
        isLoading = true
        isLoadingMore = false
        defer {
            if current == generation {
                isLoading = false
                pageLoads += 1
            }
        }
        do {
            let page = try await service.transactions(makeQuery(offset: 0))
            let plans = await loadPlanned(using: service)
            guard current == generation else { return }
            planned = plans
            transactions = page
            serverOffset = page.count
            hasMore = page.count >= Self.pageSize
            error = nil
            pageError = nil
            hasLoaded = true
        } catch {
            let apiError = APIError(error)
            guard current == generation, !apiError.isCancellation else { return }
            self.error = apiError
        }
    }

    /// Plans for the Planned section; empty when the section is hidden or the request fails,
    /// since the main list still shows every plan.
    private func loadPlanned(using service: any TransactionsServicing) async -> [Transaction] {
        guard showsPlannedSection else { return [] }
        var query = TransactionListQuery(limit: Self.plannedLimit, offset: 0)
        query.sortBy = .time
        query.order = .ascending
        query.includeTags = true
        query.isPlanned = true
        return (try? await service.transactions(query)) ?? []
    }

    func loadMore(using service: any TransactionsServicing) async {
        guard hasMore, hasLoaded, !isLoading, !isLoadingMore else { return }
        let current = generation
        isLoadingMore = true
        defer {
            if current == generation {
                isLoadingMore = false
                pageLoads += 1
            }
        }
        do {
            let page = try await service.transactions(makeQuery(offset: serverOffset))
            guard current == generation else { return }
            serverOffset += page.count
            let known = Set(transactions.map(\.id))
            transactions += page.filter { !known.contains($0.id) }
            hasMore = page.count >= Self.pageSize
            pageError = nil
        } catch {
            let apiError = APIError(error)
            guard current == generation, !apiError.isCancellation else { return }
            pageError = apiError
        }
    }

    /// Patches the loaded rows. Returns `true` when only a reload can reflect the change.
    func apply(_ change: TransactionChange) -> Bool {
        switch change {
        case .invalidated:
            return true
        case .deleted(let id, let transferId):
            let before = transactions.count
            transactions.removeAll { row in
                row.id == id || (transferId != nil && row.transferId == transferId)
            }
            serverOffset = max(0, serverOffset - (before - transactions.count))
            planned.removeAll { $0.id == id }
            return false
        case .saved(let rows):
            for row in rows {
                if let index = planned.firstIndex(where: { $0.id == row.id }) {
                    if row.isPlanned { planned[index] = row } else { planned.remove(at: index) }
                } else if row.isPlanned, showsPlannedSection {
                    planned.append(row)
                    planned.sort { $0.time < $1.time }
                }
                let index = transactions.firstIndex { $0.id == row.id }
                let inScope = scopeAccountIds.isEmpty || scopeAccountIds.contains(row.accountId)
                switch (index, inScope) {
                case (let index?, true):
                    transactions[index] = row
                case (let index?, false):
                    transactions.remove(at: index)
                case (nil, true):
                    // New rows are only inserted when nothing else could exclude them.
                    guard filter.activeCount == 0, !isSearching else { return true }
                    transactions.append(row)
                case (nil, false):
                    break
                }
            }
            transactions.sort { $0.time > $1.time }
            return false
        }
    }
}

/// Parses amounts typed into text fields, accepting either decimal separator.
enum EditorAmountParser {
    static func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let grouping = Locale.current.groupingSeparator ?? ""
        let decimal = Locale.current.decimalSeparator ?? "."
        var cleaned = trimmed
        if !grouping.isEmpty, grouping != decimal, grouping != "." && grouping != "," {
            cleaned = cleaned.replacingOccurrences(of: grouping, with: "")
        }
        cleaned = cleaned
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard cleaned.wholeMatch(of: /-?\d*\.?\d*/) != nil, cleaned.contains(where: \.isNumber) else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Plain text for prefilling a field, without grouping.
    static func text(_ amount: Decimal) -> String {
        amount.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}
