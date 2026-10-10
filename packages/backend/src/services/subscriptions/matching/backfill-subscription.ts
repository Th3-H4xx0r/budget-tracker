import type { RecordId } from '@bt/shared/types';
import { logger } from '@js/utils/logger';
import { namespace } from '@models/connection';
import { withTransaction } from '@services/common/with-transaction';
import { addDays, subDays } from 'date-fns';
import type { Transaction } from 'sequelize';

import { applyMatchDecision } from './apply-decisions';
import { findCandidateTransactions, toScorableTransaction } from './candidate-transactions';
import { decideMatches } from './decide-matches';
import { createFxConverter, loadLinkState, pairKey } from './link-state';
import { scoreTransaction } from './score-transaction';
import { loadSubscriptionProfiles } from './subscription-profile';
import type { MatchScore } from './types';

const BACKFILL_DAYS_BACK = 400;
const BACKFILL_DAYS_FORWARD = 7;

/**
 * Re-scans the user's history for one recurring payment: candidates from the SQL prefilter are scored
 * against every active profile, so a transaction that fits another payment better is not taken.
 * Auto-links become links (and paid open periods); suggestions become pending rows.
 */
const backfillSubscriptionMatches = withTransaction(
  async ({ userId, subscriptionId }: { userId: number; subscriptionId: RecordId }): Promise<{ linked: number }> => {
    const [target] = await loadSubscriptionProfiles({ userId, subscriptionIds: [subscriptionId] });
    if (!target || !target.subscription.isActive) return { linked: 0 };

    const now = new Date();
    const candidates = await findCandidateTransactions({
      userId,
      profile: target,
      from: subDays(now, BACKFILL_DAYS_BACK),
      to: addDays(now, BACKFILL_DAYS_FORWARD),
    });
    if (candidates.length === 0) return { linked: 0 };

    const others = (await loadSubscriptionProfiles({ userId })).filter((profile) => profile.id !== target.id);
    const profiles = [target, ...others];
    const profilesById = new Map(profiles.map((profile) => [profile.id, profile]));
    const linkState = await loadLinkState({ transactionIds: candidates.map((tx) => tx.id) });
    const fx = createFxConverter({ userId });

    let linked = 0;
    for (const tx of candidates) {
      const transaction = toScorableTransaction({ tx });
      const scored: MatchScore[] = [];
      for (const profile of profiles) {
        if (linkState.blockedPairs.has(pairKey({ subscriptionId: profile.id, transactionId: tx.id }))) continue;
        const match = await scoreTransaction({ profile, transaction, fx });
        if (match) scored.push(match);
      }

      const decision = decideMatches({ scored });
      // The backfill only writes on behalf of the target; other payments keep their own runs. Explicit
      // rules link incoming charges automatically, but history they match is offered for confirmation:
      // a broad note keyword written for new charges can sweep in unrelated past rows.
      const targetAutoLink = decision.autoLink?.subscriptionId === target.id ? decision.autoLink : null;
      const forTarget = {
        autoLink: targetAutoLink && !targetAutoLink.ruleMatch ? targetAutoLink : null,
        suggestions: [
          ...(targetAutoLink?.ruleMatch ? [targetAutoLink] : []),
          ...decision.suggestions.filter((match) => match.subscriptionId === target.id),
        ],
      };
      const result = await applyMatchDecision({ userId, transaction, decision: forTarget, profilesById });
      if (result) linked += 1;
    }

    return { linked };
  },
);

/**
 * Runs the backfill once the surrounding DB transaction commits (immediately when none is active), in
 * its own transaction, so a backfill failure never rolls back the subscription write that triggered it.
 * Awaited by Sequelize's commit, so the HTTP response already reflects its links.
 */
export function backfillSubscriptionMatchesAfterCommit({
  userId,
  subscriptionId,
}: {
  userId: number;
  subscriptionId: RecordId;
}): Promise<void> | void {
  const run = async () => {
    try {
      await backfillSubscriptionMatches({ userId, subscriptionId });
    } catch (error) {
      logger.error({ message: `Subscription match backfill failed for ${subscriptionId}`, error: error as Error });
    }
  };

  const transaction = namespace.get('transaction') as (Transaction & { finished?: string }) | undefined;
  if (transaction && !transaction.finished) {
    transaction.afterCommit(run);
    return;
  }
  return run();
}
