import { type RecordId, SUBSCRIPTION_FREQUENCIES, SUBSCRIPTION_PERIOD_STATUSES } from '@bt/shared/types';
import { describe, expect, it } from '@jest/globals';
import * as helpers from '@tests/helpers';
import { format, startOfDay, subDays, subMonths } from 'date-fns';

const today = startOfDay(new Date());
const toDateString = ({ date }: { date: Date }) => format(date, 'yyyy-MM-dd');

/**
 * Creates a recurring payment the way the web/iOS manual forms do: no matching
 * rules, a monthly expected amount of 15.99 and a due date of today, so its
 * previous due dates fall one and two months back.
 */
async function createManualNetflixSubscription({
  payeeId,
  accountId,
}: {
  payeeId?: string;
  accountId?: string;
} = {}) {
  return helpers.createSubscription({
    name: 'Netflix',
    expectedAmount: 15.99,
    expectedCurrencyCode: global.BASE_CURRENCY.code,
    frequency: SUBSCRIPTION_FREQUENCIES.monthly,
    startDate: toDateString({ date: subMonths(today, 2) }),
    dueDate: toDateString({ date: today }),
    categoryId: global.DEFAULT_CATEGORY_ID,
    ...(payeeId && { payeeId }),
    ...(accountId && { accountId }),
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

/** Ids the user can act on for a subscription: already linked, or offered as suggestions. */
async function getLinkedAndSuggestedIds({ subscriptionId }: { subscriptionId: string }) {
  const [detail, suggestions] = await Promise.all([
    helpers.getSubscriptionById({ id: subscriptionId, raw: true }),
    helpers.getSuggestedMatches({ id: subscriptionId, raw: true }),
  ]);
  const linkedIds = detail.transactions.map((tx) => tx.id);
  const suggestedIds = suggestions.map((tx) => tx.id);
  return { linkedIds, suggestedIds, allIds: new Set([...linkedIds, ...suggestedIds]) };
}

async function getOpenPeriodId({ subscriptionId }: { subscriptionId: string }) {
  const detail = await helpers.getSubscriptionById({ id: subscriptionId, raw: true });
  const open = detail.periods.find(
    (period) =>
      period.status === SUBSCRIPTION_PERIOD_STATUSES.upcoming || period.status === SUBSCRIPTION_PERIOD_STATUSES.overdue,
  );
  expect(open).toBeDefined();
  return open!.id;
}

describe('Smart recurring-payment matching (bug reproductions)', () => {
  describe('manually created recurring payment without matching rules', () => {
    it('links or suggests past same-payee transactions on its due dates despite amount differences', async () => {
      const account = await helpers.createAccount({ raw: true });
      const payee = await helpers.createPayee({ payload: { name: 'Netflix' }, raw: true });

      const twoMonthsAgo = await createExpense({
        accountId: account.id,
        amount: 15.49,
        time: subMonths(today, 2),
        payeeId: payee.id,
      });
      const oneMonthAgo = await createExpense({
        accountId: account.id,
        amount: 16.99,
        time: subMonths(today, 1),
        payeeId: payee.id,
      });

      const subscription = await createManualNetflixSubscription({ payeeId: payee.id });

      const { allIds } = await getLinkedAndSuggestedIds({ subscriptionId: subscription.id });
      expect(allIds.has(twoMonthsAgo.id)).toBe(true);
      expect(allIds.has(oneMonthAgo.id)).toBe(true);
    });

    it('links or suggests past same-note transactions on its due dates despite amount differences', async () => {
      const account = await helpers.createAccount({ raw: true });

      const twoMonthsAgo = await createExpense({
        accountId: account.id,
        amount: 15.49,
        time: subMonths(today, 2),
        note: 'NETFLIX.COM 8822 AMSTERDAM',
      });
      const oneMonthAgo = await createExpense({
        accountId: account.id,
        amount: 16.99,
        time: subMonths(today, 1),
        note: 'NETFLIX.COM 8822 AMSTERDAM',
      });

      const subscription = await createManualNetflixSubscription();

      const { allIds } = await getLinkedAndSuggestedIds({ subscriptionId: subscription.id });
      expect(allIds.has(twoMonthsAgo.id)).toBe(true);
      expect(allIds.has(oneMonthAgo.id)).toBe(true);
    });

    it('links or suggests a new same-payee transaction arriving on its due date with a different amount', async () => {
      const account = await helpers.createAccount({ raw: true });
      const payee = await helpers.createPayee({ payload: { name: 'Netflix' }, raw: true });
      const subscription = await createManualNetflixSubscription({ payeeId: payee.id });

      const tx = await createExpense({
        accountId: account.id,
        amount: 16.99,
        time: today,
        payeeId: payee.id,
        note: 'NETFLIX.COM',
      });

      const { allIds } = await getLinkedAndSuggestedIds({ subscriptionId: subscription.id });
      expect(allIds.has(tx.id)).toBe(true);
    });
  });

  describe('POST /subscriptions/:id/periods/:periodId/pay', () => {
    it('lists the transaction booked by mark-paid (createTransaction) among linked transactions', async () => {
      const account = await helpers.createAccount({ raw: true });
      const subscription = await createManualNetflixSubscription({ accountId: account.id });
      const periodId = await getOpenPeriodId({ subscriptionId: subscription.id });

      const paid = await helpers.markSubscriptionPeriodPaid({
        id: subscription.id,
        periodId,
        createTransaction: true,
        raw: true,
      });
      expect(paid.status).toBe(SUBSCRIPTION_PERIOD_STATUSES.paid);
      expect(paid.transactionId).toBeTruthy();

      const detail = await helpers.getSubscriptionById({ id: subscription.id, raw: true });
      expect(detail.transactions.map((tx) => tx.id)).toContain(paid.transactionId);
    });

    it('lists an existing transaction picked in mark-paid among linked transactions', async () => {
      const account = await helpers.createAccount({ raw: true });
      const subscription = await createManualNetflixSubscription({ accountId: account.id });
      const periodId = await getOpenPeriodId({ subscriptionId: subscription.id });

      const tx = await createExpense({
        accountId: account.id,
        amount: 17.5,
        time: subDays(today, 1),
        note: 'Card payment',
      });

      const paid = await helpers.markSubscriptionPeriodPaid({
        id: subscription.id,
        periodId,
        transactionId: tx.id,
        raw: true,
      });
      expect(paid.status).toBe(SUBSCRIPTION_PERIOD_STATUSES.paid);
      expect(paid.transactionId).toBe(tx.id);

      const detail = await helpers.getSubscriptionById({ id: subscription.id, raw: true });
      expect(detail.transactions.map((linked) => linked.id)).toContain(tx.id);
    });
  });
});
