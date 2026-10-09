import Foundation

extension Endpoints {
    // MARK: Portfolios

    /// `GET /investments/portfolios`: live portfolios, or the trash with `onlyDeleted`.
    public static func portfolios(onlyDeleted: Bool = false) -> Endpoint<[Portfolio]> {
        var query = QueryBuilder()
        query.addFlag("onlyDeleted", onlyDeleted)
        query.add("limit", 100)
        return Endpoint<PortfolioListPage>(.get, "/investments/portfolios", query: query.items).map(\.data)
    }

    /// `GET /investments/portfolios/:id`.
    public static func portfolio(id: String) -> Endpoint<Portfolio> {
        Endpoint(.get, "/investments/portfolios/\(id)")
    }

    /// `POST /investments/portfolios`.
    public static func portfolioCreate(_ request: PortfolioCreateRequest) -> Endpoint<Portfolio> {
        Endpoint(.post, "/investments/portfolios", body: request)
    }

    /// `PUT /investments/portfolios/:id`.
    public static func portfolioUpdate(id: String, _ request: PortfolioUpdateRequest) -> Endpoint<Portfolio> {
        Endpoint(.put, "/investments/portfolios/\(id)", body: request)
    }

    /// `DELETE /investments/portfolios/:id`: moves it to the trash, or with `force` deletes
    /// it and everything in it for good.
    public static func portfolioDelete(id: String, force: Bool = false) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/investments/portfolios/\(id)", body: PortfolioDeleteRequest(force: force ? true : nil))
    }

    /// `POST /investments/portfolios/:id/restore`: brings a portfolio back from the trash.
    public static func portfolioRestore(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/investments/portfolios/\(id)/restore")
    }

    /// `GET /investments/portfolios/:id/summary`: value, cost basis, gains and cash.
    public static func portfolioSummary(id: String) -> Endpoint<PortfolioSummary> {
        Endpoint(.get, "/investments/portfolios/\(id)/summary")
    }

    // MARK: Holdings

    /// `GET /investments/portfolios/:id/holdings`.
    public static func holdings(portfolioID: String) -> Endpoint<[PortfolioHolding]> {
        Endpoint(.get, "/investments/portfolios/\(portfolioID)/holdings")
    }

    /// `POST /investments/holding`.
    public static func holdingCreate(_ request: HoldingCreateRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/investments/holding", body: request)
    }

    /// `DELETE /investments/holding`.
    public static func holdingDelete(_ request: HoldingDeleteRequest) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/investments/holding", body: request)
    }

    // MARK: Securities

    /// `GET /investments/securities/search`. Passing the portfolio flags hits it already holds.
    public static func investmentSecuritiesSearch(
        query text: String,
        portfolioID: String? = nil
    ) -> Endpoint<[InvestmentSecuritySearchResult]> {
        var query = QueryBuilder()
        query.add("query", text)
        query.add("portfolioId", portfolioID)
        return Endpoint(.get, "/investments/securities/search", query: query.items)
    }

    // MARK: Investment transactions

    /// `GET /investments/transactions`: a page of trades for a portfolio, optionally one holding.
    public static func investmentTransactions(
        portfolioID: String,
        securityID: String? = nil,
        limit: Int = 20,
        offset: Int = 0
    ) -> Endpoint<InvestmentTransactionPage> {
        var query = QueryBuilder()
        query.add("portfolioId", portfolioID)
        query.add("securityId", securityID)
        query.add("limit", limit)
        query.add("offset", offset)
        return Endpoint(.get, "/investments/transactions", query: query.items)
    }

    /// `POST /investments/transaction`.
    public static func investmentTransactionCreate(
        _ request: InvestmentTransactionCreateRequest
    ) -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/investments/transaction", body: request)
    }

    /// `PUT /investments/transaction/:id`.
    public static func investmentTransactionUpdate(
        id: String,
        _ request: InvestmentTransactionUpdateRequest
    ) -> Endpoint<EmptyResponse> {
        Endpoint(.put, "/investments/transaction/\(id)", body: request)
    }

    /// `DELETE /investments/transaction/:id`.
    public static func investmentTransactionDelete(id: String) -> Endpoint<EmptyResponse> {
        Endpoint(.delete, "/investments/transaction/\(id)")
    }
}
