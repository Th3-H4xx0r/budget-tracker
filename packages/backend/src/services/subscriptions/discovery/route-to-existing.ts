import {
  MATCH_REASON_CODE,
  type MatchReason,
  type RecordId,
  SUBSCRIPTION_SUGGESTION_SOURCE,
  SUBSCRIPTION_SUGGESTION_STATUS,
} from '@bt/shared/types';
import SubscriptionMatchSuggestions from '@models/subscription-match-suggestions.model';
import Subscriptions from '@models/subscriptions.model';

import { buildMerchantKey, tokenSimilarity } from '../matching/merchant-key';
import type { AnalyzedCluster } from './types';

const NAME_MIN_SIMILARITY = 0.75;
const PAYEE_MATCH_SCORE = 0.7;
const NAME_MATCH_BASE_SCORE = 0.5;
const NAME_MATCH_SCORE_SPAN = 0.2;

interface RouteResult {
  /** Clusters that don't belong to an existing recurring payment: these become candidates. */
  unrouted: AnalyzedCluster[];
  /** Suggestion rows written for existing recurring payments. */
  suggestionsCreated: number;
}

interface RouteMatch {
  subscriptionId: string;
  score: number;
  reason: MatchReason;
}

function matchCluster({
  analyzed,
  subscriptions,
}: {
  analyzed: AnalyzedCluster;
  subscriptions: Array<{ subscription: Subscriptions; tokens: string[] }>;
}): RouteMatch | null {
  const { cluster } = analyzed;
  let best: RouteMatch | null = null;

  for (const { subscription, tokens } of subscriptions) {
    if (subscription.transactionType !== cluster.transactionType) continue;
    if (subscription.expectedCurrencyCode && subscription.expectedCurrencyCode !== cluster.currencyCode) continue;

    if (cluster.payeeId && subscription.payeeId === cluster.payeeId) {
      return {
        subscriptionId: subscription.id,
        score: PAYEE_MATCH_SCORE,
        reason: { code: MATCH_REASON_CODE.payeeMatch, weight: PAYEE_MATCH_SCORE, value: 1 },
      };
    }

    const similarity = tokenSimilarity({ a: cluster.tokens, b: tokens });
    if (similarity < NAME_MIN_SIMILARITY) continue;

    const score =
      NAME_MATCH_BASE_SCORE + (NAME_MATCH_SCORE_SPAN * (similarity - NAME_MIN_SIMILARITY)) / (1 - NAME_MIN_SIMILARITY);
    if (!best || score > best.score) {
      best = {
        subscriptionId: subscription.id,
        score: Math.round(score * 1000) / 1000,
        reason: {
          code: MATCH_REASON_CODE.merchantSimilar,
          weight: score,
          value: Math.round(similarity * 1000) / 1000,
        },
      };
    }
  }

  return best;
}

/**
 * Routes clusters that already correspond to an active recurring payment into
 * `SubscriptionMatchSuggestions` (`source: discovery`) instead of new candidates: the user created
 * the payment by hand and the history only needs linking.
 *
 * Identity here is payee equality or merchant-token similarity with the payment's name. Amount and
 * date never gate routing, so a payment whose price changed still claims its history. Existing rows
 * are left untouched, which keeps a dismissed pair dismissed.
 */
export async function routeClustersToExisting({
  userId,
  clusters,
}: {
  userId: number;
  clusters: AnalyzedCluster[];
}): Promise<RouteResult> {
  if (clusters.length === 0) return { unrouted: [], suggestionsCreated: 0 };

  const activeSubscriptions = await Subscriptions.findAll({
    where: { userId, isActive: true },
    attributes: ['id', 'name', 'payeeId', 'transactionType', 'expectedCurrencyCode'],
  });
  if (activeSubscriptions.length === 0) return { unrouted: clusters, suggestionsCreated: 0 };

  const subscriptions = activeSubscriptions.map((subscription) => ({
    subscription,
    tokens: buildMerchantKey({ raw: subscription.name }).tokens,
  }));

  const unrouted: AnalyzedCluster[] = [];
  const rows: Array<Partial<SubscriptionMatchSuggestions>> = [];

  for (const analyzed of clusters) {
    const match = matchCluster({ analyzed, subscriptions });
    if (!match) {
      unrouted.push(analyzed);
      continue;
    }

    for (const tx of analyzed.cluster.transactions) {
      rows.push({
        subscriptionId: match.subscriptionId as RecordId,
        transactionId: tx.id as RecordId,
        userId,
        score: match.score,
        reasons: [match.reason],
        status: SUBSCRIPTION_SUGGESTION_STATUS.pending,
        source: SUBSCRIPTION_SUGGESTION_SOURCE.discovery,
      });
    }
  }

  if (rows.length > 0) {
    await SubscriptionMatchSuggestions.bulkCreate(rows, { ignoreDuplicates: true });
  }

  return { unrouted, suggestionsCreated: rows.length };
}
