import Foundation

extension Endpoints {
    /// `GET /stats/combined-balance-history`: daily totals in the base currency.
    public static func combinedBalanceHistory(from: CalendarDate, to: CalendarDate) -> Endpoint<[BalancePoint]> {
        Endpoint(.get, "/stats/combined-balance-history", query: dayRange(from: from, to: to).items)
    }

    /// `GET /stats/spendings-by-categories`, sorted largest first. Amounts are positive.
    public static func spendingsByCategories(
        from: CalendarDate,
        to: CalendarDate,
        type: TransactionType = .expense,
        excludePlanned: Bool = true
    ) -> Endpoint<[CategorySpending]> {
        var query = dayRange(from: from, to: to)
        if type != .unknown { query.add("type", type.rawValue) }
        query.add("excludePlanned", excludePlanned)
        return Endpoint<CategorySpendingMap>(.get, "/stats/spendings-by-categories", query: query.items).map(\.items)
    }

    /// `GET /stats/expenses-amount-for-period`: total expenses in the base currency.
    public static func expensesAmountForPeriod(from: CalendarDate, to: CalendarDate) -> Endpoint<ExpensesTotal> {
        Endpoint(.get, "/stats/expenses-amount-for-period", query: dayRange(from: from, to: to).items)
    }

    private static func dayRange(from: CalendarDate, to: CalendarDate) -> QueryBuilder {
        var query = QueryBuilder()
        query.add("from", day: from)
        query.add("to", day: to)
        return query
    }
}
