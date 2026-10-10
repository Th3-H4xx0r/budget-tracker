import { describe, expect, it } from '@jest/globals';
import { ERROR_CODES } from '@js/errors';
import * as helpers from '@tests/helpers';

describe('User settings – monthlySpendingBudget', () => {
  it('defaults to no amount with alerts enabled when nothing is stored', async () => {
    const settings = await helpers.getUserSettings({ raw: true });

    expect(settings.monthlySpendingBudget).toStrictEqual({ amount: null, alertsEnabled: true });
  });

  it('sets a decimal amount and enables alerts, and reads them back', async () => {
    await helpers.patchUserSettings({
      raw: true,
      patch: { monthlySpendingBudget: { alertsEnabled: false } },
    });

    const patched = await helpers.patchUserSettings({
      raw: true,
      patch: { monthlySpendingBudget: { amount: 1500.75, alertsEnabled: true } },
    });
    expect(patched.monthlySpendingBudget).toStrictEqual({ amount: 1500.75, alertsEnabled: true });

    const fetched = await helpers.getUserSettings({ raw: true });
    expect(fetched.monthlySpendingBudget).toStrictEqual({ amount: 1500.75, alertsEnabled: true });
  });

  it('clears the amount to null and keeps alertsEnabled', async () => {
    await helpers.patchUserSettings({
      raw: true,
      patch: { monthlySpendingBudget: { amount: 800, alertsEnabled: false } },
    });

    const cleared = await helpers.patchUserSettings({
      raw: true,
      patch: { monthlySpendingBudget: { amount: null } },
    });
    expect(cleared.monthlySpendingBudget).toStrictEqual({ amount: null, alertsEnabled: false });

    const fetched = await helpers.getUserSettings({ raw: true });
    expect(fetched.monthlySpendingBudget).toStrictEqual({ amount: null, alertsEnabled: false });
  });

  it('rejects a negative amount and keeps the stored budget intact', async () => {
    await helpers.patchUserSettings({
      raw: true,
      patch: { monthlySpendingBudget: { amount: 300, alertsEnabled: true } },
    });

    const response = await helpers.patchUserSettings({
      patch: { monthlySpendingBudget: { amount: -1 } },
    });
    expect(response.statusCode).toBe(ERROR_CODES.ValidationError);

    const fetched = await helpers.getUserSettings({ raw: true });
    expect(fetched.monthlySpendingBudget).toStrictEqual({ amount: 300, alertsEnabled: true });
  });

  it('rejects values of the wrong type', async () => {
    const invalidPatches: Record<string, unknown>[] = [
      { monthlySpendingBudget: { amount: '100' } },
      { monthlySpendingBudget: { alertsEnabled: 'yes' } },
      { monthlySpendingBudget: 100 },
    ];

    for (const patch of invalidPatches) {
      const response = await helpers.patchUserSettings({ patch });
      expect({ patch, statusCode: response.statusCode }).toStrictEqual({
        patch,
        statusCode: ERROR_CODES.ValidationError,
      });
    }

    const fetched = await helpers.getUserSettings({ raw: true });
    expect(fetched.monthlySpendingBudget).toStrictEqual({ amount: null, alertsEnabled: true });
  });
});
