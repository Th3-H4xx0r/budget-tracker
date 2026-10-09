import { captureException } from '@/lib/sentry';
import { TRANSACTION_REVIEW_ACTION, type TransactionModel } from '@bt/shared/types';
import { computed, ref, shallowRef } from 'vue';

export type ReviewDecision =
  | TRANSACTION_REVIEW_ACTION.reviewed
  | TRANSACTION_REVIEW_ACTION.checkLater
  | TRANSACTION_REVIEW_ACTION.fraud;

interface ReviewHistoryEntry {
  transaction: TransactionModel;
  action: ReviewDecision;
}

type ReviewSubmitErrorKind = 'action' | 'undo';

const REVIEW_SESSION_PAGE_SIZE = 50;
// The next page is requested while this many cards are still ahead, so advancing
// never waits on the network.
const DEFAULT_PREFETCH_THRESHOLD = 10;

/**
 * State for one pass through the review card stack. Framework-light on purpose: it
 * only uses Vue refs, and the network is injected, so it runs without a component.
 *
 * - Actions advance immediately; the PUT runs in the background. Writes are chained so
 *   an action and its undo always reach the server in the order the user made them,
 *   and a throwing callback never stops later writes from going out.
 * - A failed action puts its card back at the front of the queue.
 * - Undo pops the last action and sends `unreviewed`, which also clears a deferral the
 *   row carried from an earlier session.
 * - Pages are always requested from offset 0 and filtered by every id this session has
 *   seen. Acting on a row moves it out of (or to the back of) the server queue, so a
 *   running offset would skip rows; filtering also keeps rows deferred during the
 *   session from coming back.
 * - A failed background page load is reported once and retried on the next action.
 */
