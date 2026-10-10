import { MATCH_REASON_CODE } from '@bt/shared/types';

import { tierOf } from './score-transaction';
import type { MatchScore } from './types';

const AMBIGUITY_MARGIN = 0.05;
const MAX_SUGGESTIONS_PER_TRANSACTION = 3;

export interface TransactionDecision {
  autoLink: MatchScore | null;
  suggestions: MatchScore[];
}

/**
 * Picks, for one transaction, the subscription to auto-link (if any) and the suggestions to persist,
 * from its scores against every eligible subscription. Two subscriptions within 0.05 of each other
 * are ambiguous: both are suggested, neither linked. Rule-path pairs keep the legacy amount-closeness
 * tie-break instead.
 */
export function decideMatches({ scored }: { scored: MatchScore[] }): TransactionDecision {
  const ranked = scored
    .map((match) => ({ match, tier: tierOf({ match }) }))
    .filter((entry) => entry.tier !== 'none')
    .sort((a, b) =>
      a.match.ruleMatch && b.match.ruleMatch
        ? b.match.amountCloseness - a.match.amountCloseness
        : b.match.score - a.match.score,
    );

  const [top, runnerUp] = ranked;
  if (!top) return { autoLink: null, suggestions: [] };

  const ambiguous =
    !!runnerUp &&
    !(top.match.ruleMatch && runnerUp.match.ruleMatch) &&
    top.match.score - runnerUp.match.score <= AMBIGUITY_MARGIN;

  if (ambiguous) {
    for (const [entry, other] of [
      [top, runnerUp],
      [runnerUp, top],
    ] as const) {
      entry.match.reasons.push({
        code: MATCH_REASON_CODE.ambiguousWithOtherSubscription,
        weight: 0,
        value: 0,
        detail: { otherSubscriptionId: other.match.subscriptionId },
      });
    }
  }

  if (top.tier === 'auto' && !ambiguous) return { autoLink: top.match, suggestions: [] };

  return {
    autoLink: null,
    suggestions: ranked.slice(0, MAX_SUGGESTIONS_PER_TRANSACTION).map((entry) => entry.match),
  };
}
