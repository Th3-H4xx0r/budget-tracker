import { RecordId, SUBSCRIPTION_LINK_STATUS, TRANSACTION_TYPES } from '@bt/shared/types';
import { Money } from '@common/types/money';
import FutureBudgetEntries from '@models/future-budget-entries.model';
import FutureBudgetPlans from '@models/future-budget-plans.model';
import FutureBudgetRecurringOverrides from '@models/future-budget-recurring-overrides.model';
import Subscriptions from '@models/subscriptions.model';
import { transactionsInclude } from '@models/transactions-query';

import { daysBetween, occurrences } from './occurrences';

/** How far a paid occurrence may land from its due date, per frequency (the matcher's windows). */
const OCCURRENCE_WINDOW_DAYS: Record<string, number> = {
  weekly: 2,
  biweekly: 4,
  monthly: 6,
  quarterly: 10,
  semi_annual: 15,
  annual: 20,
};
const DEFAULT_OCCURRENCE_WINDOW_DAYS = 6;

/** Recent payments a variable-amount recurring payment's projected amount is derived from. */
const LEARNED_AMOUNT_SAMPLE_SIZE = 3;

export interface RecurringPlanOccurrence {
  source: 'recurring' | 'recurring_actual';
  subscriptionId: RecordId;
  name: string;
  transactionType: TRANSACTION_TYPES;
  amount: Money;
  date: string;
  categoryId: RecordId | null;
  /** `recurring_actual` only: the auto-added entry and the real transaction it mirrors. */
  id?: RecordId;
  transactionId?: RecordId | null;
  note?: string | null;
}

const median = ({ values }: { values: Money[] }): Money | null => {
  if (!values.length) return null;
  const sorted = values.toSorted((a, b) => a.toCents() - b.toCents());
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle]! : sorted[middle - 1]!.add(sorted[middle]!).divide(2);
};

/** Median of the latest actively linked real payments, for recurring payments without an expected amount. */
const loadLearnedAmounts = async ({ subscriptionIds }: { subscriptionIds: RecordId[] }) => {
  const result = new Map<RecordId, Money>();
  if (!subscriptionIds.length) return result;

  const subscriptions = await Subscriptions.findAll({
    where: { id: subscriptionIds },
    attributes: ['id'],
    include: [
      transactionsInclude({
        planned: 'exclude',
        required: true,
        attributes: ['id', 'amount', 'time'],
        through: {
          attributes: [],
          where: { status: SUBSCRIPTION_LINK_STATUS.active },
        },
      }),
    ],
  });

  for (const subscription of subscriptions) {
    const recent = subscription.transactions
      .toSorted((a, b) => b.time.getTime() - a.time.getTime())
      .slice(0, LEARNED_AMOUNT_SAMPLE_SIZE)
      .map((tx) => tx.amount);
    const amount = median({ values: recent });
    if (amount) result.set(subscription.id, amount);
  }
  return result;
};

/**
 * The plan's recurring rows. Every active recurring payment is projected, whether created by hand or
 * discovered from transactions, unless the plan excludes it, it ended before the plan starts, or no
 * amount can be determined (override, else expected amount, else the median of recent payments).
 *
 * Auto-added entries whose transaction is linked to a recurring payment become `recurring_actual`
 * rows and replace that payment's projected occurrence nearest to them (within the frequency's
 * window), so a paid occurrence is counted once. Their entry ids are returned so the caller doesn't
 * also list them as one-off entries.
 */
export const buildRecurringOccurrences = async ({
  userId,
  plan,
  overrides,
  entries,
}: {
  userId: number;
  plan: FutureBudgetPlans;
  overrides: FutureBudgetRecurringOverrides[];
  entries: FutureBudgetEntries[];
}): Promise<{
  occurrences: RecurringPlanOccurrence[];
  actualEntryIds: Set<RecordId>;
}> => {
  const subscriptions = await Subscriptions.findAll({ where: { userId } });
  const subscriptionById = new Map(subscriptions.map((subscription) => [subscription.id, subscription]));
  const overrideBySubscription = new Map(overrides.map((override) => [override.subscriptionId, override]));

  const projectable = subscriptions.filter(
    (subscription) =>
      subscription.isActive &&
      overrideBySubscription.get(subscription.id)?.isIncluded !== false &&
      !(subscription.endDate && subscription.endDate < plan.startDate),
  );
  const learnedAmounts = await loadLearnedAmounts({
    subscriptionIds: projectable
      .filter((subscription) => !overrideBySubscription.get(subscription.id)?.amount && !subscription.expectedAmount)
      .map((subscription) => subscription.id),
  });

  const projected: RecurringPlanOccurrence[] = projectable.flatMap((subscription) => {
    const override = overrideBySubscription.get(subscription.id);
    const amount = override?.amount ?? subscription.expectedAmount ?? learnedAmounts.get(subscription.id);
    if (!amount) return [];

    return occurrences({
      startDate: plan.startDate,
      endDate: subscription.endDate && subscription.endDate < plan.endDate ? subscription.endDate : plan.endDate,
      anchorDate: override?.nextOccurrenceDate ?? subscription.dueDate ?? subscription.startDate,
      frequency: subscription.frequency,
      // The installment count runs from the subscription's own schedule, not a plan-level re-anchor.
      maxCount: override?.nextOccurrenceDate ? null : subscription.maxOccurrences,
    }).map((date) => ({
      source: 'recurring' as const,
      subscriptionId: subscription.id,
      name: subscription.name,
      transactionType: subscription.transactionType,
      amount,
      date,
      categoryId: override?.categoryId ?? subscription.categoryId,
    }));
  });

  const remaining = [...projected];
  const actualEntryIds = new Set<RecordId>();
  const actuals: RecurringPlanOccurrence[] = [];

  for (const entry of entries) {
    if (!entry.transactionId || !entry.subscriptionId) continue;
    const subscription = subscriptionById.get(entry.subscriptionId);
    const windowDays = OCCURRENCE_WINDOW_DAYS[subscription?.frequency ?? ''] ?? DEFAULT_OCCURRENCE_WINDOW_DAYS;

    let nearestIndex = -1;
    let nearestDistance = Infinity;
    remaining.forEach((occurrence, index) => {
      if (occurrence.subscriptionId !== entry.subscriptionId) return;
      const distance = daysBetween({ from: occurrence.date, to: entry.date });
      if (distance <= windowDays && distance < nearestDistance) {
        nearestIndex = index;
        nearestDistance = distance;
      }
    });
    if (nearestIndex >= 0) remaining.splice(nearestIndex, 1);

    actualEntryIds.add(entry.id);
    actuals.push({
      source: 'recurring_actual',
      id: entry.id,
      transactionId: entry.transactionId,
      subscriptionId: entry.subscriptionId,
      name: subscription?.name ?? entry.note ?? '',
      note: entry.note,
      transactionType: entry.transactionType,
      amount: entry.amount,
      date: entry.date,
      categoryId: entry.categoryId,
    });
  }

  return { occurrences: [...remaining, ...actuals], actualEntryIds };
};
