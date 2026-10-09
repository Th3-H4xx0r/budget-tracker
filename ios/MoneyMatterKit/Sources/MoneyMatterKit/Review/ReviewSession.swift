import Foundation
import Observation

/// The decisions a card can get in the review stack.
public enum ReviewDecision: Sendable, Hashable, CaseIterable {
    case reviewed
    case checkLater
    case fraud

    public var action: ReviewAction {
        switch self {
        case .reviewed: .reviewed
        case .checkLater: .checkLater
        case .fraud: .fraud
        }
    }
}

/// One decided card, kept for undo.
public struct ReviewHistoryEntry: Sendable, Hashable, Identifiable {
    /// Unique per decision, so the same transaction decided twice is two entries.
    public let id: Int
    public let transaction: Transaction
    public let decision: ReviewDecision
}

public enum ReviewSubmitErrorKind: Sendable, Hashable {
    case action
    case undo
}

/// State for one pass through the review card stack, ported from the web
/// `use-review-session.ts`. The network is injected, so it runs without a view.
///
/// - Actions advance immediately; the write runs in the background. Writes are chained so
///   an action and its undo reach the server in the order the user made them.
/// - A failed action puts its card back at the front of the queue.
/// - Undo pops the last action and sends `unreviewed`, which also clears a deferral the row
///   carried from an earlier session.
/// - Pages are always requested from offset 0 and filtered by every id this session has
///   seen. Acting on a row moves it out of (or to the back of) the server queue, so a running
///   offset would skip rows; filtering also keeps rows deferred during the session from
///   coming back.
/// - A failed background page load is reported once and retried on the next action.
@MainActor
@Observable
public final class ReviewSession {
    public typealias FetchPage = @Sendable (_ offset: Int, _ limit: Int) async throws -> [Transaction]
    public typealias SubmitAction = @Sendable (_ transactionIds: [String], _ action: ReviewAction) async throws -> Void

    public static let defaultPageSize = 50
    /// `GET /transactions/review` caps `limit` at 100. A larger page size would make every
    /// page look short, which reads as the end of the queue.
    public static let maxPageSize = 100
    /// The next page is requested while this many cards are still ahead, so advancing
    /// never waits on the network.
    public static let defaultPrefetchThreshold = 10

    public private(set) var queue: [Transaction] = []
    public private(set) var history: [ReviewHistoryEntry] = []
    public private(set) var hasMore = false
    public private(set) var isFetching = false
    public private(set) var loadError: APIError?
    public private(set) var hasStarted = false
    /// Writes that landed during this session.
    public private(set) var submittedCount = 0
    /// Writes queued or in flight, from this session or an earlier one.
    public private(set) var pendingWriteCount = 0
    private var initialTotal = 0

    /// Called after each successful write.
    @ObservationIgnored public var onSubmitSuccess: (() -> Void)?
    /// Called when a write fails; the card is already back in play.
    @ObservationIgnored public var onSubmitError: ((_ error: APIError, _ kind: ReviewSubmitErrorKind, _ transaction: Transaction) -> Void)?
    /// A page load failed while cards were still on screen, so no error state is visible yet.
    @ObservationIgnored public var onLoadMoreError: ((_ error: APIError) -> Void)?

    @ObservationIgnored private let fetchPage: FetchPage
    @ObservationIgnored private let submitAction: SubmitAction
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private let prefetchThreshold: Int

    @ObservationIgnored private var seenIDs = Set<String>()
    /// Bumped on every `start()`, so async results from an earlier session are dropped.
    @ObservationIgnored private var sessionToken = 0
    @ObservationIgnored private var submitChain: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var writeSequence = 0
    @ObservationIgnored private var entrySequence = 0
    /// Latest write per transaction: a failed write that is no longer the latest for its
    /// card was superseded by a newer decision, which wins.
    @ObservationIgnored private var latestWriteByTransaction: [String: Int] = [:]
    /// One notice per run of failed background loads, not one per retry.
    @ObservationIgnored private var isLoadMoreErrorReported = false

