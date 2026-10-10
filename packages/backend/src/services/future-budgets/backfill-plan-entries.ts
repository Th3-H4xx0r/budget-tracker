import { isTwoLegTransfer, RecordId } from '@bt/shared/types';
import FutureBudgetPlans from '@models/future-budget-plans.model';
import { findTransactions } from '@models/transactions-query';
import { withTransaction } from '@services/common/with-transaction';
import { addDays } from 'date-fns';
import { Op } from 'sequelize';

import { syncPlanEntriesForTransactions } from './sync-plan-entries';

/** Bounds the one-off scan when a long plan window spans a large transaction history. */
const BACKFILL_TRANSACTIONS_LIMIT = 5000;

export interface BackfillPlanEntriesParams {
  userId: number;
  planId: RecordId;
}

/**
 * Brings the transactions that already exist in a plan's window into it, as auto-add would have
 * done had it been on when they were created. Runs when a plan starts auto-adding.
 */
const backfillPlanEntriesImpl = async ({ userId, planId }: BackfillPlanEntriesParams): Promise<void> => {
  const plan = await FutureBudgetPlans.findOne({ where: { id: planId, userId } });
  if (!plan) return;

  const windowStart = new Date(`${plan.startDate}T00:00:00.000Z`);
  const windowEnd = addDays(new Date(`${plan.endDate}T00:00:00.000Z`), 1);

  const transactions = await findTransactions({
    where: { time: { [Op.gte]: windowStart, [Op.lt]: windowEnd } },
    attributes: ['id', 'transferNature'],
    order: [['time', 'DESC']],
    planned: 'exclude',
    access: { accountOwner: userId },
    balanceAdjustments: 'exclude',
    completeness: { cap: { limit: BACKFILL_TRANSACTIONS_LIMIT, onTruncated: 'log', context: { userId, planId } } },
  });

  await syncPlanEntriesForTransactions({
    userId,
    transactionIds: transactions.filter((tx) => !isTwoLegTransfer(tx.transferNature)).map((tx) => tx.id),
  });
};

export const backfillPlanEntries = withTransaction(backfillPlanEntriesImpl);
