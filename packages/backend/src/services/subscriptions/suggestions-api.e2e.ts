import { MATCH_REASON_CODE, type RecordId, SUBSCRIPTION_FREQUENCIES } from '@bt/shared/types';
import { generateRandomRecordId } from '@common/lib/record-id-helpers';
import { describe, expect, it } from '@jest/globals';
import { ERROR_CODES } from '@js/errors';
import * as helpers from '@tests/helpers';
import { format, startOfDay, subDays, subMonths } from 'date-fns';

const today = startOfDay(new Date());
const toDateString = ({ date }: { date: Date }) => format(date, 'yyyy-MM-dd');

/** A monthly 15.99 recurring payment due today, the shape the manual web/iOS forms create (no rules). */
async function createSubscription({
  name = 'Netflix',
  accountId,
  payeeId,
  expectedAmount = 15.99,
  matchingRules,
}: {
  name?: string;
  accountId?: RecordId;
  payeeId?: RecordId;
  expectedAmount?: number;
  matchingRules?: { rules: Array<Record<string, unknown>> };
} = {}) {
  return helpers.createSubscription({
    name,
    expectedAmount,
    expectedCurrencyCode: global.BASE_CURRENCY.code,
    frequency: SUBSCRIPTION_FREQUENCIES.monthly,
    startDate: toDateString({ date: subMonths(today, 2) }),
    dueDate: toDateString({ date: today }),
    categoryId: global.DEFAULT_CATEGORY_ID,
    ...(accountId && { accountId }),
    ...(payeeId && { payeeId }),
    ...(matchingRules && { matchingRules }),
    raw: true,
  });
}

async function createExpense({
  accountId,
  amount,
  time,
  note,
  payeeId,
}: {
  accountId: RecordId;
  amount: number;
  time: Date;
  note?: string;
  payeeId?: RecordId;
}) {
  const [tx] = await helpers.createTransaction({
    payload: helpers.buildTransactionPayload({
      accountId,
      amount,
      time: time.toISOString(),
      ...(note && { note }),
      ...(payeeId && { payeeId }),
    }),
    raw: true,
  });
  return tx;
}

const suggestedIds = async ({ subscriptionId }: { subscriptionId: string }) => {
  const { suggestions } = await helpers.getSubscriptionSuggestions({ id: subscriptionId, raw: true });
  return suggestions.map((suggestion) => suggestion.transaction.id);
};

const linkedIds = async ({ subscriptionId }: { subscriptionId: string }) => {
  const detail = await helpers.getSubscriptionById({ id: subscriptionId, raw: true });
  return detail.transactions.map((tx) => tx.id);
};

