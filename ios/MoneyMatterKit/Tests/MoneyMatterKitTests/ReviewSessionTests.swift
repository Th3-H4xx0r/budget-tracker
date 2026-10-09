import Foundation
import Testing
@testable import MoneyMatterKit

@MainActor
@Suite("ReviewSession")
struct ReviewSessionTests {
    private func rows(_ prefix: String = "tx", count: Int) -> [Transaction] {
        Transaction.stubs(prefix: prefix, count: count)
    }

    // MARK: Advance

    @Test("Loads the first page and shows the first card as 1 of total")
    func firstPage() async {
        let harness = ReviewHarness(rows: rows(count: 3))
        await harness.session.start(total: 3)

        #expect(await harness.server.calls == [.init(offset: 0, limit: 5)])
        #expect(harness.currentID == "tx-1")
        #expect(harness.session.position == 1)
        #expect(harness.session.total == 3)
        #expect(harness.session.isFinished == false)
    }

    @Test("Advances immediately and submits the action in the background")
    func advances() async {
        let harness = ReviewHarness(rows: rows(count: 3))
        await harness.session.start(total: 3)

        harness.session.act(.reviewed)

        #expect(harness.currentID == "tx-2")
        #expect(harness.session.position == 2)
        await harness.session.whenSettled()
        #expect(await harness.writer.calls == [.init(ids: ["tx-1"], action: .reviewed)])
        #expect(harness.callbacks.successes == 1)
        #expect(harness.session.submittedCount == 1)
    }

    @Test("Sends writes in the order the user made them, even when the first is slow")
    func ordersWrites() async {
        let log = EventLog()
        let gate = Gate()
        let session = ReviewSession(
            pageSize: 5,
            prefetchThreshold: 2,
            fetchPage: { _, _ in Transaction.stubs(prefix: "tx", count: 3) },
            submitAction: { _, action in
                let index = await log.append("start:\(action.rawValue)")
                if index == 1 { await gate.wait() }
                await log.append("end:\(action.rawValue)")
            }
        )
        await session.start(total: 3)

        session.act(.fraud)
        session.undo()
        // Hold the first write open until it has started, so a second write that didn't wait
        // for it would show up in between.
        var attempts = 0
        while await log.events.isEmpty, attempts < 1_000 {
            attempts += 1
            await Task.yield()
        }
        await drainTasks()
        await gate.open()
        await session.whenSettled()

        #expect(await log.events == ["start:fraud", "end:fraud", "start:unreviewed", "end:unreviewed"])
    }

    @Test("Reaches the finished state after the last card")
    func finishes() async {
        let harness = ReviewHarness(rows: rows(count: 2))
        await harness.session.start(total: 2)

        harness.session.act(.reviewed)
        harness.session.act(.fraud)
        await harness.session.whenSettled()

        #expect(harness.session.current == nil)
        #expect(harness.session.isFinished)
        #expect(harness.session.position == 2)
        #expect(harness.session.total == 2)
    }

    @Test("Finishes straight away when the queue is empty")
    func emptyQueue() async {
        let harness = ReviewHarness(rows: [])
        await harness.session.start(total: 0)

        #expect(harness.session.current == nil)
        #expect(harness.session.isFinished)
    }

    @Test("Ignores actions when there is no card")
    func noCard() async {
        let harness = ReviewHarness(rows: [])
        await harness.session.start(total: 0)

        harness.session.act(.reviewed)
        await harness.session.whenSettled()

        #expect(await harness.writer.calls.isEmpty)
        #expect(harness.session.processedCount == 0)
    }

    // MARK: Paging

    @Test("Requests the next page from offset 0 before the user reaches the end")
    func prefetches() async {
        let all = rows(count: 8)
        let harness = ReviewHarness(rows: all, pageSize: 5, prefetchThreshold: 2)
        await harness.session.start(total: 8)
        #expect(harness.session.queue.count == 5)

        harness.session.act(.reviewed)
        harness.session.act(.reviewed)
        #expect(await harness.server.callCount == 1)

        // Reviewed rows leave the server queue as their writes land.
        await harness.server.setRows(Array(all.dropFirst(2)))
        harness.session.act(.reviewed)
        await harness.session.whenLoaded()

        #expect(await harness.server.calls == [.init(offset: 0, limit: 5), .init(offset: 0, limit: 5)])
        // The page is tx-3...tx-7: tx-3 is already decided and tx-4/tx-5 are queued, so only
        // tx-6 and tx-7 are new.
        #expect(harness.queueIDs == ["tx-4", "tx-5", "tx-6", "tx-7"])
        #expect(harness.session.hasMore)
    }

