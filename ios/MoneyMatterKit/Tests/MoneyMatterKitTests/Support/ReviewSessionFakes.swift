import Foundation
@testable import MoneyMatterKit

struct TestFailure: Error, Equatable {}

/// A fake server queue: each page is sliced from whatever `rows` holds at call time, so a
/// test can mimic rows leaving the queue (reviewed) or arriving (sync) between pages.
/// Scripted failures are consumed first.
actor FakeReviewServer {
    struct PageCall: Equatable, Sendable {
        let offset: Int
        let limit: Int
    }

    private(set) var rows: [Transaction]
    private(set) var calls: [PageCall] = []
    private var scriptedFailures: [Bool]

    init(rows: [Transaction], failures: [Bool] = []) {
        self.rows = rows
        self.scriptedFailures = failures
    }

    func setRows(_ rows: [Transaction]) {
        self.rows = rows
    }

    /// Serves a page, or throws when the next scripted outcome is a failure.
    func page(offset: Int, limit: Int) throws -> [Transaction] {
        calls.append(PageCall(offset: offset, limit: limit))
        if !scriptedFailures.isEmpty, scriptedFailures.removeFirst() {
            throw TestFailure()
        }
        return Array(rows.dropFirst(offset).prefix(limit))
    }

    var callCount: Int { calls.count }
}

/// Records review writes, failing the ones the script marks.
actor FakeReviewWriter {
    struct Call: Equatable, Sendable {
        let ids: [String]
        let action: ReviewAction
    }

    private(set) var calls: [Call] = []
    private var outcomes: [Bool]
    private let gate: Gate?

    /// `failures[i] == true` makes the i-th write throw; later writes succeed.
    init(failures: [Bool] = [], gate: Gate? = nil) {
        self.outcomes = failures
        self.gate = gate
    }

    func submit(ids: [String], action: ReviewAction) async throws {
        calls.append(Call(ids: ids, action: action))
        let shouldFail = outcomes.isEmpty ? false : outcomes.removeFirst()
        if let gate { await gate.wait() }
        if shouldFail { throw TestFailure() }
    }

    var lastCall: Call? { calls.last }
}

/// Holds async work until the test opens it.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// An ordered log shared between the test and the injected closures.
actor EventLog {
    private(set) var events: [String] = []

    @discardableResult
    func append(_ event: String) -> Int {
        events.append(event)
        return events.count
    }
}

/// Captures the session's callbacks.
@MainActor
final class ReviewCallbacks {
    var successes = 0
    var errors: [(kind: ReviewSubmitErrorKind, transactionID: String)] = []
    var loadMoreErrors = 0

    func attach(to session: ReviewSession) {
        session.onSubmitSuccess = { [unowned self] in successes += 1 }
        session.onSubmitError = { [unowned self] _, kind, transaction in errors.append((kind, transaction.id)) }
        session.onLoadMoreError = { [unowned self] _ in loadMoreErrors += 1 }
    }
}

@MainActor
struct ReviewHarness {
    let session: ReviewSession
    let server: FakeReviewServer
    let writer: FakeReviewWriter
    let callbacks = ReviewCallbacks()

    init(
        rows: [Transaction],
        pageSize: Int = 5,
        prefetchThreshold: Int = 2,
        fetchFailures: [Bool] = [],
        writeFailures: [Bool] = [],
        gate: Gate? = nil
    ) {
        let server = FakeReviewServer(rows: rows, failures: fetchFailures)
        let writer = FakeReviewWriter(failures: writeFailures, gate: gate)
        self.server = server
        self.writer = writer
        session = ReviewSession(
            pageSize: pageSize,
            prefetchThreshold: prefetchThreshold,
            fetchPage: { offset, limit in try await server.page(offset: offset, limit: limit) },
            submitAction: { ids, action in try await writer.submit(ids: ids, action: action) }
        )
        callbacks.attach(to: session)
    }

    var queueIDs: [String] { session.queue.map(\.id) }
    var currentID: String? { session.current?.id }
}

/// Lets queued main-actor tasks run.
@MainActor
func drainTasks(_ rounds: Int = 50) async {
    for _ in 0..<rounds { await Task.yield() }
}
