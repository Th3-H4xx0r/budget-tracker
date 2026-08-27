import { describe, expect, it } from '@jest/globals';
import * as helpers from '@tests/helpers';
import { addDays, format, subDays } from 'date-fns';

const today = new Date();
const planStartDate = format(subDays(today, 5), 'yyyy-MM-dd');
const planEndDate = format(addDays(today, 5), 'yyyy-MM-dd');

describe('Update and delete future budget plans and entries', () => {
  it('updates a plan entry', async () => {
    const plan = await helpers.createFutureBudgetPlan({ startDate: planStartDate, endDate: planEndDate, raw: true });
    const entry = await helpers.createFutureBudgetEntry({
      id: plan.id,
      payload: { transactionType: 'expense', amount: 10, date: planStartDate },
      raw: true,
    });

    const updated = await helpers.updateFutureBudgetEntry({
      id: plan.id,
      entryId: entry.id,
      payload: { amount: 25, note: 'Updated note' },
      raw: true,
    });

    expect(updated.amount).toBe(25);
    expect(updated.note).toBe('Updated note');
  });

  it('returns an error when updating an entry that does not exist', async () => {
    const plan = await helpers.createFutureBudgetPlan({ startDate: planStartDate, endDate: planEndDate, raw: true });

    const response = await helpers.updateFutureBudgetEntry({
      id: plan.id,
      entryId: '01a03d74-a6f7-70ee-8031-9abeb9a07000',
      payload: { amount: 25 },
      raw: false,
    });

    expect(response.statusCode).toBe(500);
  });

  it('deletes a plan and its entries', async () => {
    const plan = await helpers.createFutureBudgetPlan({ startDate: planStartDate, endDate: planEndDate, raw: true });
    await helpers.createFutureBudgetEntry({
      id: plan.id,
      payload: { transactionType: 'expense', amount: 10, date: planStartDate },
      raw: true,
    });

    await helpers.deleteFutureBudgetPlan({ id: plan.id, raw: true });

    const response = await helpers.getFutureBudgetPlan({ id: plan.id, raw: false });
    expect(response.statusCode).toBe(500);
  });
});
