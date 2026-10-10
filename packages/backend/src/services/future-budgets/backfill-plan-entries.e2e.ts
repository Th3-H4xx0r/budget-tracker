import { RecordId, SUBSCRIPTION_FREQUENCIES } from '@bt/shared/types';
import { describe, expect, it } from '@jest/globals';
import * as helpers from '@tests/helpers';
import { addDays, format, startOfDay, subDays } from 'date-fns';

const today = startOfDay(new Date());
const toDateString = ({ date }: { date: Date }) => format(date, 'yyyy-MM-dd');

async function createPlan({ endInDays = 5 }: { endInDays?: number } = {}) {
  return helpers.createFutureBudgetPlan({
    startDate: toDateString({ date: subDays(today, 5) }),
    endDate: toDateString({ date: addDays(today, endInDays) }),
    raw: true,
  });
}

async function setAutoAdd({ planId, enabled }: { planId: string; enabled: boolean }) {
  return helpers.updateFutureBudgetPlan({ id: planId, payload: { autoAddSyncedTransactions: enabled }, raw: true });
}

async function createExpense({ accountId, amount, time }: { accountId: RecordId; amount: number; time: Date }) {
  const [tx] = await helpers.createTransaction({
    payload: helpers.buildTransactionPayload({ accountId, amount, time: time.toISOString() }),
    raw: true,
  });
  return tx;
}

describe('Backfill plan entries when auto-add is turned on', () => {
  it('adds the transactions already in the plan window, and only those', async () => {
    const plan = await createPlan();
    const account = await helpers.createAccount({ raw: true });
    const inWindow = await createExpense({ accountId: account.id, amount: 31, time: today });
    await createExpense({ accountId: account.id, amount: 32, time: addDays(today, 30) });

    const before = await helpers.getFutureBudgetPlan({ id: plan.id, raw: true });
    expect(before.entries).toHaveLength(0);

    await setAutoAdd({ planId: plan.id, enabled: true });

    const details = await helpers.getFutureBudgetPlan({ id: plan.id, raw: true });
    expect(details.entries).toHaveLength(1);
    expect(details.entries[0]).toMatchObject({ transactionId: inWindow.id, amount: 31, subscriptionId: null });
    expect(details.occurrences.filter((o) => o.source === 'manual' && o.amount === 31)).toHaveLength(1);
    expect(details.occurrences.some((o) => o.amount === 32)).toBe(false);
    expect(details.summary.expense).toBe(31);
  });

  it('keeps entries when auto-add is turned off and does not duplicate them when it is turned back on', async () => {
    const plan = await createPlan();
    const account = await helpers.createAccount({ raw: true });
    const tx = await createExpense({ accountId: account.id, amount: 33, time: today });

    await setAutoAdd({ planId: plan.id, enabled: true });
    await setAutoAdd({ planId: plan.id, enabled: false });

    const afterOff = await helpers.getFutureBudgetPlan({ id: plan.id, raw: true });
    expect(afterOff.entries.map((entry) => entry.transactionId)).toEqual([tx.id]);

    await setAutoAdd({ planId: plan.id, enabled: true });

    const afterOn = await helpers.getFutureBudgetPlan({ id: plan.id, raw: true });
    expect(afterOn.entries.map((entry) => entry.transactionId)).toEqual([tx.id]);
    expect(afterOn.summary.expense).toBe(33);
  });

  it('records a backfilled transaction linked to a recurring payment as that payment, counted once', async () => {
    const plan = await createPlan({ endInDays: 20 });
    const account = await helpers.createAccount({ raw: true });
    const tx = await createExpense({ accountId: account.id, amount: 37, time: today });
    const subscription = await helpers.createSubscription({
      name: 'Streaming',
      expectedAmount: 50,
      expectedCurrencyCode: global.BASE_CURRENCY.code,
      frequency: SUBSCRIPTION_FREQUENCIES.monthly,
      startDate: toDateString({ date: today }),
      dueDate: toDateString({ date: today }),
      categoryId: global.DEFAULT_CATEGORY_ID,
      raw: true,
    });
    await helpers.linkTransactionsToSubscription({ id: subscription.id, transactionIds: [tx.id], raw: true });

    await setAutoAdd({ planId: plan.id, enabled: true });

    const details = await helpers.getFutureBudgetPlan({ id: plan.id, raw: true });
    const forSubscription = details.occurrences.filter((o) => o.subscriptionId === subscription.id);
    expect(forSubscription).toHaveLength(1);
    expect(forSubscription[0]).toMatchObject({
      source: 'recurring_actual',
      transactionId: tx.id,
      name: 'Streaming',
      amount: 37,
    });
    expect(details.occurrences.some((o) => o.source === 'manual' && o.amount === 37)).toBe(false);
    expect(details.summary.expense).toBe(37);
  });

  it('adds nothing when the plan window has no transactions', async () => {
    const plan = await createPlan();

    const updated = await setAutoAdd({ planId: plan.id, enabled: true });
    expect(updated.autoAddSyncedTransactions).toBe(true);

    const details = await helpers.getFutureBudgetPlan({ id: plan.id, raw: true });
    expect(details.entries).toHaveLength(0);
    expect(details.summary).toEqual({ income: 0, expense: 0, net: 0 });
  });

  it('returns an error when turning on auto-add for a plan that does not exist', async () => {
    const response = await helpers.updateFutureBudgetPlan({
      id: '01a03d74-a6f7-70ee-8031-9abeb9a07000',
      payload: { autoAddSyncedTransactions: true },
      raw: false,
    });

    expect(response.statusCode).toBe(500);
  });
});
