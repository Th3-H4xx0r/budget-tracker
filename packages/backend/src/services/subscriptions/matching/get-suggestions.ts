import {
  type RecordId,
  SUBSCRIPTION_AUTO_LINK_MIN_SCORE,
  SUBSCRIPTION_SUGGESTION_MIN_SCORE,
  SUBSCRIPTION_SUGGESTION_STATUS,
  type SubscriptionSuggestion,
  type SubscriptionSuggestionsResponse,
} from '@bt/shared/types';
import SubscriptionMatchSuggestions from '@models/subscription-match-suggestions.model';
import { findTransactions } from '@models/transactions-query';
import type Transactions from '@models/transactions.model';
import { type TransactionApiResponse, serializeTransaction } from '@root/serializers/transactions.serializer';
import { addDays, subDays } from 'date-fns';
import { Op } from 'sequelize';

import { findSubscriptionOrThrow } from '../helpers';
import {
  findCandidateTransactions,
  notActivelyLinkedWhere,
  payeeNameInclude,
  toScorableTransaction,
} from './candidate-transactions';
import { createFxConverter, loadLinkState, pairKey } from './link-state';
import { scoreTransaction } from './score-transaction';
import { loadSubscriptionProfiles } from './subscription-profile';

const SUGGESTION_DAYS_BACK = 400;
const SUGGESTION_DAYS_FORWARD = 7;
const DEFAULT_SUGGESTIONS_LIMIT = 50;

type SubscriptionSuggestionItem = SubscriptionSuggestion<TransactionApiResponse>;

/**
 * Ranked suggestions for one recurring payment, computed live (prefilter + scorer, no writes) and
 * unioned with persisted pending rows (e.g. from discovery). Dismissed and actively linked
 * transactions are excluded; only scores >= 0.5 are kept. Sorted by score, then newest first.
 */
export async function getSubscriptionSuggestions({
  userId,
  subscriptionId,
  limit = DEFAULT_SUGGESTIONS_LIMIT,
}: {
  userId: number;
  subscriptionId: RecordId;
  limit?: number;
}): Promise<SubscriptionSuggestionsResponse<TransactionApiResponse>> {
  await findSubscriptionOrThrow({ id: subscriptionId, userId });

  const [persisted, dismissedCount] = await Promise.all([
    SubscriptionMatchSuggestions.findAll({
      where: { subscriptionId, userId, status: SUBSCRIPTION_SUGGESTION_STATUS.pending },
    }),
    SubscriptionMatchSuggestions.count({
      where: { subscriptionId, userId, status: SUBSCRIPTION_SUGGESTION_STATUS.dismissed },
    }),
  ]);

  const [profile] = await loadSubscriptionProfiles({ userId, subscriptionIds: [subscriptionId] });
  if (!profile) return { suggestions: [], dismissedCount };

  const now = new Date();
  const live = await findCandidateTransactions({
    userId,
    profile,
    from: subDays(now, SUGGESTION_DAYS_BACK),
    to: addDays(now, SUGGESTION_DAYS_FORWARD),
  });

  const liveIds = new Set(live.map((tx) => tx.id));
  const missingPersistedIds = persisted.map((row) => row.transactionId).filter((id) => !liveIds.has(id));
  const persistedTxs: Transactions[] = missingPersistedIds.length
    ? await findTransactions({
        where: { id: { [Op.in]: missingPersistedIds }, [Op.and]: [notActivelyLinkedWhere()] },
        planned: 'exclude',
        access: { accountOwner: userId },
        balanceAdjustments: 'include',
        completeness: 'all',
        include: [payeeNameInclude()],
      })
    : [];

  const candidates = [...live, ...persistedTxs];
  const linkState = await loadLinkState({ transactionIds: candidates.map((tx) => tx.id) });
  const persistedScore = new Map(persisted.map((row) => [row.transactionId as string, row]));
  const fx = createFxConverter({ userId });

  const suggestions: Array<SubscriptionSuggestionItem & { time: number }> = [];
  for (const tx of candidates) {
    if (linkState.blockedPairs.has(pairKey({ subscriptionId, transactionId: tx.id }))) continue;

    const match = await scoreTransaction({ profile, transaction: toScorableTransaction({ tx }), fx });
    const stored = persistedScore.get(tx.id);
    const score = Math.max(match?.score ?? 0, stored?.score ?? 0);
    if (score < SUBSCRIPTION_SUGGESTION_MIN_SCORE) continue;

    const useStored = !!stored && (!match || stored.score > match.score);
    suggestions.push({
      transaction: serializeTransaction(tx),
      score: Math.round(score * 1000) / 1000,
      confidence: score >= SUBSCRIPTION_AUTO_LINK_MIN_SCORE ? 'high' : 'medium',
      reasons: useStored ? stored.reasons : (match?.reasons ?? []),
      nearestDueDate: match?.nearestDueDate ?? null,
      daysFromDue: match?.daysFromDue ?? null,
      amountDeviationPct: match?.amountDeviationPct ?? null,
      time: tx.time.getTime(),
    });
  }

  suggestions.sort((a, b) => b.score - a.score || b.time - a.time);

  return {
    suggestions: suggestions.slice(0, limit).map(({ time: _time, ...item }) => item),
    dismissedCount,
  };
}
