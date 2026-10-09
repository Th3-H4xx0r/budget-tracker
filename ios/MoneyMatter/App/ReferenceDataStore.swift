import Foundation
import MoneyMatterKit
import Observation

/// Session-wide cache of the lookups most screens need: accounts, categories, tags, payee
/// names, and the user's currencies. Refresh it on pull-to-refresh and after any write that
/// changes one of them. Read it with `@Environment(ReferenceDataStore.self)`.
@Observable
final class ReferenceDataStore {
    private(set) var accounts: [Account] = []
    private(set) var categories: [Category] = []
    private(set) var categoryTree: [CategoryNode] = []
    private(set) var tags: [Tag] = []
    private(set) var payees: [PayeeLookup] = []
    private(set) var userCurrencies: [UserCurrency] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// The most recent load failure, cleared by the next successful refresh.
    private(set) var lastError: APIError?

    private var accountsByID: [String: Account] = [:]
    private var categoriesByID: [String: Category] = [:]
    private var tagsByID: [String: Tag] = [:]
    private var payeesByID: [String: PayeeLookup] = [:]
    private var currenciesByCode: [String: UserCurrency] = [:]

    @ObservationIgnored private let source: () -> (any ReferenceDataServicing)?
    /// Bumped by `reset()`, so loads started for an earlier session are discarded.
    @ObservationIgnored private var generation = 0
    /// Set when any list in the current `refresh()` didn't apply, including cancellation.
    @ObservationIgnored private var refreshIncomplete = false

    init(source: @escaping () -> (any ReferenceDataServicing)?) {
        self.source = source
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await refresh()
    }

    /// Reloads everything in parallel. A failing list keeps its previous value.
    func refresh() async {
        guard source() != nil else { return }
        let startedGeneration = generation
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        refreshIncomplete = false
        async let accountsLoad: Void = refreshAccounts()
        async let categoriesLoad: Void = refreshCategories()
        async let tagsLoad: Void = refreshTags()
        async let payeesLoad: Void = refreshPayees()
        async let currenciesLoad: Void = refreshCurrencies()
        _ = await (accountsLoad, categoriesLoad, tagsLoad, payeesLoad, currenciesLoad)
        guard startedGeneration == generation else { return }
        hasLoaded = !refreshIncomplete
    }

    func refreshAccounts() async {
        await load({ try await $0.accounts() }, apply: setAccounts)
    }

    func refreshCategories() async {
        await load({ try await $0.categories() }, apply: setCategories)
    }

    func refreshTags() async {
        await load({ try await $0.tags() }, apply: setTags)
    }

    func refreshPayees() async {
        await load({ try await $0.payeesLookup() }, apply: setPayees)
    }

    func refreshCurrencies() async {
        await load({ try await $0.userCurrencies() }, apply: setCurrencies)
    }

    func reset() {
        generation += 1
        setAccounts([])
        setCategories([])
        setTags([])
        setPayees([])
        setCurrencies([])
        hasLoaded = false
        lastError = nil
    }

    // MARK: Local updates after writes

    func upsert(_ account: Account) {
        var updated = accounts
        if let index = updated.firstIndex(where: { $0.id == account.id }) {
            updated[index] = account
        } else {
            updated.append(account)
        }
        setAccounts(updated)
    }

    func removeAccount(id: String) {
        setAccounts(accounts.filter { $0.id != id })
    }

    func upsert(_ payee: PayeeLookup) {
        guard payeesByID[payee.id] != payee else { return }
        setPayees(payees.filter { $0.id != payee.id } + [payee])
    }

    // MARK: Lookups

    func account(id: String?) -> Account? {
        id.flatMap { accountsByID[$0] }
    }

    func category(id: String?) -> Category? {
        id.flatMap { categoriesByID[$0] }
    }

    func tag(id: String?) -> Tag? {
        id.flatMap { tagsByID[$0] }
    }

    func payee(id: String?) -> PayeeLookup? {
        id.flatMap { payeesByID[$0] }
    }

    func userCurrency(code: String?) -> UserCurrency? {
        code.flatMap { currenciesByCode[$0] }
    }

    /// Minor-unit digits for `code` when the user has connected it; nil means use the ISO default.
    func digits(for code: String?) -> Int? {
        userCurrency(code: code)?.currency?.digits
    }

    var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    // MARK: Private

    private func load<Value>(
        _ fetch: (any ReferenceDataServicing) async throws -> Value,
        apply: (Value) -> Void
    ) async {
        guard let source = source() else { return }
        let startedGeneration = generation
        do {
            let value = try await fetch(source)
            guard startedGeneration == generation else { return }
            apply(value)
        } catch {
            guard startedGeneration == generation else { return }
            refreshIncomplete = true
            let apiError = APIError(error)
            if !apiError.isCancellation { lastError = apiError }
        }
    }

    private func setAccounts(_ value: [Account]) {
        accounts = value
        accountsByID = Dictionary(value.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    private func setCategories(_ value: [Category]) {
        categories = value
        categoryTree = CategoryTree.build(from: value)
        categoriesByID = Dictionary(value.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    private func setTags(_ value: [Tag]) {
        tags = value
        tagsByID = Dictionary(value.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    private func setPayees(_ value: [PayeeLookup]) {
        payees = value
        payeesByID = Dictionary(value.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    private func setCurrencies(_ value: [UserCurrency]) {
        userCurrencies = value
        currenciesByCode = Dictionary(value.map { ($0.currencyCode, $0) }, uniquingKeysWith: { _, latest in latest })
    }
}