describe('Recurring payment suggestions API', () => {
  describe('GET /subscriptions/:id/suggestions', () => {
    it('ranks a same-payee transaction on the due date above a similar-name one far from it, with reasons', async () => {
      const subscriptionAccount = await helpers.createAccount({ raw: true });
      const otherAccount = await helpers.createAccount({ raw: true });
      const payee = await helpers.createPayee({ payload: { name: 'Netflix' }, raw: true });
      // Scoped to another account, so the transactions below are capped at "suggested" and stay unlinked.
      const subscription = await createSubscription({ accountId: subscriptionAccount.id, payeeId: payee.id });

      const onDueDate = await createExpense({
        accountId: otherAccount.id,
        amount: 15.99,
        time: today,
        payeeId: payee.id,
      });
      const farFromDue = await createExpense({
        accountId: otherAccount.id,
        amount: 15.99,
        time: subDays(today, 15),
        note: 'NETFLIX.COM 8822 AMSTERDAM',
      });

      const result = await helpers.getSubscriptionSuggestions({ id: subscription.id, raw: true });

      expect(result.dismissedCount).toBe(0);
      const ids = result.suggestions.map((suggestion) => suggestion.transaction.id);
      expect(ids).toContain(onDueDate.id);
      expect(ids).toContain(farFromDue.id);
      expect(ids.indexOf(onDueDate.id)).toBeLessThan(ids.indexOf(farFromDue.id));

      const top = result.suggestions.find((suggestion) => suggestion.transaction.id === onDueDate.id)!;
      const topCodes = top.reasons.map((reason) => reason.code);
      expect(topCodes).toEqual(
        expect.arrayContaining([
          MATCH_REASON_CODE.payeeMatch,
          MATCH_REASON_CODE.nearDueDate,
          MATCH_REASON_CODE.differentAccount,
        ]),
      );
      expect(top.score).toBeGreaterThan(0.5);
      expect(top.nearestDueDate).toBe(toDateString({ date: today }));
      expect(top.daysFromDue).toBe(0);
      expect(top.transaction.amount).toBe(15.99);

      const far = result.suggestions.find((suggestion) => suggestion.transaction.id === farFromDue.id)!;
      const farCodes = far.reasons.map((reason) => reason.code);
      expect(
        farCodes.some((code) => code === MATCH_REASON_CODE.payeeMatch || code === MATCH_REASON_CODE.merchantSimilar),
      ).toBe(true);
      expect(farCodes).toContain(MATCH_REASON_CODE.farFromDueDate);
      expect(far.score).toBeLessThan(top.score);

      // Still suggestions, not links.
      expect(await linkedIds({ subscriptionId: subscription.id })).toEqual([]);
    });

    it('returns an empty list when the user has no transactions', async () => {
      const subscription = await createSubscription();

      const result = await helpers.getSubscriptionSuggestions({ id: subscription.id, raw: true });

      expect(result).toEqual({ suggestions: [], dismissedCount: 0 });
    });

    it('returns 404 for an unknown subscription and 422 for an invalid id', async () => {
      const unknown = await helpers.getSubscriptionSuggestions({ id: generateRandomRecordId() });
      expect(unknown.statusCode).toBe(ERROR_CODES.NotFoundError);

      const invalid = await helpers.getSubscriptionSuggestions({ id: 'not-a-uuid' });
      expect(invalid.statusCode).toBe(ERROR_CODES.ValidationError);
    });
  });

  describe('GET /subscriptions/:id/linkable-transactions', () => {
    async function seedHistory() {
      const accountA = await helpers.createAccount({ raw: true });
      const accountB = await helpers.createAccount({ raw: true });
      const streamingPayee = await helpers.createPayee({ payload: { name: 'Streaming Co' }, raw: true });

      // Amounts far from the expected 15.99 keep every row below the auto-link threshold.
      const netflixOnB = await createExpense({
        accountId: accountB.id,
        amount: 99,
        time: subDays(today, 95),
        note: 'NETFLIX.COM 1931 LOS GATOS',
      });
      const streamingOnA = await createExpense({
        accountId: accountA.id,
        amount: 5,
        time: subDays(today, 10),
        note: 'Card purchase',
        payeeId: streamingPayee.id,
      });
      const groceriesOnA = await createExpense({
        accountId: accountA.id,
        amount: 40,
        time: subDays(today, 40),
        note: 'Groceries',
      });

      const subscription = await createSubscription();
      return { accountA, accountB, subscription, netflixOnB, streamingOnA, groceriesOnA };
    }

    it('finds transactions by note, payee name and amount regardless of amount or account', async () => {
      const { subscription, netflixOnB, streamingOnA } = await seedHistory();

      const byNote = await helpers.searchLinkableTransactions({ id: subscription.id, search: 'netflix', raw: true });
      expect(byNote.items.map((item) => item.transaction.id)).toEqual([netflixOnB.id]);
      expect(byNote.hasMore).toBe(false);
      expect(byNote.items[0]!.score).toBeGreaterThan(0);
      expect(byNote.items[0]!.reasons.map((reason) => reason.code)).toContain(MATCH_REASON_CODE.merchantSimilar);
      expect(byNote.items[0]!.linkedSubscription).toBeNull();
      expect(byNote.items[0]!.isDismissed).toBe(false);

      const byPayee = await helpers.searchLinkableTransactions({ id: subscription.id, search: 'streaming', raw: true });
      expect(byPayee.items.map((item) => item.transaction.id)).toEqual([streamingOnA.id]);

      const byAmount = await helpers.searchLinkableTransactions({ id: subscription.id, search: '99', raw: true });
      expect(byAmount.items.map((item) => item.transaction.id)).toContain(netflixOnB.id);
    });

    it('filters by date range and accounts', async () => {
      const { subscription, accountB, netflixOnB, streamingOnA } = await seedHistory();

      const recent = await helpers.searchLinkableTransactions({
        id: subscription.id,
        from: toDateString({ date: subDays(today, 15) }),
        to: toDateString({ date: today }),
        raw: true,
      });
      expect(recent.items.map((item) => item.transaction.id)).toEqual([streamingOnA.id]);

      const onB = await helpers.searchLinkableTransactions({
        id: subscription.id,
        accountIds: [accountB.id],
        raw: true,
      });
      expect(onB.items.map((item) => item.transaction.id)).toEqual([netflixOnB.id]);
    });

    it('pages newest first with hasMore', async () => {
      const { subscription, netflixOnB, streamingOnA, groceriesOnA } = await seedHistory();

      const first = await helpers.searchLinkableTransactions({ id: subscription.id, limit: 1, raw: true });
      expect(first.items.map((item) => item.transaction.id)).toEqual([streamingOnA.id]);
      expect(first.hasMore).toBe(true);

      const second = await helpers.searchLinkableTransactions({ id: subscription.id, limit: 1, offset: 1, raw: true });
      expect(second.items.map((item) => item.transaction.id)).toEqual([groceriesOnA.id]);
      expect(second.hasMore).toBe(true);

      const last = await helpers.searchLinkableTransactions({ id: subscription.id, limit: 1, offset: 2, raw: true });
      expect(last.items.map((item) => item.transaction.id)).toEqual([netflixOnB.id]);
      expect(last.hasMore).toBe(false);
    });

    it('annotates a transaction linked to another recurring payment', async () => {
      const { subscription, groceriesOnA } = await seedHistory();
      const gym = await createSubscription({ name: 'Gym' });
      await helpers.linkTransactionsToSubscription({ id: gym.id, transactionIds: [groceriesOnA.id], raw: true });

      const result = await helpers.searchLinkableTransactions({ id: subscription.id, search: 'groceries', raw: true });

      expect(result.items).toHaveLength(1);
      expect(result.items[0]!.transaction.id).toBe(groceriesOnA.id);
      expect(result.items[0]!.linkedSubscription).toEqual({ id: gym.id, name: 'Gym' });
    });

    it('returns an empty page when the user has no transactions', async () => {
      const subscription = await createSubscription();

      const result = await helpers.searchLinkableTransactions({ id: subscription.id, raw: true });

      expect(result).toEqual({ items: [], hasMore: false });
    });

    it('rejects an inverted date range, an oversized limit and an unknown subscription', async () => {
      const subscription = await createSubscription();

      const inverted = await helpers.searchLinkableTransactions({
        id: subscription.id,
        from: toDateString({ date: today }),
        to: toDateString({ date: subDays(today, 5) }),
      });
      expect(inverted.statusCode).toBe(ERROR_CODES.ValidationError);

      const oversized = await helpers.searchLinkableTransactions({ id: subscription.id, limit: 101 });
      expect(oversized.statusCode).toBe(ERROR_CODES.ValidationError);

      const unknown = await helpers.searchLinkableTransactions({ id: generateRandomRecordId() });
      expect(unknown.statusCode).toBe(ERROR_CODES.NotFoundError);
    });
  });

  describe('POST /subscriptions/:id/suggestions/dismiss', () => {
    it('hides a dismissed transaction, keeps backfill from linking it, and an explicit link clears the dismissal', async () => {
      const subscriptionAccount = await helpers.createAccount({ raw: true });
      const otherAccount = await helpers.createAccount({ raw: true });
      const subscription = await createSubscription({ accountId: subscriptionAccount.id });

      const tx = await createExpense({ accountId: otherAccount.id, amount: 15.99, time: today, note: 'NETFLIX' });
      expect(await suggestedIds({ subscriptionId: subscription.id })).toContain(tx.id);

      const dismissed = await helpers.dismissSubscriptionSuggestions({
        id: subscription.id,
        transactionIds: [tx.id],
        raw: true,
      });
      expect(dismissed).toEqual({ dismissed: 1 });

      const afterDismiss = await helpers.getSubscriptionSuggestions({ id: subscription.id, raw: true });
      expect(afterDismiss.suggestions.map((suggestion) => suggestion.transaction.id)).not.toContain(tx.id);
      expect(afterDismiss.dismissedCount).toBe(1);

      const linkable = await helpers.searchLinkableTransactions({ id: subscription.id, search: 'netflix', raw: true });
      expect(linkable.items.find((item) => item.transaction.id === tx.id)?.isDismissed).toBe(true);

      // Dropping the account scope would make it an auto-link; the edit's backfill must respect the dismissal.
      await helpers.updateSubscription({ id: subscription.id, accountId: null, raw: true });
      expect(await linkedIds({ subscriptionId: subscription.id })).not.toContain(tx.id);

      const linked = await helpers.linkTransactionsToSubscription({
        id: subscription.id,
        transactionIds: [tx.id],
        raw: true,
      });
      expect(linked.linked).toBe(1);
      expect(await linkedIds({ subscriptionId: subscription.id })).toContain(tx.id);

      const afterLink = await helpers.getSubscriptionSuggestions({ id: subscription.id, raw: true });
      expect(afterLink.dismissedCount).toBe(0);
    });

    it('returns 404 for a transaction that does not exist and 422 for an empty list', async () => {
      const subscription = await createSubscription();

      const unknownTx = await helpers.dismissSubscriptionSuggestions({
        id: subscription.id,
        transactionIds: [generateRandomRecordId()],
      });
      expect(unknownTx.statusCode).toBe(ERROR_CODES.NotFoundError);

      const empty = await helpers.dismissSubscriptionSuggestions({ id: subscription.id, transactionIds: [] });
      expect(empty.statusCode).toBe(ERROR_CODES.ValidationError);
    });
  });

  describe('tiering', () => {
    it('suggests an ambiguous transaction for both close recurring payments and links neither', async () => {
      const account = await helpers.createAccount({ raw: true });
      const first = await createSubscription({ name: 'Netflix' });
      const second = await createSubscription({ name: 'Netflix' });

      const tx = await createExpense({ accountId: account.id, amount: 15.99, time: today, note: 'NETFLIX' });

      expect(await linkedIds({ subscriptionId: first.id })).toEqual([]);
      expect(await linkedIds({ subscriptionId: second.id })).toEqual([]);
      expect(await suggestedIds({ subscriptionId: first.id })).toContain(tx.id);
      expect(await suggestedIds({ subscriptionId: second.id })).toContain(tx.id);
    });

    it('keeps an explicit amount rule as a gate for a same-payee transaction outside the range', async () => {
      const account = await helpers.createAccount({ raw: true });
      const payee = await helpers.createPayee({ payload: { name: 'Netflix' }, raw: true });
      const subscription = await createSubscription({
        payeeId: payee.id,
        expectedAmount: 11,
        matchingRules: { rules: [{ field: 'amount', operator: 'between', value: { min: 10, max: 12 } }] },
      });

      const outside = await createExpense({ accountId: account.id, amount: 30, time: today, payeeId: payee.id });
      const inside = await createExpense({ accountId: account.id, amount: 11, time: today, payeeId: payee.id });

      const linked = await linkedIds({ subscriptionId: subscription.id });
      expect(linked).toEqual([inside.id]);
      expect(await suggestedIds({ subscriptionId: subscription.id })).not.toContain(outside.id);
    });
  });

  describe('pendingSuggestionsCount', () => {
    it('counts pending suggestions on the list and the detail', async () => {
      const subscriptionAccount = await helpers.createAccount({ raw: true });
      const otherAccount = await helpers.createAccount({ raw: true });
      const withSuggestion = await createSubscription({ accountId: subscriptionAccount.id });
      const withoutSuggestion = await createSubscription({ name: 'Gym' });

      await createExpense({ accountId: otherAccount.id, amount: 15.99, time: today, note: 'NETFLIX' });

      const detail = await helpers.getSubscriptionById({ id: withSuggestion.id, raw: true });
      expect(detail.pendingSuggestionsCount).toBe(1);

      const list = await helpers.getSubscriptions({ raw: true });
      expect(list.find((item) => item.id === withSuggestion.id)?.pendingSuggestionsCount).toBe(1);
      expect(list.find((item) => item.id === withoutSuggestion.id)?.pendingSuggestionsCount).toBe(0);
    });
  });
});