    @Test("Stops paging after a short page")
    func shortPage() async {
        let all = rows(count: 6)
        let harness = ReviewHarness(rows: all, pageSize: 5, prefetchThreshold: 2)
        await harness.session.start(total: 6)

        harness.session.act(.reviewed)
        harness.session.act(.reviewed)
        await harness.server.setRows(Array(all.dropFirst(3)))
        harness.session.act(.reviewed)
        await harness.session.whenLoaded()

        #expect(harness.queueIDs == ["tx-4", "tx-5", "tx-6"])
        #expect(harness.session.hasMore == false)

        harness.session.act(.reviewed)
        await harness.session.whenLoaded()
        #expect(await harness.server.callCount == 2)
    }

    @Test("Walks past a full page of rows the session already holds")
    func walksPastSeenRows() async {
        let deferred = rows("deferred", count: 3)
        let later = rows("later", count: 2)
        let harness = ReviewHarness(rows: deferred, pageSize: 3, prefetchThreshold: 0)
        await harness.session.start(total: 3)

        harness.session.act(.checkLater)
        harness.session.act(.checkLater)
        // A sync lands rows that sort after the deferred ones on the server.
        await harness.server.setRows(deferred + later)
        harness.session.act(.checkLater)
        await harness.session.whenLoaded()

        let calls = await harness.server.calls
        #expect(calls.count == 3)
        #expect(calls[1] == .init(offset: 0, limit: 3))
        #expect(calls[2] == .init(offset: 3, limit: 3))
        #expect(harness.queueIDs == ["later-1", "later-2"])
    }

    @Test("Keeps a failed first load visible and retries on demand")
    func failedFirstLoad() async {
        let harness = ReviewHarness(rows: rows(count: 2), fetchFailures: [true])

        await harness.session.start(total: 2)
        #expect(harness.session.loadError != nil)
        #expect(harness.session.isFinished == false)
        // The empty stack shows its own error state, so no separate notice goes out.
        #expect(harness.callbacks.loadMoreErrors == 0)

        await harness.session.retry()
        #expect(harness.session.loadError == nil)
        #expect(harness.currentID == "tx-1")
    }

    @Test("Reports a failed background load once and retries it on the next actions")
    func backgroundLoadFailure() async {
        let first = rows(count: 4)
        let later = rows("later", count: 2)
        let harness = ReviewHarness(rows: first, pageSize: 4, prefetchThreshold: 2, fetchFailures: [false, true, true])
        await harness.session.start(total: 6)
        await harness.server.setRows(later)

        harness.session.act(.reviewed)
        harness.session.act(.reviewed)
        await harness.session.whenLoaded()
        #expect(await harness.server.callCount == 2)
        #expect(harness.callbacks.loadMoreErrors == 1)

        harness.session.act(.reviewed)
        await harness.session.whenLoaded()
        #expect(await harness.server.callCount == 3)
        #expect(harness.callbacks.loadMoreErrors == 1)

        harness.session.act(.reviewed)
        await harness.session.whenLoaded()
        #expect(await harness.server.callCount == 4)
        #expect(harness.session.loadError == nil)
        #expect(harness.queueIDs == ["later-1", "later-2"])
    }

    @Test("Page size is capped at the endpoint's limit of 100")
    func pageSizeCap() async {
        let harness = ReviewHarness(rows: rows(count: 3), pageSize: 500)
        await harness.session.start()

        #expect(await harness.server.calls == [.init(offset: 0, limit: 100)])
    }

    @Test("Falls back to the loaded count when the total is unknown")
    func unknownTotal() async {
        let harness = ReviewHarness(rows: rows(count: 5), pageSize: 5)
        await harness.session.start()

        #expect(harness.session.total == 5)
        #expect(harness.session.position == 1)
    }

    @Test("Grows the total when more rows exist than the summary reported")
    func growsTotal() async {
        let harness = ReviewHarness(rows: rows(count: 4), pageSize: 5)
        await harness.session.start(total: 2)

        #expect(harness.session.total == 4)
    }

    // MARK: Defer

    @Test("Counts rows saved for later")
    func countsDeferred() async {
        let harness = ReviewHarness(rows: rows(count: 3))
        await harness.session.start(total: 3)

        harness.session.act(.checkLater)
        harness.session.act(.reviewed)
        harness.session.act(.checkLater)
        await harness.session.whenSettled()

        #expect(harness.session.deferredCount == 2)
        #expect(harness.session.isFinished)
        #expect(await harness.writer.calls.first == .init(ids: ["tx-1"], action: .checkLater))
    }

