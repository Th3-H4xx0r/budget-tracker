import {
  ACCOUNT_TYPES,
  AccountOptionValue,
  CategoryOptionValue,
  CurrencyOptionValue,
  TRANSACTION_REVIEW_ACTION,
  TRANSACTION_REVIEW_STATUS,
  TransactionTypeOptionValue,
} from '@bt/shared/types';
import type { ColumnMappingConfig } from '@bt/shared/types';
import { describe, expect, it } from '@jest/globals';
import { ERROR_CODES } from '@js/errors';
import * as helpers from '@tests/helpers';
import { expectCsvImportCompleted, waitForCsvImportCompletion } from '@tests/helpers/import-export';
import type { MonobankTransactionOverride } from '@tests/helpers/monobank';
import { getMonobankTransactionsMock } from '@tests/mocks/monobank/mock-api';
import { randomUUID } from 'crypto';
import { addDays, format, startOfDay, subDays } from 'date-fns';

const { unreviewed, reviewed, fraud, not_required: notRequired } = TRANSACTION_REVIEW_STATUS;

const CSV_ACCOUNT = 'CSV Account';
const CSV_HEADER = 'Date,Amount,Description,Category,Account,Currency,Type';

const COLUMN_MAPPING: ColumnMappingConfig = {
  date: 'Date',
  dateFieldOrder: 'month-first',
  amount: 'Amount',
  description: 'Description',
  category: { option: CategoryOptionValue.mapDataSourceColumn, columnName: 'Category' },
  currency: { option: CurrencyOptionValue.dataSourceColumn, columnName: 'Currency' },
  transactionType: {
    option: TransactionTypeOptionValue.dataSourceColumn,
    columnName: 'Type',
    incomeValues: ['income'],
    expenseValues: ['expense'],
  },
  account: { option: AccountOptionValue.dataSourceColumn, columnName: 'Account' },
};

/**
 * Imports one expense per entry of `daysAgo` into a fresh system account through the CSV
 * importer and returns the created ids in input order. Row `i` costs `(i + 1) * 10`, which is
 * how ids are matched back to their rows.
 */
const importExpenses = async ({ daysAgo }: { daysAgo: number[] }): Promise<string[]> => {
  const account = await helpers.createAccount({ raw: true });
  const today = startOfDay(new Date());

  const lines = daysAgo.map((days, index) =>
    [
      format(subDays(today, days), 'yyyy-MM-dd'),
      `${(index + 1) * 10}.00`,
      `Imported row ${index + 1}`,
      '',
      CSV_ACCOUNT,
      account.currencyCode,
      'expense',
    ].join(','),
  );

  const { jobId } = await helpers.executeImport({
    payload: {
      fileContent: [CSV_HEADER, ...lines].join('\n'),
      delimiter: ',',
      columnMapping: COLUMN_MAPPING,
      accountMapping: { [CSV_ACCOUNT]: { action: 'link-existing', accountId: account.id } },
      categoryMapping: {},
      skipDuplicateIndices: [],
    },
    raw: true,
  });

  const progress = await waitForCsvImportCompletion({ jobId });
  expectCsvImportCompleted(progress);
  expect(progress.summary.newTransactionIds).toHaveLength(daysAgo.length);

  const rows = await helpers.getTransactionsByIds({ ids: progress.summary.newTransactionIds, raw: true });

  return daysAgo.map((_, index) => rows.find((row) => row.amount === (index + 1) * 10)!.id);
};

const pollUntil = async <T>({ read, done }: { read: () => Promise<T>; done: (value: T) => boolean }) => {
  let value = await read();
  for (let attempt = 0; attempt < 20 && !done(value); attempt += 1) {
    await helpers.sleep(300);
    value = await read();
  }
  return value;
};

/**
 * Connects exactly one Monobank account and waits for its initial sync. The statement mock
 * answers every account, so connecting all of them would sync each row once per account.
 */
