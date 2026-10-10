import { BUDGET_STATUSES, isTwoLegTransfer, RecordId, SUBSCRIPTION_LINK_STATUS } from '@bt/shared/types';
import FutureBudgetEntries from '@models/future-budget-entries.model';
import FutureBudgetPlans from '@models/future-budget-plans.model';
import SubscriptionTransactions from '@models/subscription-transactions.model';
import Subscriptions from '@models/subscriptions.model';
import { findTransactions } from '@models/transactions-query';
import Transactions from '@models/transactions.model';
import { withTransaction } from '@services/common/with-transaction';

export interface SyncPlanEntriesForTransactionsParams {
  userId: number;
  transactionIds: RecordId[];
}

const entryKey = ({ planId, transactionId }: { planId: RecordId; transactionId: RecordId }) =>
  `${planId}:${transactionId}`;

/** Plan dates are UTC calendar days, matching how plan ranges and entry dates are stored. */
const toPlanDate = ({ time }: { time: Date }) => time.toISOString().slice(0, 10);

/**
 * Maps each transaction to the user's recurring payment it is actively linked to. When a tx is
 * actively linked to more than one, the most recent link wins.
 */
const findActiveSubscriptionIds = async ({
  userId,
  transactionIds,
}: {
  userId: number;
  transactionIds: RecordId[];
}): Promise<Map<RecordId, RecordId>> => {
  const result = new Map<RecordId, RecordId>();
  if (!transactionIds.length) return result;

  const links = await SubscriptionTransactions.findAll({
    where: {
      transactionId: transactionIds,
      status: SUBSCRIPTION_LINK_STATUS.active,
    },
    order: [['matchedAt', 'DESC']],
  });
  if (!links.length) return result;

  const ownedSubscriptions = await Subscriptions.findAll({
    where: {
      id: [...new Set(links.map((link) => link.subscriptionId))],
      userId,
    },
    attributes: ['id'],
  });
  const ownedIds = new Set(ownedSubscriptions.map((subscription) => subscription.id));

  for (const link of links) {
    if (ownedIds.has(link.subscriptionId) && !result.has(link.transactionId)) {
      result.set(link.transactionId, link.subscriptionId);
    }
  }
  return result;
};

/**
 * Idempotently reconciles the `FutureBudgetEntries` of the user's active plans with
 * `autoAddSyncedTransactions` on against the current state of the given transactions:
 * - every real (non-planned, non-balance-adjustment, non-two-leg-transfer) tx gets exactly one
 *   entry per plan whose range covers its date, carrying its amount, date, category, note, type and
 *   the recurring payment it is actively linked to (`subscriptionId`, null when unlinked);
 * - entries of those plans that no longer correspond to a covering real tx are removed.
 *
 * Plans with auto-add off or archived are left untouched: their auto-added entries are user data.
 * A transaction can legitimately land in several overlapping plans. Deleted transactions are
 * handled by the `transactionId` FK cascade.
 *
 * Callers invoke it after transaction creates/updates and after every recurring-payment
 * link-state change (link, unlink, mark paid, auto-match).
 */
const syncPlanEntriesForTransactionsImpl = async ({
  userId,
  transactionIds,
}: SyncPlanEntriesForTransactionsParams): Promise<void> => {
  const uniqueIds = [...new Set(transactionIds)];
  if (!uniqueIds.length) return;

  const plans = await FutureBudgetPlans.findAll({
    where: { userId, status: BUDGET_STATUSES.active, autoAddSyncedTransactions: true },
    attributes: ['id', 'startDate', 'endDate'],
  });
  if (!plans.length) return;

  const planIds = plans.map((plan) => plan.id);
  const [transactions, existingEntries] = await Promise.all([
    findTransactions({
      where: { id: uniqueIds },
      attributes: ['id', 'transactionType', 'amount', 'time', 'categoryId', 'note', 'transferNature'],
      planned: 'exclude',
      access: { accountOwner: userId },
      balanceAdjustments: 'exclude',
      completeness: 'all',
    }),
    FutureBudgetEntries.findAll({ where: { planId: planIds, transactionId: uniqueIds } }),
  ]);

  const realTransactions = transactions.filter((tx: Transactions) => !isTwoLegTransfer(tx.transferNature));
  const subscriptionIdByTransaction = await findActiveSubscriptionIds({
    userId,
    transactionIds: realTransactions.map((tx) => tx.id),
  });

  const existingByKey = new Map(
    existingEntries.map((entry) => [entryKey({ planId: entry.planId, transactionId: entry.transactionId! }), entry]),
  );
  const keptKeys = new Set<string>();
  const toCreate: Array<Record<string, unknown>> = [];

  for (const tx of realTransactions) {
    const date = toPlanDate({ time: tx.time });
    const fields = {
      transactionType: tx.transactionType,
      amount: tx.amount,
      date,
      categoryId: tx.categoryId ?? null,
      note: tx.note ?? null,
      frequency: null,
      intervalDays: null,
      transactionId: tx.id,
      subscriptionId: subscriptionIdByTransaction.get(tx.id) ?? null,
    };

    for (const plan of plans) {
      if (date < plan.startDate || date > plan.endDate) continue;

      const key = entryKey({ planId: plan.id, transactionId: tx.id });
      keptKeys.add(key);
      const existing = existingByKey.get(key);
      if (existing) await existing.update(fields);
      else toCreate.push({ ...fields, planId: plan.id });
    }
  }

  if (toCreate.length) await FutureBudgetEntries.bulkCreate(toCreate);

  const staleIds = existingEntries
    .filter(
      (entry) =>
        !keptKeys.has(
          entryKey({
            planId: entry.planId,
            transactionId: entry.transactionId!,
          }),
        ),
    )
    .map((entry) => entry.id);
  if (staleIds.length) await FutureBudgetEntries.destroy({ where: { id: staleIds } });
};

export const syncPlanEntriesForTransactions = withTransaction(syncPlanEntriesForTransactionsImpl);
