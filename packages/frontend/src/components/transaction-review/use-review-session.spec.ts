import { captureException } from '@/lib/sentry';
import { TRANSACTION_REVIEW_ACTION, type TransactionModel } from '@bt/shared/types';
import { flushPromises } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { useReviewSession } from './use-review-session';

vi.mock('@/lib/sentry', () => ({ captureException: vi.fn() }));

const mockCaptureException = vi.mocked(captureException);

beforeEach(() => {
  mockCaptureException.mockClear();
});

const makeTx = ({ id }: { id: string }): TransactionModel => ({ id }) as unknown as TransactionModel;

const makeTxs = ({ prefix, count }: { prefix: string; count: number }) =>
  Array.from({ length: count }, (_, index) => makeTx({ id: `${prefix}-${index + 1}` }));

/**
 * A fake server queue: `fetchPage` slices whatever `rows` holds at call time, so a test
 * can mimic rows leaving the queue (reviewed) or new rows arriving (sync) between pages.
 */
const createServer = ({ rows }: { rows: TransactionModel[] }) => {
  const server = { rows: [...rows] };
  const fetchPage = vi.fn(async ({ offset, limit }: { offset: number; limit: number }) =>
    server.rows.slice(offset, offset + limit),
  );
  return { server, fetchPage };
};

type SubmitAction = (params: { transactionIds: string[]; action: TRANSACTION_REVIEW_ACTION }) => Promise<unknown>;

const setup = ({
  rows,
  pageSize = 5,
  prefetchThreshold = 2,
  submitAction = vi.fn(async () => ({ updatedCount: 1 })),
  onSubmitSuccess = vi.fn(),
  onSubmitError = vi.fn(),
}: {
  rows: TransactionModel[];
  pageSize?: number;
  prefetchThreshold?: number;
  submitAction?: SubmitAction;
  onSubmitSuccess?: () => void;
  onSubmitError?: () => void;
}) => {
  const { server, fetchPage } = createServer({ rows });
  const onLoadMoreError = vi.fn();
  const session = useReviewSession({
    fetchPage,
    submitAction,
    onSubmitError,
    onSubmitSuccess,
    onLoadMoreError,
    pageSize,
    prefetchThreshold,
  });
  return { session, server, fetchPage, submitAction, onSubmitError, onSubmitSuccess, onLoadMoreError };
};

/** A write that stays pending until the test releases it. */
const createDeferredWrite = () => {
  let release: () => void = () => {};
  const promise = new Promise<void>((resolve) => {
    release = resolve;
  });
  return { promise, release: () => release() };
};

const currentId = ({ session }: { session: ReturnType<typeof useReviewSession> }) => session.current.value?.id;

