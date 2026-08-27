import { describe, expect, it } from '@jest/globals';
import * as helpers from '@tests/helpers';
import { addDays, format, subDays } from 'date-fns';

const today = new Date();
const planStartDate = format(subDays(today, 5), 'yyyy-MM-dd');
const planEndDate = format(addDays(today, 5), 'yyyy-MM-dd');

describe('Auto-add synced transactions to future budget plans', () => {
  it('adds a real transaction created within the plan window when the setting is enabled', async () => {
    const plan = await helpers.createFutureBudgetPlan({
      startDate: planStartDate,
      endDate: planEndDate,
      raw: true,
    });
    await helpers.updateFutureBudgetPlan({
      id: plan.id,
      payload: { autoAddSyncedTransactions: true },
      raw: true,
    });

    const account = await helpers.createAccount({ raw: true });
    const txPayload = helpers.buildTransactionPayload({
      accountId: account.id,
      amount: 42,
      time: today.toISOString(),
    });
    await helpers.createTransaction({ payload: txPayload });

    const details = await helpers.getFutureBudgetPlan({ id: plan.id, raw: true });
    const autoAdded = details.occurrences.find(
      (occurrence) => occurrence.source === 'manual' && occurrence.amount === 42,
    );
    expect(autoAdded).toBeDefined();
    expect(details.entries.some((entry) => entry.amount === 42)).toBe(true);
  });

  it('does not add the transaction when the setting is left at its default (off)', async () => {
    const plan = await helpers.createFutureBudgetPlan({
      startDate: planStartDate,
      endDate: planEndDate,
      raw: true,
    });

    const account = await helpers.createAccount({ raw: true });
    const txPayload = helpers.buildTransactionPayload({
      accountId: account.id,
      amount: 43,
      time: today.toISOString(),
    });
    await helpers.createTransaction({ payload: txPayload });

    const details = await helpers.getFutureBudgetPlan({ id: plan.id, raw: true });
    expect(details.occurrences.some((occurrence) => occurrence.amount === 43)).toBe(false);
    expect(details.entries).toHaveLength(0);
  });

  it('does not add a transaction dated outside the plan window even when the setting is enabled', async () => {
    const plan = await helpers.createFutureBudgetPlan({
      startDate: planStartDate,
      endDate: planEndDate,
      raw: true,
    });
    await helpers.updateFutureBudgetPlan({
      id: plan.id,
      payload: { autoAddSyncedTransactions: true },
      raw: true,
    });

    const account = await helpers.createAccount({ raw: true });
    const txPayload = helpers.buildTransactionPayload({
      accountId: account.id,
      amount: 44,
      time: addDays(today, 30).toISOString(),
    });
    await helpers.createTransaction({ payload: txPayload });

    const details = await helpers.getFutureBudgetPlan({ id: plan.id, raw: true });
    expect(details.occurrences.some((occurrence) => occurrence.amount === 44)).toBe(false);
    expect(details.entries).toHaveLength(0);
  });
});