    @Test("Doesn't bring a deferred row back when the server returns it at the back of the queue")
    func deferredStaysGone() async {
        let all = rows(count: 3)
        let harness = ReviewHarness(rows: all, pageSize: 3, prefetchThreshold: 1)
        await harness.session.start(total: 3)

        harness.session.act(.checkLater)
        // The deferral moved tx-1 behind every fresh row.
        await harness.server.setRows([all[1], all[2], all[0]])
        harness.session.act(.reviewed)
        await harness.session.whenLoaded()

        #expect(harness.queueIDs == ["tx-3"])
        harness.session.act(.reviewed)
        await harness.session.whenSettled()
        #expect(harness.session.isFinished)
    }

    // MARK: Undo

    @Test("Undo returns the last card to the front and sends unreviewed")
    func undo() async {
        let harness = ReviewHarness(rows: rows(count: 3))
        await harness.session.start(total: 3)

        harness.session.act(.fraud)
        let undone = harness.session.undo()

        #expect(undone?.transaction.id == "tx-1")
        #expect(harness.currentID == "tx-1")
        #expect(harness.session.position == 1)
        #expect(harness.session.canUndo == false)
        await harness.session.whenSettled()
        #expect(await harness.writer.lastCall == .init(ids: ["tx-1"], action: .unreviewed))
    }

    @Test("Undoes repeatedly, newest action first")
    func undoRepeatedly() async {
        let harness = ReviewHarness(rows: rows(count: 3))
        await harness.session.start(total: 3)

        harness.session.act(.reviewed)
        harness.session.act(.checkLater)
        harness.session.act(.fraud)

        #expect(harness.session.undo()?.transaction.id == "tx-3")
        #expect(harness.session.undo()?.transaction.id == "tx-2")
        #expect(harness.session.undo()?.transaction.id == "tx-1")
        #expect(harness.session.undo() == nil)
        #expect(harness.queueIDs == ["tx-1", "tx-2", "tx-3"])
        #expect(harness.session.deferredCount == 0)
        await harness.session.whenSettled()
    }

    @Test("Drops an undone deferral from the saved-for-later tally")
    func undoDeferral() async {
        let harness = ReviewHarness(rows: rows(count: 2))
        await harness.session.start(total: 2)

        harness.session.act(.checkLater)
        #expect(harness.session.deferredCount == 1)

        harness.session.undo()
        #expect(harness.session.deferredCount == 0)
        await harness.session.whenSettled()
    }

    @Test("Restores the action when the undo write fails")
    func failedUndo() async {
        let harness = ReviewHarness(rows: rows(count: 2), writeFailures: [false, true])
        await harness.session.start(total: 2)

        harness.session.act(.reviewed)
        harness.session.undo()
        await harness.session.whenSettled()

        #expect(harness.currentID == "tx-2")
        #expect(harness.session.processedCount == 1)
        #expect(harness.callbacks.errors.count == 1)
        #expect(harness.callbacks.errors.first?.kind == .undo)
        #expect(harness.callbacks.errors.first?.transactionID == "tx-1")
    }

    @Test("Restores a failed undo even when another undone card sits in front of it")
    func failedUndoBehindAnother() async {
        let harness = ReviewHarness(rows: rows(count: 3), writeFailures: [false, false, true])
        await harness.session.start(total: 3)

        harness.session.act(.reviewed)
        harness.session.act(.fraud)
        // Undo tx-2 (this write fails), then undo tx-1, which lands in front of it.
        harness.session.undo()
        harness.session.undo()
        await harness.session.whenSettled()

        #expect(harness.queueIDs == ["tx-1", "tx-3"])
        #expect(harness.session.processedCount == 1)
        #expect(harness.session.undo()?.transaction.id == "tx-2")
        #expect(harness.callbacks.errors.count == 1)
        await harness.session.whenSettled()
    }

    @Test("Stays silent about a failed undo once the user decided the card again")
    func supersededUndo() async {
        let harness = ReviewHarness(rows: rows(count: 2), writeFailures: [false, true])
        await harness.session.start(total: 2)

        harness.session.act(.reviewed)
        harness.session.undo()
        harness.session.act(.fraud)
        await harness.session.whenSettled()

        #expect(harness.callbacks.errors.isEmpty)
        #expect(harness.currentID == "tx-2")
        #expect(harness.session.processedCount == 1)
        #expect(await harness.writer.lastCall == .init(ids: ["tx-1"], action: .fraud))
    }