describe('useReviewSession', () => {
  describe('advance', () => {
    it('loads the first page and shows the first card as 1 of total', async () => {
      const { session, fetchPage } = setup({ rows: makeTxs({ prefix: 'tx', count: 3 }) });

      await session.start({ total: 3 });

      expect(fetchPage).toHaveBeenCalledWith({ offset: 0, limit: 5 });
      expect(currentId({ session })).toBe('tx-1');
      expect(session.position.value).toBe(1);
      expect(session.total.value).toBe(3);
      expect(session.isFinished.value).toBe(false);
    });

    it('advances immediately and submits the action in the background', async () => {
      const { session, submitAction, onSubmitSuccess } = setup({ rows: makeTxs({ prefix: 'tx', count: 3 }) });
      await session.start({ total: 3 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });

      expect(currentId({ session })).toBe('tx-2');
      expect(session.position.value).toBe(2);

      await session.whenSettled();
      expect(submitAction).toHaveBeenCalledWith({
        transactionIds: ['tx-1'],
        action: TRANSACTION_REVIEW_ACTION.reviewed,
      });
      expect(onSubmitSuccess).toHaveBeenCalledTimes(1);
      expect(session.submittedCount.value).toBe(1);
    });

    it('sends writes in the order the user made them, even when the first is slow', async () => {
      const calls: string[] = [];
      let releaseFirst: () => void = () => {};
      const submitAction = vi.fn(({ action }: { action: TRANSACTION_REVIEW_ACTION }) => {
        calls.push(`start:${action}`);
        if (calls.length === 1) {
          return new Promise<void>((resolve) => {
            releaseFirst = () => {
              calls.push(`end:${action}`);
              resolve();
            };
          });
        }
        calls.push(`end:${action}`);
        return Promise.resolve();
      });
      const { session } = setup({ rows: makeTxs({ prefix: 'tx', count: 3 }), submitAction });
      await session.start({ total: 3 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.fraud });
      session.undo();
      await flushPromises();
      releaseFirst();
      await session.whenSettled();

      expect(calls).toEqual([
        `start:${TRANSACTION_REVIEW_ACTION.fraud}`,
        `end:${TRANSACTION_REVIEW_ACTION.fraud}`,
        `start:${TRANSACTION_REVIEW_ACTION.unreviewed}`,
        `end:${TRANSACTION_REVIEW_ACTION.unreviewed}`,
      ]);
    });

    it('reaches the finished state after the last card', async () => {
      const { session } = setup({ rows: makeTxs({ prefix: 'tx', count: 2 }) });
      await session.start({ total: 2 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.act({ action: TRANSACTION_REVIEW_ACTION.fraud });

      expect(session.current.value).toBeNull();
      expect(session.isFinished.value).toBe(true);
      expect(session.position.value).toBe(2);
      expect(session.total.value).toBe(2);
    });

    it('finishes straight away when the queue is empty', async () => {
      const { session } = setup({ rows: [] });

      await session.start({ total: 0 });

      expect(session.current.value).toBeNull();
      expect(session.isFinished.value).toBe(true);
    });

    it('ignores actions when there is no card', async () => {
      const { session, submitAction } = setup({ rows: [] });
      await session.start({ total: 0 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      await session.whenSettled();

      expect(submitAction).not.toHaveBeenCalled();
      expect(session.processedCount.value).toBe(0);
    });
  });

  describe('paging', () => {
    it('requests the next page before the user reaches the end', async () => {
      const { session, server, fetchPage } = setup({
        rows: makeTxs({ prefix: 'tx', count: 8 }),
        pageSize: 5,
        prefetchThreshold: 2,
      });
      await session.start({ total: 8 });
      expect(session.queue.value).toHaveLength(5);

      // Reviewed rows leave the server queue as their PUT lands.
      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      expect(fetchPage).toHaveBeenCalledTimes(1);

      server.rows = server.rows.slice(2);
      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      await flushPromises();

      expect(fetchPage).toHaveBeenCalledTimes(2);
      expect(fetchPage).toHaveBeenLastCalledWith({ offset: 0, limit: 5 });
      // The page is tx-3..tx-7: tx-3's write is still pending and tx-4/tx-5 are already
      // queued, so only tx-6 and tx-7 are new.
      expect(session.queue.value.map((tx) => tx.id)).toEqual(['tx-4', 'tx-5', 'tx-6', 'tx-7']);
      expect(session.hasMore.value).toBe(true);
    });

    it('stops paging after a short page', async () => {
      const { session, server, fetchPage } = setup({
        rows: makeTxs({ prefix: 'tx', count: 6 }),
        pageSize: 5,
        prefetchThreshold: 2,
      });
      await session.start({ total: 6 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      server.rows = server.rows.slice(3);
      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      await flushPromises();

      expect(session.queue.value.map((tx) => tx.id)).toEqual(['tx-4', 'tx-5', 'tx-6']);
      expect(session.hasMore.value).toBe(false);

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      await flushPromises();
      expect(fetchPage).toHaveBeenCalledTimes(2);
    });

    it('walks past a full page of rows the session already holds', async () => {
      const deferredInSession = makeTxs({ prefix: 'deferred', count: 3 });
      const later = makeTxs({ prefix: 'later', count: 2 });
      const { session, server, fetchPage } = setup({
        rows: deferredInSession,
        pageSize: 3,
        prefetchThreshold: 0,
      });
      await session.start({ total: 3 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.checkLater });
      session.act({ action: TRANSACTION_REVIEW_ACTION.checkLater });
      // A sync lands rows that sort after the deferred ones on the server.
      server.rows = [...deferredInSession, ...later];
      session.act({ action: TRANSACTION_REVIEW_ACTION.checkLater });
      await flushPromises();

      expect(fetchPage).toHaveBeenNthCalledWith(2, { offset: 0, limit: 3 });
      expect(fetchPage).toHaveBeenNthCalledWith(3, { offset: 3, limit: 3 });
      expect(session.queue.value.map((tx) => tx.id)).toEqual(['later-1', 'later-2']);
    });

    it('keeps a failed page load visible and retries on demand', async () => {
      const rows = makeTxs({ prefix: 'tx', count: 2 });
      const fetchPage = vi
        .fn()
        .mockRejectedValueOnce(new Error('offline'))
        .mockImplementation(async () => rows);
      const onLoadMoreError = vi.fn();
      const session = useReviewSession({ fetchPage, submitAction: vi.fn(), onLoadMoreError, pageSize: 5 });

      await session.start({ total: 2 });
      expect(session.loadError.value).toBeInstanceOf(Error);
      expect(session.isFinished.value).toBe(false);
      // The empty stack shows its own error state, so no separate notice goes out.
      expect(onLoadMoreError).not.toHaveBeenCalled();

      await session.retry();
      expect(session.loadError.value).toBeNull();
      expect(currentId({ session })).toBe('tx-1');
    });

    it('reports a failed background load once and retries it on the next actions', async () => {
      const firstPage = makeTxs({ prefix: 'tx', count: 4 });
      const laterPage = makeTxs({ prefix: 'later', count: 2 });
      const fetchPage = vi
        .fn()
        .mockResolvedValueOnce(firstPage)
        .mockRejectedValueOnce(new Error('offline'))
        .mockRejectedValueOnce(new Error('offline'))
        .mockResolvedValueOnce(laterPage);
      const onLoadMoreError = vi.fn();
      const session = useReviewSession({
        fetchPage,
        submitAction: vi.fn(async () => undefined),
        onLoadMoreError,
        pageSize: 4,
        prefetchThreshold: 2,
      });
      await session.start({ total: 6 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      await flushPromises();
      expect(fetchPage).toHaveBeenCalledTimes(2);
      expect(onLoadMoreError).toHaveBeenCalledTimes(1);

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      await flushPromises();
      expect(fetchPage).toHaveBeenCalledTimes(3);
      expect(onLoadMoreError).toHaveBeenCalledTimes(1);

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      await flushPromises();
      expect(fetchPage).toHaveBeenCalledTimes(4);
      expect(session.loadError.value).toBeNull();
      expect(session.queue.value.map((tx) => tx.id)).toEqual(['later-1', 'later-2']);
    });

    it('falls back to the loaded count when the total is unknown', async () => {
      const { session } = setup({ rows: makeTxs({ prefix: 'tx', count: 5 }), pageSize: 5 });

      await session.start();

      expect(session.total.value).toBe(5);
      expect(session.position.value).toBe(1);
    });

    it('grows the total when more rows exist than the summary reported', async () => {
      const { session } = setup({ rows: makeTxs({ prefix: 'tx', count: 4 }), pageSize: 5 });

      await session.start({ total: 2 });

      expect(session.total.value).toBe(4);
    });
  });

  describe('defer', () => {
    it('counts rows saved for later', async () => {
      const { session, submitAction } = setup({ rows: makeTxs({ prefix: 'tx', count: 3 }) });
      await session.start({ total: 3 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.checkLater });
      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.act({ action: TRANSACTION_REVIEW_ACTION.checkLater });
      await session.whenSettled();

      expect(session.deferredCount.value).toBe(2);
      expect(session.isFinished.value).toBe(true);
      expect(submitAction).toHaveBeenCalledWith({
        transactionIds: ['tx-1'],
        action: TRANSACTION_REVIEW_ACTION.checkLater,
      });
    });

    it('does not bring a deferred row back when the server returns it at the back of the queue', async () => {
      const rows = makeTxs({ prefix: 'tx', count: 3 });
      const { session, server } = setup({ rows, pageSize: 3, prefetchThreshold: 1 });
      await session.start({ total: 3 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.checkLater });
      // The deferral moved tx-1 behind every fresh row.
      server.rows = [rows[1]!, rows[2]!, rows[0]!];
      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      await flushPromises();

      expect(session.queue.value.map((tx) => tx.id)).toEqual(['tx-3']);
      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      expect(session.isFinished.value).toBe(true);
    });
  });

  describe('undo', () => {
    it('returns the last card to the front and sends `unreviewed`', async () => {
      const { session, submitAction } = setup({ rows: makeTxs({ prefix: 'tx', count: 3 }) });
      await session.start({ total: 3 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.fraud });
      const undone = session.undo();

      expect(undone?.transaction.id).toBe('tx-1');
      expect(currentId({ session })).toBe('tx-1');
      expect(session.position.value).toBe(1);
      expect(session.canUndo.value).toBe(false);

      await session.whenSettled();
      expect(submitAction).toHaveBeenLastCalledWith({
        transactionIds: ['tx-1'],
        action: TRANSACTION_REVIEW_ACTION.unreviewed,
      });
    });

    it('undoes repeatedly, newest action first', async () => {
      const { session } = setup({ rows: makeTxs({ prefix: 'tx', count: 3 }) });
      await session.start({ total: 3 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.act({ action: TRANSACTION_REVIEW_ACTION.checkLater });
      session.act({ action: TRANSACTION_REVIEW_ACTION.fraud });

      expect(session.undo()?.transaction.id).toBe('tx-3');
      expect(session.undo()?.transaction.id).toBe('tx-2');
      expect(session.undo()?.transaction.id).toBe('tx-1');
      expect(session.undo()).toBeNull();
      expect(session.queue.value.map((tx) => tx.id)).toEqual(['tx-1', 'tx-2', 'tx-3']);
      expect(session.deferredCount.value).toBe(0);
    });

    it('drops an undone deferral from the saved-for-later tally', async () => {
      const { session } = setup({ rows: makeTxs({ prefix: 'tx', count: 2 }) });
      await session.start({ total: 2 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.checkLater });
      expect(session.deferredCount.value).toBe(1);

      session.undo();
      expect(session.deferredCount.value).toBe(0);
    });

    it('restores the action when the undo write fails', async () => {
      const submitAction = vi.fn().mockResolvedValueOnce({ updatedCount: 1 }).mockRejectedValueOnce(new Error('boom'));
      const { session, onSubmitError } = setup({ rows: makeTxs({ prefix: 'tx', count: 2 }), submitAction });
      await session.start({ total: 2 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.undo();
      await session.whenSettled();

      expect(currentId({ session })).toBe('tx-2');
      expect(session.processedCount.value).toBe(1);
      expect(onSubmitError).toHaveBeenCalledWith(
        expect.objectContaining({ kind: 'undo', transaction: expect.objectContaining({ id: 'tx-1' }) }),
      );
    });

    it('restores a failed undo even when another undone card sits in front of it', async () => {
      const submitAction = vi
        .fn()
        .mockResolvedValueOnce({ updatedCount: 1 })
        .mockResolvedValueOnce({ updatedCount: 1 })
        .mockRejectedValueOnce(new Error('boom'))
        .mockResolvedValue({ updatedCount: 1 });
      const { session, onSubmitError } = setup({ rows: makeTxs({ prefix: 'tx', count: 3 }), submitAction });
      await session.start({ total: 3 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.act({ action: TRANSACTION_REVIEW_ACTION.fraud });
      // Undo tx-2 (this write fails), then undo tx-1, which lands in front of it.
      session.undo();
      session.undo();
      await session.whenSettled();

      expect(session.queue.value.map((tx) => tx.id)).toEqual(['tx-1', 'tx-3']);
      expect(session.processedCount.value).toBe(1);
      expect(session.undo()?.transaction.id).toBe('tx-2');
      expect(onSubmitError).toHaveBeenCalledTimes(1);
    });

    it('stays silent about a failed undo once the user decided the card again', async () => {
      const submitAction = vi
        .fn()
        .mockResolvedValueOnce({ updatedCount: 1 })
        .mockRejectedValueOnce(new Error('boom'))
        .mockResolvedValue({ updatedCount: 1 });
      const { session, onSubmitError } = setup({ rows: makeTxs({ prefix: 'tx', count: 2 }), submitAction });
      await session.start({ total: 2 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.undo();
      session.act({ action: TRANSACTION_REVIEW_ACTION.fraud });
      await session.whenSettled();

      expect(onSubmitError).not.toHaveBeenCalled();
      expect(currentId({ session })).toBe('tx-2');
      expect(session.processedCount.value).toBe(1);
      expect(submitAction).toHaveBeenLastCalledWith({
        transactionIds: ['tx-1'],
        action: TRANSACTION_REVIEW_ACTION.fraud,
      });
    });
  });

  describe('failure rollback', () => {
    it('puts the card back at the front and reports the error', async () => {
      const submitAction = vi.fn().mockRejectedValueOnce(new Error('boom'));
      const { session, onSubmitError } = setup({ rows: makeTxs({ prefix: 'tx', count: 3 }), submitAction });
      await session.start({ total: 3 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.checkLater });
      expect(currentId({ session })).toBe('tx-2');

      await session.whenSettled();

      expect(currentId({ session })).toBe('tx-1');
      expect(session.processedCount.value).toBe(0);
      expect(session.deferredCount.value).toBe(0);
      expect(session.submittedCount.value).toBe(0);
      expect(onSubmitError).toHaveBeenCalledWith(
        expect.objectContaining({ kind: 'action', transaction: expect.objectContaining({ id: 'tx-1' }) }),
      );
    });

    it('rolls back only the failed card when later actions succeed', async () => {
      const submitAction = vi.fn().mockRejectedValueOnce(new Error('boom')).mockResolvedValue({ updatedCount: 1 });
      const { session } = setup({ rows: makeTxs({ prefix: 'tx', count: 3 }), submitAction });
      await session.start({ total: 3 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.act({ action: TRANSACTION_REVIEW_ACTION.fraud });
      await session.whenSettled();

      expect(session.queue.value.map((tx) => tx.id)).toEqual(['tx-1', 'tx-3']);
      expect(session.processedCount.value).toBe(1);
      // Undo now targets the surviving action.
      expect(session.undo()?.transaction.id).toBe('tx-2');
    });

    it('leaves the queue alone when the failed action was already undone', async () => {
      const submitAction = vi.fn().mockRejectedValueOnce(new Error('boom')).mockResolvedValue({ updatedCount: 1 });
      const { session, onSubmitError } = setup({ rows: makeTxs({ prefix: 'tx', count: 2 }), submitAction });
      await session.start({ total: 2 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.undo();
      await session.whenSettled();

      expect(session.queue.value.map((tx) => tx.id)).toEqual(['tx-1', 'tx-2']);
      expect(onSubmitError).toHaveBeenCalledTimes(1);
    });
  });

  describe('restart', () => {
    it('starts a fresh session with empty history', async () => {
      const { session } = setup({ rows: makeTxs({ prefix: 'tx', count: 2 }) });
      await session.start({ total: 2 });
      session.act({ action: TRANSACTION_REVIEW_ACTION.checkLater });
      await session.whenSettled();

      await session.start({ total: 2 });

      expect(session.processedCount.value).toBe(0);
      expect(session.deferredCount.value).toBe(0);
      expect(session.submittedCount.value).toBe(0);
      expect(currentId({ session })).toBe('tx-1');
    });

    it('waits for pending writes before loading, so decided cards do not come back', async () => {
      const write = createDeferredWrite();
      const submitAction = vi.fn(() => write.promise);
      const { session, fetchPage, server } = setup({ rows: makeTxs({ prefix: 'tx', count: 2 }), submitAction });
      await session.start({ total: 2 });
      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });

      const restart = session.start({ total: 2 });
      await flushPromises();
      expect(fetchPage).toHaveBeenCalledTimes(1);

      // The write lands and tx-1 leaves the server queue before the reload runs.
      server.rows = server.rows.slice(1);
      write.release();
      await restart;

      expect(fetchPage).toHaveBeenCalledTimes(2);
      expect(session.queue.value.map((tx) => tx.id)).toEqual(['tx-2']);
    });
  });

  describe('write chain resilience', () => {
    it('keeps sending writes after the success callback throws', async () => {
      const onSubmitSuccess = vi.fn(() => {
        throw new Error('callback broke');
      });
      const { session, submitAction } = setup({ rows: makeTxs({ prefix: 'tx', count: 3 }), onSubmitSuccess });
      await session.start({ total: 3 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.act({ action: TRANSACTION_REVIEW_ACTION.fraud });
      await expect(session.whenSettled()).resolves.toBeUndefined();

      expect(submitAction).toHaveBeenCalledTimes(2);
      expect(session.submittedCount.value).toBe(2);
      expect(mockCaptureException).toHaveBeenCalledTimes(2);
    });

    it('keeps sending writes after the error callback throws', async () => {
      const submitAction = vi.fn().mockRejectedValueOnce(new Error('boom')).mockResolvedValue({ updatedCount: 1 });
      const onSubmitError = vi.fn(() => {
        throw new Error('callback broke');
      });
      const { session } = setup({ rows: makeTxs({ prefix: 'tx', count: 3 }), submitAction, onSubmitError });
      await session.start({ total: 3 });

      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      session.act({ action: TRANSACTION_REVIEW_ACTION.reviewed });
      await expect(session.whenSettled()).resolves.toBeUndefined();

      expect(submitAction).toHaveBeenCalledTimes(2);
      expect(session.submittedCount.value).toBe(1);
      // The failed card still went back to the front before the callback threw.
      expect(currentId({ session })).toBe('tx-1');
      expect(mockCaptureException).toHaveBeenCalledTimes(1);
    });
  });
});
