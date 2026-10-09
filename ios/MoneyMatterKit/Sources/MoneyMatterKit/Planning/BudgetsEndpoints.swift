import Foundation

extension Endpoints {
    /// `GET /budgets`. The server defaults to active budgets when `statuses` is empty.
    public static func planningBudgets(statuses: [PlanningBudgetStatus] = [.active]) -> Endpoint<[PlanningBudget]> {
        var query = QueryBuilder()
        query.add("status", list: statuses.filter { $0 != .unknown }.map(\.rawValue))
        return Endpoint(.get, "/budgets", query: query.items)
    }

    /// `GET /budgets/:id`.
    public static func planningBudget(id: String) -> Endpoint<PlanningBudget> {
        Endpoint(.get, "/budgets/\(id)")
    }

    /// `GET /budgets/:id/stats`.
    public static func planningBudgetStats(id: String) -> Endpoint<PlanningBudgetStats> {
        Endpoint(.get, "/budgets/\(id)/stats")
    }

    /// `GET /budgets/:id/spending-stats`: category breakdown and spending over time.
    public static func planningBudgetSpendingStats(id: String) -> Endpoint<PlanningBudgetSpendingStats> {
        Endpoint(.get, "/budgets/\(id)/spending-stats")
    }

    /// `GET /budgets/:id/category-transactions`. Category budgets only; `limit` is capped at 100.
    public static func planningBudgetCategoryTransactions(
        id: String,
        from: Int = 0,
        limit: Int = 50
    ) -> Endpoint<PlanningBudgetCategoryTransactionsPage> {
        var query = QueryBuilder()
        query.add("from", from)
        query.add("limit", min(max(limit, 1), 100))
        return Endpoint(.get, "/budgets/\(id)/category-transactions", query: query.items)
    }

    /// `POST /budgets`.
    public static func createPlanningBudget(_ request: PlanningBudgetCreateRequest) -> Endpoint<PlanningBudget> {
        Endpoint(.post, "/budgets", body: request)
    }

    /// `PUT /budgets/:id`. The server returns `null` if the budget vanished mid-edit.
    public static func updatePlanningBudget(id: String, _ request: PlanningBudgetUpdateRequest) -> Endpoint<PlanningBudget?> {
        Endpoint(.put, "/budgets/\(id)", body: request)
    }

    /// `PATCH /budgets/:id/archive`.
    public static func setPlanningBudgetArchived(id: String, isArchived: Bool) -> Endpoint<PlanningBudget> {
        Endpoint(.patch, "/budgets/\(id)/archive", body: PlanningBudgetArchiveRequest(isArchived: isArchived))
    }

    /// `DELETE /budgets/:id`. Owner-only.
    public static func deletePlanningBudget(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/budgets/\(id)")
    }

    /// `POST /budgets/:id/transactions`. Manual budgets; ids must be unique and non-empty.
    public static func addTransactionsToPlanningBudget(id: String, transactionIds: [String]) -> Endpoint<EmptyResponse> {
        var seen = Set<String>()
        let unique = transactionIds.filter { seen.insert($0).inserted }
        return Endpoint(.post, "/budgets/\(id)/transactions", body: PlanningBudgetTransactionsRequest(transactionIds: unique))
    }

    /// `DELETE /budgets/:id/transactions`, with the ids in the body.
    public static func removeTransactionsFromPlanningBudget(id: String, transactionIds: [String]) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/budgets/\(id)/transactions", body: PlanningBudgetTransactionsRequest(transactionIds: transactionIds))
    }
}
