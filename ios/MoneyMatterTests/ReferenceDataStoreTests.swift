import Foundation
import MoneyMatterKit
import Testing
@testable import MoneyMatter

final class StubReferenceData: ReferenceDataServicing {
    var accountsResult: Result<[Account], APIError> = .success([
        Account(id: "a1", name: "Checking", currencyCode: "EUR"),
        Account(id: "a2", name: "Old card", currencyCode: "USD", status: .archived),
    ])
    var categoriesResult: Result<[MoneyMatterKit.Category], APIError> = .success([
        MoneyMatterKit.Category(id: "c-food", name: "Food"),
        MoneyMatterKit.Category(id: "c-cafe", name: "Cafe", parentId: "c-food"),
    ])
    var tagsResult: Result<[MoneyMatterKit.Tag], APIError> = .success([MoneyMatterKit.Tag(id: "t1", name: "Trip")])
    var payeesResult: Result<[PayeeLookup], APIError> = .success([PayeeLookup(id: "p1", name: "Lidl")])
    var currenciesResult: Result<[UserCurrency], APIError> = .success([
        UserCurrency(id: "uc1", userId: 1, currencyCode: "JPY", currency: Currency(code: "JPY", currency: "Yen", digits: 0)),
    ])

    func accounts() async throws -> [Account] { try accountsResult.get() }
    func categories() async throws -> [MoneyMatterKit.Category] { try categoriesResult.get() }
    func tags() async throws -> [MoneyMatterKit.Tag] { try tagsResult.get() }
    func payeesLookup() async throws -> [PayeeLookup] { try payeesResult.get() }
    func userCurrencies() async throws -> [UserCurrency] { try currenciesResult.get() }
}

@Suite("ReferenceDataStore")
struct ReferenceDataStoreTests {
    @Test("Refresh loads every list and builds lookups and the category tree")
    func refresh() async {
        let source = StubReferenceData()
        let store = ReferenceDataStore { source }

        await store.refresh()

        #expect(store.hasLoaded)
        #expect(store.account(id: "a1")?.name == "Checking")
        #expect(store.activeAccounts.map(\.id) == ["a1"])
        #expect(store.category(id: "c-cafe")?.name == "Cafe")
        #expect(store.categoryTree.first?.children.map(\.id) == ["c-cafe"])
        #expect(store.tag(id: "t1")?.name == "Trip")
        #expect(store.payee(id: "p1")?.name == "Lidl")
        #expect(store.digits(for: "JPY") == 0)
        #expect(store.digits(for: "GBP") == nil)
        #expect(store.account(id: nil) == nil)
    }

    @Test("A failing list keeps its previous value and leaves the store not loaded")
    func partialFailure() async {
        let source = StubReferenceData()
        let store = ReferenceDataStore { source }
        await store.refresh()

        source.tagsResult = .failure(.network(URLError(.timedOut)))
        source.payeesResult = .success([PayeeLookup(id: "p2", name: "Landlord")])
        await store.refresh()

        #expect(store.tags.map(\.id) == ["t1"])
        #expect(store.payees.map(\.id) == ["p2"])
        #expect(store.lastError == .network(URLError(.timedOut)))
        #expect(store.hasLoaded == false)
    }

    @Test("Without a connected server nothing loads")
    func noSource() async {
        let store = ReferenceDataStore { nil }
        await store.loadIfNeeded()
        #expect(store.hasLoaded == false)
        #expect(store.accounts.isEmpty)
    }

    @Test("Local upserts and removals update lookups")
    func localUpdates() async {
        let source = StubReferenceData()
        let store = ReferenceDataStore { source }
        await store.refresh()

        store.upsert(Account(id: "a1", name: "Main checking", currencyCode: "EUR"))
        store.upsert(Account(id: "a3", name: "Savings", currencyCode: "EUR"))
        store.removeAccount(id: "a2")

        #expect(store.accounts.map(\.name) == ["Main checking", "Savings"])
        #expect(store.account(id: "a2") == nil)
    }

    @Test("A refresh still in flight when the session resets doesn't repopulate the store")
    func resetDuringRefresh() async {
        let gate = AsyncGate()
        let source = GatedReferenceData(gate: gate)
        let store = ReferenceDataStore { source }

        let refresh = Task { await store.refresh() }
        await gate.waitUntilEntered()
        store.reset()
        await gate.open()
        await refresh.value

        #expect(store.accounts.isEmpty)
        #expect(store.hasLoaded == false)
    }

    @Test("Reset clears everything for the next session")
    func reset() async {
        let source = StubReferenceData()
        let store = ReferenceDataStore { source }
        await store.refresh()

        store.reset()

        #expect(store.hasLoaded == false)
        #expect(store.accounts.isEmpty)
        #expect(store.categoryTree.isEmpty)
        #expect(store.payee(id: "p1") == nil)
    }
}

/// Holds every fetch until the test opens it.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

final class GatedReferenceData: ReferenceDataServicing {
    let gate: AsyncGate
    let wrapped = StubReferenceData()

    init(gate: AsyncGate) {
        self.gate = gate
    }

    func accounts() async throws -> [Account] {
        await gate.pass()
        return try await wrapped.accounts()
    }

    func categories() async throws -> [MoneyMatterKit.Category] {
        await gate.pass()
        return try await wrapped.categories()
    }

    func tags() async throws -> [MoneyMatterKit.Tag] {
        await gate.pass()
        return try await wrapped.tags()
    }

    func payeesLookup() async throws -> [PayeeLookup] {
        await gate.pass()
        return try await wrapped.payeesLookup()
    }

    func userCurrencies() async throws -> [UserCurrency] {
        await gate.pass()
        return try await wrapped.userCurrencies()
    }
}
