import { type RecordId, SUBSCRIPTION_LINK_STATUS, SUBSCRIPTION_SUGGESTION_STATUS } from '@bt/shared/types';
import type { Money } from '@common/types/money';
import SubscriptionMatchSuggestions from '@models/subscription-match-suggestions.model';
import SubscriptionTransactions from '@models/subscription-transactions.model';
import { calculateRefAmount } from '@services/calculate-ref-amount.service';
import { Op } from 'sequelize';

import { toDateOnly } from './expected-dates';
import type { FxConvert } from './types';

export const pairKey = ({ subscriptionId, transactionId }: { subscriptionId: string; transactionId: string }) =>
  `${subscriptionId}:${transactionId}`;

export interface LinkState {
  /** transactionId → subscriptionId of its active link. */
  activeLinks: Map<string, string>;
  /** Pairs the user rejected: dismissed suggestions and links unlinked from that subscription. */
  blockedPairs: Set<string>;
  dismissedPairs: Set<string>;
}

/** Link state of the given transactions across all subscriptions. */
export async function loadLinkState({ transactionIds }: { transactionIds: RecordId[] }): Promise<LinkState> {
  const state: LinkState = { activeLinks: new Map(), blockedPairs: new Set(), dismissedPairs: new Set() };
  if (transactionIds.length === 0) return state;

  const [links, dismissed] = await Promise.all([
    SubscriptionTransactions.findAll({
      attributes: ['subscriptionId', 'transactionId', 'status'],
      where: { transactionId: { [Op.in]: transactionIds } },
    }),
    SubscriptionMatchSuggestions.findAll({
      attributes: ['subscriptionId', 'transactionId'],
      where: { transactionId: { [Op.in]: transactionIds }, status: SUBSCRIPTION_SUGGESTION_STATUS.dismissed },
    }),
  ]);

  for (const link of links) {
    if (link.status === SUBSCRIPTION_LINK_STATUS.active) state.activeLinks.set(link.transactionId, link.subscriptionId);
    else state.blockedPairs.add(pairKey(link));
  }
  for (const row of dismissed) {
    state.blockedPairs.add(pairKey(row));
    state.dismissedPairs.add(pairKey(row));
  }

  return state;
}

/** FX conversion memoised per (date, pair) for one run; a missing rate yields null (neutral signal). */
export function createFxConverter({ userId }: { userId: number }): FxConvert {
  const cache = new Map<string, Promise<Money | null>>();

  return ({ amount, date, from, to }) => {
    const key = `${toDateOnly({ date })}:${from}:${to}:${amount.toCents()}`;
    let pending = cache.get(key);
    if (!pending) {
      pending = calculateRefAmount({ amount, userId, date, baseCode: from, quoteCode: to }).catch(() => null);
      cache.set(key, pending);
    }
    return pending;
  };
}
