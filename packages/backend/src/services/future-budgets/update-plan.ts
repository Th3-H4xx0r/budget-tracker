import { BUDGET_STATUSES } from '@bt/shared/types';
import FutureBudgetPlans from '@models/future-budget-plans.model';
import { withTransaction } from '@services/common/with-transaction';

import { backfillPlanEntries } from './backfill-plan-entries';

interface UpdatePlanParams {
  userId: number;
  plan: FutureBudgetPlans;
  changes: Record<string, unknown>;
}

const isAutoAdding = ({ plan }: { plan: FutureBudgetPlans }) =>
  plan.status === BUDGET_STATUSES.active && plan.autoAddSyncedTransactions;

/**
 * Applies plan changes. When the plan starts auto-adding (the toggle turns on, or an archived
 * auto-adding plan is reactivated) the transactions already in its window are backfilled. Turning
 * auto-add off leaves the existing entries in place: from then on they are the user's data.
 */
const updatePlanImpl = async ({ userId, plan, changes }: UpdatePlanParams): Promise<FutureBudgetPlans> => {
  const wasAutoAdding = isAutoAdding({ plan });
  await plan.update(changes);

  if (!wasAutoAdding && isAutoAdding({ plan })) {
    await backfillPlanEntries({ userId, planId: plan.id });
  }
  return plan;
};

export const updatePlan = withTransaction(updatePlanImpl);