const syncOneMonobankAccount = async ({ transactions }: { transactions: MonobankTransactionOverride[] }) => {
  const { connectionId } = await helpers.monobank.pair();

  global.mswMockServer.use(
    getMonobankTransactionsMock({
      response: transactions.map((transaction) => helpers.monobank.buildTransaction(transaction)),
    }),
  );

  const { accounts } = await helpers.bankDataProviders.listExternalAccounts({ connectionId, raw: true });
  const { syncedAccounts } = await helpers.bankDataProviders.connectSelectedAccounts({
    connectionId,
    accountExternalIds: [accounts[0]!.externalId],
    raw: true,
  });
  const accountId = syncedAccounts[0]!.id;

  const rows = await pollUntil({
    read: () => helpers.getTransactions({ accountIds: [accountId], raw: true }),
    done: (value) => value.length === transactions.length,
  });
  expect(rows).toHaveLength(transactions.length);

  return { connectionId, accountId, rowIds: rows.map((row) => row.id) };
};

const listIds = async ({ status }: { status: TRANSACTION_REVIEW_STATUS }) =>
  (await helpers.getReviewTransactions({ status, raw: true })).map((row) => row.id);

const applyAction = ({ ids, action }: { ids: string[]; action: TRANSACTION_REVIEW_ACTION }) =>
  helpers.updateReviewStatus({ payload: { transactionIds: ids, action }, raw: true });

const getById = async ({ id }: { id: string }) => (await helpers.getTransactionById({ id, raw: true }))!;

