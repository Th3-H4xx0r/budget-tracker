import {
  CATEGORIZATION_SOURCE,
  type RecordId,
  SUBSCRIPTION_MATCH_SOURCE,
  SUBSCRIPTION_SUGGESTION_SOURCE,
  SUBSCRIPTION_SUGGESTION_STATUS,
} from '@bt/shared/types';
import { logger } from '@js/utils/logger';
import SubscriptionMatchSuggestions from '@models/subscription-match-suggestions.model';
import SubscriptionTransactions from '@models/subscription-transactions.model';
import { updateTransactions } from '@models/transactions-query';
import { syncPlanEntriesForTransactions } from '@services/future-budgets/sync-plan-entries';
import { Op } from 'sequelize';

import { stampSubscriptionPayeeAndTags } from '../stamp-payee-and-tags';
import type { TransactionDecision } from './decide-matches';
import { toDateOnly } from './expected-dates';
import { markNearestOpenPeriodPaidByLink } from './mark-period-by-link';
import type { ScorableTransaction, SubscriptionProfile } from './types';

/**
 * Persists one transaction's decision. Auto-link: link row with score and reasons, payee/tag stamp,
 * category stamp on the rule path only, LINK-mode payment of the nearest open period, cleanup of
 * pending suggestions for the tx and a plan sync. Otherwise: upserts pending suggestions.
 * Returns the linked profile, if any. Callers run inside `withTransaction`.
 */
export async function applyMatchDecision({
  userId,
  transaction,
  decision,
  profilesById,
}: {
  userId: number;
  transaction: ScorableTransaction;
  decision: TransactionDecision;
  profilesById: Map<string, SubscriptionProfile>;
}): Promise<SubscriptionProfile | null> {
  const { autoLink, suggestions } = decision;

  if (!autoLink) {
    if (suggestions.length > 0) {
      await SubscriptionMatchSuggestions.bulkCreate(
        suggestions.map((match) => ({
          subscriptionId: match.subscriptionId,
          transactionId: transaction.id,
          userId,
          score: match.score,
          reasons: match.reasons,
          status: SUBSCRIPTION_SUGGESTION_STATUS.pending,
          source: SUBSCRIPTION_SUGGESTION_SOURCE.engine,
        })),
        // Dismissed pairs never reach here (they are gated), so the upsert only refreshes pending rows.
        { updateOnDuplicate: ['score', 'reasons', 'updatedAt'] },
      );
    }
    return null;
  }

  const profile = profilesById.get(autoLink.subscriptionId)!;
  const { subscription } = profile;

  await SubscriptionTransactions.create({
    subscriptionId: subscription.id,
    transactionId: transaction.id,
    matchSource: SUBSCRIPTION_MATCH_SOURCE.rule,
    matchScore: autoLink.score,
    matchReasons: autoLink.reasons,
  });

  await SubscriptionMatchSuggestions.destroy({
    where: { transactionId: transaction.id, status: SUBSCRIPTION_SUGGESTION_STATUS.pending },
  });

  profile.linkedDates.push(toDateOnly({ date: transaction.time }));

  // On a planned row the user picked category, payee and tags on purpose, so the match only links.
  if (!transaction.isPlanned) {
    if (autoLink.ruleMatch && subscription.categoryId) {
      await updateTransactions({
        values: {
          categoryId: subscription.categoryId,
          categorizationMeta: {
            source: CATEGORIZATION_SOURCE.subscriptionRule,
            subscriptionId: subscription.id,
            categorizedAt: new Date().toISOString(),
          },
        },
        where: { id: transaction.id },
        planned: 'exclude',
        access: 'unscoped-internal',
        balanceAdjustments: 'include',
      });
    }

    await stampSubscriptionPayeeAndTags({ subscription, transactionIds: [transaction.id] });

    const marked = await markNearestOpenPeriodPaidByLink({ subscription, transaction });
    if (marked) {
      const period = profile.periods.find((item) => !item.transactionId && item.dueDate === autoLink.nearestDueDate);
      if (period) period.transactionId = transaction.id as RecordId;
    }
  }

  await syncPlanEntriesForTransactions({ userId, transactionIds: [transaction.id] });

  logger.info(
    `Subscription "${subscription.name}" auto-linked transaction ${transaction.id} (score: ${autoLink.score.toFixed(3)})`,
  );
  return profile;
}

/** Drops suggestion rows (pending or dismissed) for explicitly linked pairs, and pending rows of those txs elsewhere. */
export async function clearSuggestionsForLinkedTransactions({
  subscriptionId,
  transactionIds,
}: {
  subscriptionId: RecordId;
  transactionIds: RecordId[];
}): Promise<void> {
  if (transactionIds.length === 0) return;

  await SubscriptionMatchSuggestions.destroy({
    where: {
      transactionId: { [Op.in]: transactionIds },
      [Op.or]: [{ subscriptionId }, { status: SUBSCRIPTION_SUGGESTION_STATUS.pending }],
    },
  });
}
