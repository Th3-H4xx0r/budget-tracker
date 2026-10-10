import { SUBSCRIPTION_PERIOD_STATUSES } from '@bt/shared/types';
import SubscriptionPeriods from '@models/subscription-periods.model';
import type Subscriptions from '@models/subscriptions.model';
import { Op } from 'sequelize';

import { ensureNextPeriodExists } from '../ensure-next-period';
import { MATCH_WINDOW_DAYS, daysBetween } from './expected-dates';

/**
 * LINK-mode payment of the open period nearest to a newly linked real transaction: marks it paid
 * with that transaction when its due date lies within the frequency window of the tx date and it has
 * no transaction yet, then continues the schedule. A transaction backs at most one period.
 * Returns whether a period was marked.
 */
export async function markNearestOpenPeriodPaidByLink({
  subscription,
  transaction,
}: {
  subscription: Subscriptions;
  transaction: { id: string; time: Date; isPlanned: boolean };
}): Promise<boolean> {
  if (transaction.isPlanned) return false;

  const alreadyBacking = await SubscriptionPeriods.findOne({ where: { transactionId: transaction.id } });
  if (alreadyBacking) return false;

  const openPeriods = await SubscriptionPeriods.findAll({
    where: {
      subscriptionId: subscription.id,
      transactionId: null,
      status: { [Op.in]: [SUBSCRIPTION_PERIOD_STATUSES.upcoming, SUBSCRIPTION_PERIOD_STATUSES.overdue] },
    },
  });

  const windowDays = MATCH_WINDOW_DAYS[subscription.frequency];
  const nearest = openPeriods
    .map((period) => ({ period, days: daysBetween({ dueDate: period.dueDate, date: transaction.time }) }))
    .filter((entry) => entry.days <= windowDays)
    .sort((a, b) => a.days - b.days)[0];
  if (!nearest) return false;

  await nearest.period.update({
    status: SUBSCRIPTION_PERIOD_STATUSES.paid,
    paidAt: transaction.time,
    transactionId: transaction.id,
    transactionAutoCreated: false,
  });
  await ensureNextPeriodExists({ subscription });

  return true;
}