    public init(
        pageSize: Int = ReviewSession.defaultPageSize,
        prefetchThreshold: Int = ReviewSession.defaultPrefetchThreshold,
        fetchPage: @escaping FetchPage,
        submitAction: @escaping SubmitAction
    ) {
        self.pageSize = min(max(1, pageSize), Self.maxPageSize)
        self.prefetchThreshold = prefetchThreshold
        self.fetchPage = fetchPage
        self.submitAction = submitAction
    }

    // MARK: Derived state

    /// The card on screen.
    public var current: Transaction? { queue.first }

    public var processedCount: Int { history.count }

    /// Cards saved for later in this session ("{count} saved for later").
    public var deferredCount: Int { history.filter { $0.decision == .checkLater }.count }

    public var total: Int {
        let known = history.count + queue.count
        return hasMore ? max(initialTotal, known) : known
    }

    /// 1-based index of the card on screen; equals `total` once everything is processed.
    public var position: Int { current == nil ? processedCount : processedCount + 1 }

    public var canUndo: Bool { !history.isEmpty }

    /// Also waits for every write to settle, so a last-card failure that puts the card
    /// back is never hidden behind the end state.
    public var isFinished: Bool {
        hasStarted && current == nil && !hasMore && !isFetching && loadError == nil && pendingWriteCount == 0
    }

    // MARK: Commands

    /// Starts a fresh pass. `total` is the expected count (e.g. the summary's
    /// `unreviewedCount`); without it the total grows with the loaded cards.
    public func start(total expectedTotal: Int? = nil) async {
        sessionToken += 1
        let token = sessionToken
        seenIDs.removeAll()
        queue = []
        history = []
        initialTotal = expectedTotal ?? 0
        hasMore = true
        isFetching = false
        loadError = nil
        submittedCount = 0
        isLoadMoreErrorReported = false
        hasStarted = true
        loadTask = nil

        // Writes from an earlier session may still be in flight; loading before they land
        // would bring back cards the user already decided.
        await whenSettled()
        guard token == sessionToken else { return }
        if Task.isCancelled {
            resetAfterCancellation(token: token)
            return
        }

        if let loadToken = beginLoad() {
            await performLoad(token: loadToken)
        }
    }

    /// Decides the card on screen. With `expectedID`, does nothing (and returns false) when
    /// a different card is now in front, e.g. a rolled-back card returned during an animation.
    @discardableResult
    public func act(_ decision: ReviewDecision, expectedID: String? = nil) -> Bool {
        guard let transaction = queue.first else { return false }
        if let expectedID, transaction.id != expectedID { return false }

        let token = sessionToken
        entrySequence += 1
        let entry = ReviewHistoryEntry(id: entrySequence, transaction: transaction, decision: decision)
        queue.removeFirst()
        history.append(entry)

        enqueueSubmit(transactionID: transaction.id, action: decision.action) { [weak self] error, _ in
            guard let self else { return }
            // Already undone, or a new session started: the card is back in play either way.
            if token == self.sessionToken, self.history.contains(where: { $0.id == entry.id }) {
                self.history.removeAll { $0.id == entry.id }
                self.queue.insert(transaction, at: 0)
            }
            self.onSubmitError?(error, .action, transaction)
        }

        maybePrefetch()
        return true
    }

    /// Undoes the last decision and returns it, or nil when there is nothing to undo.
    @discardableResult
    public func undo() -> ReviewHistoryEntry? {
        guard let entry = history.last else { return nil }

        let token = sessionToken
        history.removeLast()
        queue.insert(entry.transaction, at: 0)

        enqueueSubmit(transactionID: entry.transaction.id, action: .unreviewed) { [weak self] error, isSuperseded in
            guard let self else { return }
            // The user already decided the card again; that newer write wins and the failed
            // undo no longer matters to them.
            if isSuperseded { return }

            if token == self.sessionToken, let index = self.queue.firstIndex(where: { $0.id == entry.transaction.id }) {
                self.queue.remove(at: index)
                self.history.append(entry)
            }
            self.onSubmitError?(error, .undo, entry.transaction)
        }

        return entry
    }