describe('Transaction review', () => {
  describe('empty state', () => {
    it('keeps a manual transaction out of review and returns empty tabs and zero counts', async () => {
      const account = await helpers.createAccount({ raw: true });
      const [tx] = await helpers.createTransaction({
        payload: helpers.buildTransactionPayload({ accountId: account.id }),
        raw: true,
      });

      const stored = await getById({ id: tx.id });
      expect(stored.reviewStatus).toBe(notRequired);
      expect(stored.reviewDeferredAt).toBeNull();

      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 0, fraudCount: 0 });
      expect(await listIds({ status: unreviewed })).toEqual([]);
      expect(await listIds({ status: reviewed })).toEqual([]);
      expect(await listIds({ status: fraud })).toEqual([]);
    });
  });

  describe('entering the queue', () => {
    it('queues a transaction synced from Monobank', async () => {
      const { rowIds } = await syncOneMonobankAccount({
        transactions: [{ amount: -1500, time: subDays(new Date(), 1), description: 'COFFEE' }],
      });

      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 1, fraudCount: 0 });

      const queue = await helpers.getReviewTransactions({ status: unreviewed, raw: true });
      expect(queue.map((row) => row.id)).toEqual(rowIds);
      expect(queue[0]!.reviewStatus).toBe(unreviewed);
      expect(queue[0]!.reviewDeferredAt).toBeNull();
      expect(queue[0]!.accountType).toBe(ACCOUNT_TYPES.monobank);
      expect(queue[0]!.amount).toBe(15);
    }, 30000);

    it('queues a transaction created by the CSV importer', async () => {
      const [importedId] = await importExpenses({ daysAgo: [2] });

      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 1, fraudCount: 0 });
      expect(await listIds({ status: unreviewed })).toEqual([importedId]);
      expect((await getById({ id: importedId! })).reviewStatus).toBe(unreviewed);
    });

    it('queues an imported transaction only when it is dated within the last 30 days', async () => {
      const [olderId, recentId] = await importExpenses({ daysAgo: [45, 10] });

      expect((await getById({ id: olderId! })).reviewStatus).toBe(notRequired);
      expect((await getById({ id: recentId! })).reviewStatus).toBe(unreviewed);
      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 1, fraudCount: 0 });
      expect(await listIds({ status: unreviewed })).toEqual([recentId]);
    });

    it('keeps a planned transaction out of the queue', async () => {
      const account = await helpers.createAccount({ raw: true });
      const [plan] = await helpers.createPlannedTransaction({
        payload: { accountId: account.id, time: addDays(startOfDay(new Date()), 3).toISOString() },
        raw: true,
      });

      expect((await getById({ id: plan.id })).reviewStatus).toBe(notRequired);
      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 0, fraudCount: 0 });
      expect(await listIds({ status: unreviewed })).toEqual([]);
    });

    it('keeps a planned transaction out of the queue after a bank sync merges into it', async () => {
      const today = startOfDay(new Date());

      // Matching needs one real transaction already on the provider account.
      const { connectionId, accountId } = await syncOneMonobankAccount({
        transactions: [{ amount: -1234, time: subDays(today, 10), description: 'ANCHOR CHARGE' }],
      });

      const [plan] = await helpers.createPlannedTransaction({
        payload: { accountId, amount: 250, time: addDays(today, 2).toISOString(), note: 'Rent' },
        raw: true,
      });
      expect((await getById({ id: plan.id })).reviewStatus).toBe(notRequired);

      global.mswMockServer.use(
        getMonobankTransactionsMock({
          response: [
            helpers.monobank.buildTransaction({
              amount: -25000,
              time: subDays(today, 1),
              description: 'RENT LANDLORD',
            }),
          ],
        }),
      );
      const { jobGroupId } = await helpers.bankDataProviders.syncTransactionsForAccount({
        connectionId,
        accountId,
        raw: true,
      });
      const syncResult = await helpers.bankDataProviders.waitForSyncJobsToComplete({
        connectionId,
        jobGroupId: jobGroupId!,
        timeoutMs: 20000,
      });
      expect(syncResult.status).toBe('completed');

      const merged = await getById({ id: plan.id });
      expect(merged.isPlanned).toBe(false);
      expect(merged.reviewStatus).toBe(notRequired);

      // Only the anchor is waiting for review.
      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 1, fraudCount: 0 });
      expect(await listIds({ status: unreviewed })).not.toContain(plan.id);
    }, 30000);
  });

  describe('ordering', () => {
    it('lists the oldest unreviewed transaction first', async () => {
      const [middle, newest, oldest] = await importExpenses({ daysAgo: [5, 1, 9] });

      expect(await listIds({ status: unreviewed })).toEqual([oldest, middle, newest]);
    });

    it('moves a check_later row behind every fresh row', async () => {
      const [oldest, middle, newest] = await importExpenses({ daysAgo: [9, 5, 1] });

      await applyAction({ ids: [oldest!], action: TRANSACTION_REVIEW_ACTION.checkLater });

      expect(await listIds({ status: unreviewed })).toEqual([middle, newest, oldest]);
    });

    it('keeps several deferred rows in the order they were deferred', async () => {
      const [oldest, middle, newest] = await importExpenses({ daysAgo: [9, 5, 1] });

      // Separate requests, so each row gets its own deferral time.
      await applyAction({ ids: [middle!], action: TRANSACTION_REVIEW_ACTION.checkLater });
      await applyAction({ ids: [oldest!], action: TRANSACTION_REVIEW_ACTION.checkLater });

      expect(await listIds({ status: unreviewed })).toEqual([newest, middle, oldest]);
    });

    it('lists reviewed and fraud rows newest first', async () => {
      const ids = await importExpenses({ daysAgo: [9, 1, 5, 3, 7, 2] });
      const [r9, r1, r5, f3, f7, f2] = ids;

      await applyAction({ ids: [r9!, r1!, r5!], action: TRANSACTION_REVIEW_ACTION.reviewed });
      await applyAction({ ids: [f3!, f7!, f2!], action: TRANSACTION_REVIEW_ACTION.fraud });

      expect(await listIds({ status: reviewed })).toEqual([r1, r5, r9]);
      expect(await listIds({ status: fraud })).toEqual([f2, f3, f7]);
    });

    it('pages through a tab with limit and offset', async () => {
      const [oldest, middle, newest] = await importExpenses({ daysAgo: [9, 5, 1] });

      const firstPage = await helpers.getReviewTransactions({ status: unreviewed, limit: 2, raw: true });
      const secondPage = await helpers.getReviewTransactions({ status: unreviewed, limit: 2, offset: 2, raw: true });

      expect(firstPage.map((row) => row.id)).toEqual([oldest, middle]);
      expect(secondPage.map((row) => row.id)).toEqual([newest]);
    });
  });

  describe('transitions', () => {
    it('moves rows between tabs and updates both counts for every action', async () => {
      const [first, second] = await importExpenses({ daysAgo: [4, 2] });
      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 2, fraudCount: 0 });

      const deferred = await applyAction({ ids: [first!], action: TRANSACTION_REVIEW_ACTION.checkLater });
      expect(deferred).toEqual({ updatedCount: 1 });
      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 2, fraudCount: 0 });
      expect(await listIds({ status: unreviewed })).toEqual([second, first]);

      await applyAction({ ids: [first!], action: TRANSACTION_REVIEW_ACTION.reviewed });
      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 1, fraudCount: 0 });
      expect(await listIds({ status: unreviewed })).toEqual([second]);
      expect(await listIds({ status: reviewed })).toEqual([first]);

      await applyAction({ ids: [second!], action: TRANSACTION_REVIEW_ACTION.fraud });
      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 0, fraudCount: 1 });
      expect(await listIds({ status: unreviewed })).toEqual([]);
      expect(await listIds({ status: fraud })).toEqual([second]);

      // Reviewed -> fraud, and fraud -> reviewed ("Not fraud").
      await applyAction({ ids: [first!], action: TRANSACTION_REVIEW_ACTION.fraud });
      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 0, fraudCount: 2 });
      expect(await listIds({ status: reviewed })).toEqual([]);

      await applyAction({ ids: [first!], action: TRANSACTION_REVIEW_ACTION.reviewed });
      expect(await listIds({ status: reviewed })).toEqual([first]);
      expect(await listIds({ status: fraud })).toEqual([second]);

      // Both rows back to the queue in one batch.
      const reset = await applyAction({ ids: [first!, second!], action: TRANSACTION_REVIEW_ACTION.unreviewed });
      expect(reset).toEqual({ updatedCount: 2 });
      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 2, fraudCount: 0 });
      expect(await listIds({ status: unreviewed })).toEqual([first, second]);
      expect(await listIds({ status: reviewed })).toEqual([]);
      expect(await listIds({ status: fraud })).toEqual([]);
    });

    it('sets reviewDeferredAt only for check_later and exposes both fields on GET /transactions/:id', async () => {
      const [id] = await importExpenses({ daysAgo: [3] });
      const txId = id!;

      const before = Date.now();
      await applyAction({ ids: [txId], action: TRANSACTION_REVIEW_ACTION.checkLater });
      const deferred = await getById({ id: txId });
      expect(deferred.reviewStatus).toBe(unreviewed);
      expect(deferred.reviewDeferredAt).not.toBeNull();
      expect(new Date(deferred.reviewDeferredAt!).getTime()).toBeGreaterThanOrEqual(before - 1000);

      for (const [action, status] of [
        [TRANSACTION_REVIEW_ACTION.reviewed, reviewed],
        [TRANSACTION_REVIEW_ACTION.fraud, fraud],
        [TRANSACTION_REVIEW_ACTION.unreviewed, unreviewed],
      ] as const) {
        // Defer first so each action has a timestamp to clear.
        await applyAction({ ids: [txId], action: TRANSACTION_REVIEW_ACTION.checkLater });
        await applyAction({ ids: [txId], action });

        const stored = await getById({ id: txId });
        expect(stored.reviewStatus).toBe(status);
        expect(stored.reviewDeferredAt).toBeNull();
      }
    });

    it('returns a deferred row to the fresh part of the queue on the unreviewed action', async () => {
      const [oldest, newest] = await importExpenses({ daysAgo: [6, 2] });

      await applyAction({ ids: [oldest!], action: TRANSACTION_REVIEW_ACTION.checkLater });
      expect(await listIds({ status: unreviewed })).toEqual([newest, oldest]);

      await applyAction({ ids: [oldest!], action: TRANSACTION_REVIEW_ACTION.unreviewed });
      expect(await listIds({ status: unreviewed })).toEqual([oldest, newest]);
    });
  });

  describe('errors', () => {
    it('requires a session', async () => {
      const res = await helpers.withoutSession(() => helpers.getReviewSummary());
      expect(res.statusCode).toBe(ERROR_CODES.Unauthorized);
    });

    it('rejects a missing or invalid status', async () => {
      const missing = await helpers.getReviewTransactions({});
      expect(missing.statusCode).toBe(ERROR_CODES.ValidationError);

      const notListable = await helpers.getReviewTransactions({ status: notRequired });
      expect(notListable.statusCode).toBe(ERROR_CODES.ValidationError);

      const unknown = await helpers.getReviewTransactions({
        status: 'pending' as unknown as TRANSACTION_REVIEW_STATUS,
      });
      expect(unknown.statusCode).toBe(ERROR_CODES.ValidationError);
    });

    it('rejects a limit outside 1-100', async () => {
      const tooLarge = await helpers.getReviewTransactions({ status: unreviewed, limit: 101 });
      expect(tooLarge.statusCode).toBe(ERROR_CODES.ValidationError);

      const zero = await helpers.getReviewTransactions({ status: unreviewed, limit: 0 });
      expect(zero.statusCode).toBe(ERROR_CODES.ValidationError);
    });

    it('rejects empty, oversized, duplicated and malformed transactionIds', async () => {
      const action = TRANSACTION_REVIEW_ACTION.reviewed;
      const id = randomUUID();

      for (const transactionIds of [[], Array.from({ length: 101 }, () => randomUUID()), [id, id], ['not-a-uuid']]) {
        const res = await helpers.updateReviewStatus({ payload: { transactionIds, action } });
        expect(res.statusCode).toBe(ERROR_CODES.ValidationError);
      }
    });

    it('rejects an unknown or missing action', async () => {
      const [importedId] = await importExpenses({ daysAgo: [1] });

      const unknown = await helpers.updateReviewStatus({
        payload: { transactionIds: [importedId!], action: 'delete' as unknown as TRANSACTION_REVIEW_ACTION },
      });
      expect(unknown.statusCode).toBe(ERROR_CODES.ValidationError);

      const missing = await helpers.updateReviewStatus({
        payload: { transactionIds: [importedId!] } as { transactionIds: string[]; action: TRANSACTION_REVIEW_ACTION },
      });
      expect(missing.statusCode).toBe(ERROR_CODES.ValidationError);

      expect((await getById({ id: importedId! })).reviewStatus).toBe(unreviewed);
    });

    it('returns 404 and updates nothing when one id does not exist', async () => {
      const ids = await importExpenses({ daysAgo: [3, 2] });

      const res = await helpers.updateReviewStatus({
        payload: { transactionIds: [...ids, randomUUID()], action: TRANSACTION_REVIEW_ACTION.fraud },
      });
      expect(res.statusCode).toBe(ERROR_CODES.NotFoundError);

      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 2, fraudCount: 0 });
      expect(await listIds({ status: fraud })).toEqual([]);
    });

    it("keeps another user's rows out of the queue and rejects a batch that includes one, changing nothing", async () => {
      const ownIds = await importExpenses({ daysAgo: [3, 2] });

      const otherUser = await helpers.provisionSecondUserWithBaseCurrency();
      const [otherId] = await helpers.asUser({
        cookies: otherUser.cookies,
        fn: () => importExpenses({ daysAgo: [1] }),
      });

      // The other user's imported row is in their queue, not in ours.
      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 2, fraudCount: 0 });
      expect(await listIds({ status: unreviewed })).not.toContain(otherId);

      const res = await helpers.updateReviewStatus({
        payload: { transactionIds: [...ownIds, otherId!], action: TRANSACTION_REVIEW_ACTION.reviewed },
      });
      expect(res.statusCode).toBe(ERROR_CODES.NotFoundError);

      expect(await helpers.getReviewSummary({ raw: true })).toEqual({ unreviewedCount: 2, fraudCount: 0 });
      expect(await listIds({ status: reviewed })).toEqual([]);

      const otherSummary = await helpers.asUser({
        cookies: otherUser.cookies,
        fn: () => helpers.getReviewSummary({ raw: true }),
      });
      expect(otherSummary).toEqual({ unreviewedCount: 1, fraudCount: 0 });
      const otherRow = await helpers.asUser({ cookies: otherUser.cookies, fn: () => getById({ id: otherId! }) });
      expect(otherRow.reviewStatus).toBe(unreviewed);
    });
  });
});