export const useReviewSession = ({
  fetchPage,
  submitAction,
  onSubmitSuccess,
  onSubmitError,
  onLoadMoreError,
  pageSize = REVIEW_SESSION_PAGE_SIZE,
  prefetchThreshold = DEFAULT_PREFETCH_THRESHOLD,
}: {
  fetchPage: (params: { offset: number; limit: number }) => Promise<TransactionModel[]>;
  submitAction: (params: { transactionIds: string[]; action: TRANSACTION_REVIEW_ACTION }) => Promise<unknown>;
  onSubmitSuccess?: () => void;
  onSubmitError?: (params: { error: unknown; kind: ReviewSubmitErrorKind; transaction: TransactionModel }) => void;
  /** A page load failed while cards were still on screen, so no error state is visible yet. */
  onLoadMoreError?: (params: { error: unknown }) => void;
  pageSize?: number;
  prefetchThreshold?: number;
}) => {
  const queue = shallowRef<TransactionModel[]>([]);
  const history = shallowRef<ReviewHistoryEntry[]>([]);
  const initialTotal = ref(0);
  const hasMore = ref(false);
  const isFetching = ref(false);
  const loadError = ref<unknown>(null);
  const hasStarted = ref(false);
  const submittedCount = ref(0);

  const seenIds = new Set<string>();
  // Bumped on every start(), so async results from an earlier session are dropped.
  let sessionToken = 0;
  let submitChain: Promise<void> = Promise.resolve();
  let writeSequence = 0;
  // Latest write per transaction: a failed write that is no longer the latest one for
  // its card was superseded by a newer decision, which wins.
  const latestWriteByTransaction = new Map<string, number>();
  // One toast per run of failed background loads, not one per retry.
  let isLoadMoreErrorReported = false;

  const current = computed<TransactionModel | null>(() => queue.value[0] ?? null);
  const processedCount = computed(() => history.value.length);
  const deferredCount = computed(
    () => history.value.filter((entry) => entry.action === TRANSACTION_REVIEW_ACTION.checkLater).length,
  );
  const total = computed(() => {
    const known = history.value.length + queue.value.length;
    return hasMore.value ? Math.max(initialTotal.value, known) : known;
  });
  // 1-based index of the card on screen; equals `total` once everything is processed.
  const position = computed(() => (current.value ? processedCount.value + 1 : processedCount.value));
  const canUndo = computed(() => history.value.length > 0);
  const isFinished = computed(
    () => hasStarted.value && !current.value && !hasMore.value && !isFetching.value && !loadError.value,
  );

  const loadMore = async () => {
    if (isFetching.value || !hasMore.value) return;

    const token = sessionToken;
    isFetching.value = true;
    loadError.value = null;

    try {
      let offset = 0;
      // A full page made only of rows this session already holds says nothing about
      // what lies past it, so keep walking until something new or a short page shows up.
      for (;;) {
        const page = await fetchPage({ offset, limit: pageSize });
        if (token !== sessionToken) return;

        const fresh = page.filter((tx) => !seenIds.has(tx.id));
        fresh.forEach((tx) => seenIds.add(tx.id));
        if (page.length < pageSize) hasMore.value = false;

        if (fresh.length > 0 || !hasMore.value) {
          queue.value = [...queue.value, ...fresh];
          isLoadMoreErrorReported = false;
          return;
        }
        offset += pageSize;
      }
    } catch (error) {
      if (token !== sessionToken) return;
      loadError.value = error;
      // With an empty queue the dialog shows its own error state; only a background
      // load that fails behind visible cards needs a separate notice.
      if (queue.value.length > 0 && !isLoadMoreErrorReported) {
        isLoadMoreErrorReported = true;
        onLoadMoreError?.({ error });
      }
    } finally {
      if (token === sessionToken) isFetching.value = false;
    }
  };

  // Runs after every action, so a load that failed earlier is retried on the next one.
  const maybePrefetch = () => {
    if (queue.value.length > prefetchThreshold) return;
    if (!hasMore.value || isFetching.value) return;
    void loadMore();
  };

  const enqueueSubmit = ({
    transactionId,
    action,
    onError,
  }: {
    transactionId: string;
    action: TRANSACTION_REVIEW_ACTION;
    onError: (params: { error: unknown; isSuperseded: boolean }) => void;
  }) => {
    writeSequence += 1;
    const sequence = writeSequence;
    const token = sessionToken;
    latestWriteByTransaction.set(transactionId, sequence);

    submitChain = submitChain
      .then(async () => {
        try {
          await submitAction({ transactionIds: [transactionId], action });
        } catch (error) {
          try {
            onError({ error, isSuperseded: latestWriteByTransaction.get(transactionId) !== sequence });
          } catch (callbackError) {
            captureException({ error: callbackError, context: { flow: 'transactionReviewSubmitError' } });
          }
          return;
        }

        // A write left over from an earlier session does not count toward this one.
        if (token === sessionToken) submittedCount.value += 1;
        onSubmitSuccess?.();
      })
      // A throwing success callback must not leave the chain rejected: every later
      // write would then be skipped without a word.
      .catch((callbackError) => {
        captureException({ error: callbackError, context: { flow: 'transactionReviewSubmitSuccess' } });
      });
  };

  /** Resolves once every queued write has finished (succeeded or rolled back). Never rejects. */
  const whenSettled = () => submitChain;

  const start = async ({ total: expectedTotal }: { total?: number } = {}) => {
    sessionToken += 1;
    const token = sessionToken;
    seenIds.clear();
    queue.value = [];
    history.value = [];
    // Unknown totals fall back to the count of loaded cards.
    initialTotal.value = expectedTotal ?? 0;
    hasMore.value = true;
    isFetching.value = false;
    loadError.value = null;
    submittedCount.value = 0;
    isLoadMoreErrorReported = false;
    hasStarted.value = true;

    // Writes from an earlier session may still be in flight; loading before they land
    // would bring back cards the user already decided.
    await whenSettled();
    if (token !== sessionToken) return;

    await loadMore();
  };

  const act = ({ action }: { action: ReviewDecision }) => {
    const [transaction, ...rest] = queue.value;
    if (!transaction) return;

    const token = sessionToken;
    const entry: ReviewHistoryEntry = { transaction, action };
    queue.value = rest;
    history.value = [...history.value, entry];

    enqueueSubmit({
      transactionId: transaction.id,
      action,
      onError: ({ error }) => {
        // Already undone, or a new session started: the card is back in play either way.
        if (token === sessionToken && history.value.includes(entry)) {
          history.value = history.value.filter((item) => item !== entry);
          queue.value = [transaction, ...queue.value];
        }
        onSubmitError?.({ error, kind: 'action', transaction });
      },
    });

    maybePrefetch();
  };

  const undo = () => {
    const entry = history.value.at(-1);
    if (!entry) return null;

    const token = sessionToken;
    history.value = history.value.slice(0, -1);
    queue.value = [entry.transaction, ...queue.value];

    enqueueSubmit({
      transactionId: entry.transaction.id,
      action: TRANSACTION_REVIEW_ACTION.unreviewed,
      onError: ({ error, isSuperseded }) => {
        // The user already decided the card again; that newer write wins and the
        // failed undo no longer matters to them.
        if (isSuperseded) return;

        if (token === sessionToken && queue.value.includes(entry.transaction)) {
          queue.value = queue.value.filter((tx) => tx !== entry.transaction);
          history.value = [...history.value, entry];
        }
        onSubmitError?.({ error, kind: 'undo', transaction: entry.transaction });
      },
    });

    return entry;
  };

  const retry = () => loadMore();

  return {
    queue,
    current,
    position,
    total,
    processedCount,
    deferredCount,
    canUndo,
    hasMore,
    isFetching,
    isFinished,
    loadError,
    submittedCount,
    start,
    act,
    undo,
    retry,
    whenSettled,
  };
};
