import { isTwoLegTransfer } from '@bt/shared/types';
import Payees from '@models/payees.model';
import type Subscriptions from '@models/subscriptions.model';
import type Transactions from '@models/transactions.model';

import { applyMatchDecision } from './apply-decisions';
import { toScorableTransaction } from './candidate-transactions';
import { decideMatches } from './decide-matches';
import { createFxConverter, loadLinkState, pairKey } from './link-state';
import { scoreTransaction } from './score-transaction';
import { loadSubscriptionProfiles } from './subscription-profile';
import type { MatchScore } from './types';

/**
 * Scores one transaction against every active recurring payment of the user and applies the decision:
 * auto-link, pending suggestions, or nothing. Skips transactions that are actively linked; pairs the
 * user dismissed or unlinked stay excluded. Returns the auto-linked subscription, if any.
 * Callers run it inside `withTransaction`.
 */
export async function matchTransaction({
  transaction,
  userId,
}: {
  transaction: Transactions;
  userId: number;
}): Promise<Subscriptions | null> {
  if (isTwoLegTransfer(transaction.transferNature)) return null;

  const linkState = await loadLinkState({ transactionIds: [transaction.id] });
  if (linkState.activeLinks.has(transaction.id)) return null;

  const profiles = await loadSubscriptionProfiles({ userId });
  if (profiles.length === 0) return null;

  const payee = transaction.payeeId
    ? await Payees.findOne({ attributes: ['name'], where: { id: transaction.payeeId } })
    : null;
  const scorable = { ...toScorableTransaction({ tx: transaction }), payeeName: payee?.name ?? null };

  const fx = createFxConverter({ userId });
  const scored: MatchScore[] = [];
  for (const profile of profiles) {
    if (linkState.blockedPairs.has(pairKey({ subscriptionId: profile.id, transactionId: transaction.id }))) continue;
    const match = await scoreTransaction({ profile, transaction: scorable, fx });
    if (match) scored.push(match);
  }

  const linked = await applyMatchDecision({
    userId,
    transaction: scorable,
    decision: decideMatches({ scored }),
    profilesById: new Map(profiles.map((profile) => [profile.id, profile])),
  });

  return linked?.subscription ?? null;
}
