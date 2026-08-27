import { BUDGET_STATUSES, RecordId, TRANSACTION_TYPES } from '@bt/shared/types';
import { Money } from '@common/types/money';
import FutureBudgetEntries from '@models/future-budget-entries.model';
import FutureBudgetPlans from '@models/future-budget-plans.model';
import { withTransaction } from '@services/common/with-transaction';
import { Op } from 'sequelize';

interface AutoAddSyncedTransactionParams {
  accountOwnerUserId: number;
  transactionType: TRANSACTION_TYPES;
  amount: Money;
  date: string;
  categoryId: RecordId | null;
  note: string | null;
}

/**
 * A real transaction never targets a specific plan by id, so every active plan opted into
 * `autoAddSyncedTransactions` whose date range covers it gets its own entry — a transaction
 * can legitimately land inside more than one overlapping plan.
 */
const autoAddSyncedTransactionImpl = async ({
  accountOwnerUserId,
  transactionType,
  amount,
  date,
  categoryId,
  note,
}: AutoAddSyncedTransactionParams): Promise<void> => {
  const plans = await FutureBudgetPlans.findAll({
    where: {
      userId: accountOwnerUserId,
      status: BUDGET_STATUSES.active,
      autoAddSyncedTransactions: true,
      startDate: { [Op.lte]: date },
      endDate: { [Op.gte]: date },
    },
  });

  for (const plan of plans) {
    await FutureBudgetEntries.create({
      planId: plan.id,
      transactionType,
      amount,
      date,
      categoryId,
      note,
      frequency: null,
      intervalDays: null,
    });
  }
};

export const autoAddSyncedTransaction = withTransaction(autoAddSyncedTransactionImpl);