    // MARK: Failure rollback

    @Test("A failed action puts the card back at the front and reports the error")
    func rollback() async {
        let harness = ReviewHarness(rows: rows(count: 3), writeFailures: [true])
        await harness.session.start(total: 3)

        harness.session.act(.checkLater)
        #expect(harness.currentID == "tx-2")

        await harness.session.whenSettled()

        #expect(harness.currentID == "tx-1")
        #expect(harness.session.processedCount == 0)
        #expect(harness.session.deferredCount == 0)
        #expect(harness.session.submittedCount == 0)
        #expect(harness.callbacks.errors.first?.kind == .action)
        #expect(harness.callbacks.errors.first?.transactionID == "tx-1")
    }

    @Test("Rolls back only the failed card when later actions succeed")
    func rollbackOnlyFailed() async {
        let harness = ReviewHarness(rows: rows(count: 3), writeFailures: [true])
        await harness.session.start(total: 3)

        harness.session.act(.reviewed)
        harness.session.act(.fraud)
        await harness.session.whenSettled()

        #expect(harness.queueIDs == ["tx-1", "tx-3"])
        #expect(harness.session.processedCount == 1)
        // Undo now targets the surviving action.
        #expect(harness.session.undo()?.transaction.id == "tx-2")
        await harness.session.whenSettled()
    }

    @Test("Leaves the queue alone when the failed action was already undone")
    func failedActionAlreadyUndone() async {
        let harness = ReviewHarness(rows: rows(count: 2), writeFailures: [true])
        await harness.session.start(total: 2)

        harness.session.act(.reviewed)
        harness.session.undo()
        await harness.session.whenSettled()

        #expect(harness.queueIDs == ["tx-1", "tx-2"])
        #expect(harness.callbacks.errors.count == 1)
    }

    // MARK: Restart

    @Test("Restarting starts a fresh session with empty history")
    func restart() async {
        let harness = ReviewHarness(rows: rows(count: 2))
        await harness.session.start(total: 2)
        harness.session.act(.checkLater)
        await harness.session.whenSettled()

        await harness.session.start(total: 2)

        #expect(harness.session.processedCount == 0)
        #expect(harness.session.deferredCount == 0)
        #expect(harness.session.submittedCount == 0)
        #expect(harness.currentID == "tx-1")
    }

    @Test("Restarting waits for pending writes, so decided cards don't come back")
    func restartWaitsForWrites() async {
        let gate = Gate()
        let all = rows(count: 2)
        let harness = ReviewHarness(rows: all, gate: gate)
        await harness.session.start(total: 2)
        harness.session.act(.reviewed)

        let restart = Task { await harness.session.start(total: 2) }
        await drainTasks()
        #expect(await harness.server.callCount == 1)

        // The write lands and tx-1 leaves the server queue before the reload runs.
        await harness.server.setRows(Array(all.dropFirst()))
        await gate.open()
        await restart.value

        #expect(await harness.server.callCount == 2)
        #expect(harness.queueIDs == ["tx-2"])
    }

    // MARK: Guards

    @Test("Ignores an action aimed at a card that is no longer in front")
    func actExpectedID() async {
        let harness = ReviewHarness(rows: rows(count: 3))
        await harness.session.start(total: 3)

        let acted = harness.session.act(.reviewed, expectedID: "tx-2")

        #expect(acted == false)
        #expect(harness.currentID == "tx-1")
        #expect(harness.session.processedCount == 0)
        #expect(harness.session.act(.reviewed, expectedID: "tx-1"))
        #expect(harness.currentID == "tx-2")
    }

    @Test("Is not finished until the last write settles, and a failed last write brings the card back")
    func finishWaitsForWrites() async {
        let gate = Gate()
        let harness = ReviewHarness(rows: rows(count: 1), writeFailures: [true], gate: gate)
        await harness.session.start(total: 1)

        harness.session.act(.reviewed)
        await drainTasks()

        #expect(harness.session.current == nil)
        #expect(harness.session.pendingWriteCount == 1)
        #expect(harness.session.isFinished == false)

        await gate.open()
        await harness.session.whenSettled()

        #expect(harness.session.pendingWriteCount == 0)
        #expect(harness.currentID == "tx-1")
        #expect(harness.session.isFinished == false)
    }
}