    /// Retries a failed page load.
    public func retry() async {
        guard let token = beginLoad() else { return }
        await performLoad(token: token)
    }

    /// Resolves once every queued write has finished (succeeded or rolled back).
    public func whenSettled() async {
        await submitChain?.value
    }

    /// Resolves once the in-flight background page load, if any, has finished.
    public func whenLoaded() async {
        await loadTask?.value
    }

    // MARK: Loading

    /// Marks a load as started and returns its session token, or nil when a load is
    /// already running or there is nothing more to load.
    private func beginLoad() -> Int? {
        guard !isFetching, hasMore else { return nil }
        isFetching = true
        loadError = nil
        return sessionToken
    }

    private func performLoad(token: Int) async {
        defer {
            if token == sessionToken { isFetching = false }
        }
        do {
            var offset = 0
            // A full page made only of rows this session already holds says nothing about
            // what lies past it, so keep walking until something new or a short page shows up.
            while true {
                let page = try await fetchPage(offset, pageSize)
                guard token == sessionToken else { return }

                let fresh = page.filter { !seenIDs.contains($0.id) }
                fresh.forEach { seenIDs.insert($0.id) }
                if page.count < pageSize { hasMore = false }

                if !fresh.isEmpty || !hasMore {
                    queue.append(contentsOf: fresh)
                    isLoadMoreErrorReported = false
                    return
                }
                offset += pageSize
            }
        } catch {
            guard token == sessionToken else { return }
            let apiError = APIError(error)
            // A cancelled load (the view went away mid-start) is not a failure to report.
            if Task.isCancelled || error is CancellationError || apiError.isCancellation {
                resetAfterCancellation(token: token)
                return
            }
            loadError = apiError
            // With an empty queue the stack shows its own error state; only a background
            // load that fails behind visible cards needs a separate notice.
            if !queue.isEmpty, !isLoadMoreErrorReported {
                isLoadMoreErrorReported = true
                onLoadMoreError?(apiError)
            }
        }
    }

    /// Leaves the session ready for a fresh `start()` when nothing was shown yet; otherwise
    /// keeps the cards and lets the next action retry the load.
    private func resetAfterCancellation(token: Int) {
        guard token == sessionToken else { return }
        loadError = nil
        if queue.isEmpty, history.isEmpty {
            hasStarted = false
        }
    }

    /// Runs after every action, so a load that failed earlier is retried on the next one.
    private func maybePrefetch() {
        guard queue.count <= prefetchThreshold, let token = beginLoad() else { return }
        loadTask = Task { await self.performLoad(token: token) }
    }

    // MARK: Writes

    private func enqueueSubmit(
        transactionID: String,
        action: ReviewAction,
        onError: @escaping (_ error: APIError, _ isSuperseded: Bool) -> Void
    ) {
        writeSequence += 1
        let sequence = writeSequence
        let token = sessionToken
        latestWriteByTransaction[transactionID] = sequence

        let previous = submitChain
        let submitAction = submitAction
        pendingWriteCount += 1
        submitChain = Task { [weak self] in
            await previous?.value
            do {
                try await submitAction([transactionID], action)
            } catch {
                guard let self else { return }
                self.pendingWriteCount -= 1
                onError(APIError(error), self.latestWriteByTransaction[transactionID] != sequence)
                return
            }
            guard let self else { return }
            self.pendingWriteCount -= 1
            // A write left over from an earlier session does not count toward this one.
            if token == self.sessionToken { self.submittedCount += 1 }
            self.onSubmitSuccess?()
        }
    }
}
