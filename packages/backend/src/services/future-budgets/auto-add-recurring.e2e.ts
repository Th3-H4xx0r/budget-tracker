import { SUBSCRIPTION_FREQUENCIES, SUBSCRIPTION_PERIOD_STATUSES } from '@bt/shared/types';
import { describe, expect, it } from '@jest/globals';
import * as helpers from '@tests/helpers';
import type { FutureBudgetPlanDetailsResponse } from '@tests/helpers/future-budgets';
import { addDays, format, startOfDay, subDays } from 'date-fns';

const today = startOfDay(new Date());
const toDateString = ({ date }: { date: Date }) => format(date, 'yyyy-MM-dd');

async function createPlan({ endInDays, autoAdd }: { endInDays: number; autoAdd: boolean }) {
  const plan = await helpers.createFutureBudgetPlan({
    startDate: toDateString({ date: subDays(today, 5) }),
    endDate: toDateString({ date: addDays(today, endInDays) }),
    raw: true,
  });
  if (autoAdd) {
    await helpers.updateFutureBudgetPlan({
      id: plan.id,
      payload: { autoAddSyncedTransactions: true },
      raw: true,
    });
  }
  return plan;
}

/** A recurring payment created by hand: no matching rules and no linked transactions. */
async function createManualSubscription({
  name,
  dueDate,
  accountId,
  payeeId,
}: {
  name: string;
  dueDate: Date;
  accountId?: string;
  payeeId?: string;
}) {
  return helpers.createSubscription({
    name,
    expectedAmount: 50,
    expectedCurrencyCode: global.BASE_CURRENCY.code,
    frequency: SUBSCRIPTION_FREQUENCIES.monthly,
    startDate: toDateString({ date: today }),
    dueDate: toDateString({ date: dueDate }),
    categoryId: global.DEFAULT_CATEGORY_ID,
    ...(accountId && { accountId }),
    ...(payeeId && { payeeId }),
    raw: true,
  });
}

/** Plan rows backed by no recurring payment, i.e. context-free one-off entries. */
const oneOffOccurrencesWithAmount = ({
  details,
  amount,
}: {
  details: FutureBudgetPlanDetailsResponse;
  amount: number;
}) => details.occurrences.filter((o) => o.source === 'manual' && !o.subscriptionId && o.amount === amount);

describe('Planned budgets with manually created recurring payments (bug reproductions)', () => {
  it('projects a manually created recurring payment that has no linked transactions', async () => {
    const plan = await createPlan({ endInDays: 40, autoAdd: true });
    const subscription = await createManualSubscription({ name: 'Rent', dueDate: addDays(today, 10) });

    const details = await helpers.getFutureBudgetPlan({ id: plan.id, raw: true });

    const projected = details.occurrences.filter(
      (o) => o.source === 'recurring' && o.subscriptionId === subscription.id,
    );
    expect(projected.length).toBeGreaterThanOrEqual(1);
    expect(projected[0]!.amount).toBe(50);
    expect(projected[0]!.date).toBe(toDateString({ date: addDays(today, 10) }));
  });

  it('counts a mark-paid recurring payment once instead of adding it as a one-off entry', async () => {
    const plan = await createPlan({ endInDays: 20, autoAdd: true });
    const account = await helpers.createAccount({ raw: true });
    const subscription = await createManualSubscription({ name: 'Gym', dueDate: today, accountId: account.id });

    const detail = await helpers.getSubscriptionById({ id: subscription.id, raw: true });
    const openPeriod = detail.periods.find(
      (period) =>
        period.status === SUBSCRIPTION_PERIOD_STATUSES.upcoming ||
        period.status === SUBSCRIPTION_PERIOD_STATUSES.overdue,
    );
    expect(openPeriod).toBeDefined();

    await helpers.markSubscriptionPeriodPaid({
      id: subscription.id,
      periodId: openPeriod!.id,
      createTransaction: true,
      raw: true,
    });

    const details = await helpers.getFutureBudgetPlan({ id: plan.id, raw: true });

    expect(details.occurrences.filter((o) => o.subscriptionId === subscription.id)).toHaveLength(1);
    expect(oneOffOccurrencesWithAmount({ details, amount: 50 })).toHaveLength(0);
    expect(details.summary.expense).toBe(50);
  });

  it('attributes a synced same-payee transaction to the manual recurring payment instead of a one-off entry', async () => {
    const plan = await createPlan({ endInDays: 40, autoAdd: true });
    const account = await helpers.createAccount({ raw: true });
    const payee = await helpers.createPayee({ payload: { name: 'Gymco' }, raw: true });
    const subscription = await createManualSubscription({ name: 'Gymco', dueDate: today, payeeId: payee.id });

    await helpers.createTransaction({
      payload: helpers.buildTransactionPayload({
        accountId: account.id,
        amount: 50,
        time: today.toISOString(),
        payeeId: payee.id,
        note: 'GYMCO 4411',
      }),
      raw: true,
    });

    const details = await helpers.getFutureBudgetPlan({ id: plan.id, raw: true });

    // Due today (paid by the synced tx) and again one month later (still projected).
    expect(details.occurrences.filter((o) => o.subscriptionId === subscription.id)).toHaveLength(2);
    expect(oneOffOccurrencesWithAmount({ details, amount: 50 })).toHaveLength(0);
    expect(details.summary.expense).toBe(100);
  });
});
