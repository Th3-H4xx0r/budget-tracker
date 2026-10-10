import Foundation

/// Builds this month's `MonthlySpendingSnapshot` from the API: the budget from
/// `/user/settings`, the base currency, and every real expense since the 1st.
public struct MonthlySpendingLoader: Sendable {
    public static let pageSize = 500
    /// Stops paging after this many pages so a misbehaving server can't loop forever.
    static let maxPages = 40

    public let client: APIClient
    public let calendar: Calendar

    public init(client: APIClient, calendar: Calendar = .autoupdatingCurrent) {
        self.client = client
        self.calendar = calendar
    }

    public func load(now: Date = .now) async throws -> MonthlySpendingSnapshot {
        let month = BudgetMonth(containing: now, calendar: calendar)
        let monthStart = month.startDate(calendar: calendar)

        async let settings = client.send(Endpoints.monthlyBudgetSettings())
        async let baseCurrency = client.send(Endpoints.baseCurrency())
        async let expenses = fetchExpenses(from: monthStart, to: now)

        let transactions = try await expenses
        let budget = try await settings.effectiveAmount
        let currencyCode = try await baseCurrency?.currencyCode
            ?? Locale.autoupdatingCurrent.currency?.identifier
            ?? "USD"

        let today = calendar.component(.day, from: now)
        let cumulative = MonthlySpendingSnapshot.dailyCumulative(
            of: transactions,
            month: month,
            throughDay: today,
            calendar: calendar
        )
        return MonthlySpendingSnapshot(
            month: month,
            spent: cumulative.last ?? 0,
            budget: budget,
            dailyCumulative: cumulative,
            currencyCode: currencyCode,
            updatedAt: now
        )
    }

    /// `GET /transactions` for real, non-transfer, non-adjustment expenses in the range.
    public static func expenseQuery(from: Date, to: Date, offset: Int) -> TransactionListQuery {
        var query = TransactionListQuery(limit: pageSize, offset: offset > 0 ? offset : nil)
        query.from = from
        query.to = to
        query.transactionType = .expense
        query.isPlanned = false
        query.excludeTransfer = true
        query.excludeBalanceAdjustments = true
        return query
    }

    private func fetchExpenses(from: Date, to: Date) async throws -> [Transaction] {
        var all: [Transaction] = []
        var offset = 0
        for _ in 0..<Self.maxPages {
            let page = try await client.send(Endpoints.transactions(Self.expenseQuery(from: from, to: to, offset: offset)))
            all.append(contentsOf: page)
            guard page.count >= Self.pageSize else { break }
            offset += page.count
        }
        return all
    }
}
