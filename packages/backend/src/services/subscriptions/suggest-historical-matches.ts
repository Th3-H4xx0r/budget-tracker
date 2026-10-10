import {
  type RecordId,
  SUBSCRIPTION_LINK_STATUS,
  SUBSCRIPTION_SUGGESTION_STATUS,
  type SubscriptionMatchingRule,
} from '@bt/shared/types';
import { Money } from '@common/types/money';
import SubscriptionMatchSuggestions from '@models/subscription-match-suggestions.model';
import SubscriptionTransactions from '@models/subscription-transactions.model';
import { findTransactions } from '@models/transactions-query';
import { serializeTransactions } from '@root/serializers/transactions.serializer';
import { startOfDay, subMonths } from 'date-fns';
import { Op, type WhereOptions } from 'sequelize';

import { findSubscriptionOrThrow } from './helpers';
import { toScorableTransaction } from './matching/candidate-transactions';
import { getSubscriptionSuggestions } from './matching/get-suggestions';
import { evaluateRule } from './matching/legacy-rules';
import { createFxConverter } from './matching/link-state';

const HISTORICAL_MONTHS = 12;
const MAX_SUGGESTIONS = 100;

/**
 * `GET /subscriptions/:id/suggest-matches`, kept for shipped clients: the ranked suggestions of
 * `GET /subscriptions/:id/suggestions` reduced to their transactions, followed by every transaction of
 * the last 12 months that passes all of the subscription's explicit matching rules (cross-currency
 * amount rules after conversion). Rows actively linked to this subscription or dismissed for it are
 * left out.
 */
export const suggestHistoricalMatches = async ({
  subscriptionId,
  userId,
}: {
  subscriptionId: RecordId;
  userId: number;
}) => {
  const { suggestions } = await getSubscriptionSuggestions({ userId, subscriptionId, limit: MAX_SUGGESTIONS });
  const scored = suggestions.map((suggestion) => suggestion.transaction);

  const ruleMatches = await findRuleMatchingTransactions({ subscriptionId, userId });
  const scoredIds = new Set(scored.map((tx) => tx.id));

  return [...scored, ...ruleMatches.filter((tx) => !scoredIds.has(tx.id))].slice(0, MAX_SUGGESTIONS);
};

/** SQL-expressible part of the rules; amount rules in another currency are checked after conversion. */
function buildWhereFromRules({ rules }: { rules: SubscriptionMatchingRule[] }): {
  sqlConditions: WhereOptions[];
  hasCrossCurrencyAmountRule: boolean;
} {
  const sqlConditions: WhereOptions[] = [];
  let hasCrossCurrencyAmountRule = false;

  for (const rule of rules) {
    if (rule.field === 'note' && rule.operator === 'contains_any' && Array.isArray(rule.value)) {
      sqlConditions.push({
        note: { [Op.or]: (rule.value as string[]).map((value) => ({ [Op.iLike]: `%${value}%` })) },
      });
    } else if (
      rule.field === 'amount' &&
      rule.operator === 'between' &&
      typeof rule.value === 'object' &&
      !Array.isArray(rule.value)
    ) {
      if (rule.currencyCode) {
        hasCrossCurrencyAmountRule = true;
      } else {
        // Rule bounds are decimals; the `amount` column holds cents.
        const { min, max } = rule.value as { min: number; max: number };
        sqlConditions.push({
          amount: { [Op.between]: [Money.fromDecimal(min).toCents(), Money.fromDecimal(max).toCents()] },
        });
      }
    } else if (rule.field === 'transactionType' && rule.operator === 'equals') {
      sqlConditions.push({ transactionType: rule.value as string });
    } else if (rule.field === 'accountId' && rule.operator === 'equals') {
      sqlConditions.push({ accountId: rule.value as string });
    }
  }

  return { sqlConditions, hasCrossCurrencyAmountRule };
}

async function findRuleMatchingTransactions({ subscriptionId, userId }: { subscriptionId: RecordId; userId: number }) {
  const subscription = await findSubscriptionOrThrow({ id: subscriptionId, userId });
  const rules = subscription.matchingRules?.rules ?? [];
  if (rules.length === 0) return [];

  const { sqlConditions, hasCrossCurrencyAmountRule } = buildWhereFromRules({ rules });
  if (sqlConditions.length === 0 && !hasCrossCurrencyAmountRule) return [];

  const [linked, dismissed] = await Promise.all([
    SubscriptionTransactions.findAll({
      attributes: ['transactionId'],
      where: { subscriptionId, status: SUBSCRIPTION_LINK_STATUS.active },
    }),
    SubscriptionMatchSuggestions.findAll({
      attributes: ['transactionId'],
      where: { subscriptionId, status: SUBSCRIPTION_SUGGESTION_STATUS.dismissed },
    }),
  ]);
  const excludedIds = [...linked, ...dismissed].map((row) => row.transactionId);

  // Snapped to start-of-day so a transaction doesn't drop out partway through the day.
  const cutoffDate = startOfDay(subMonths(new Date(), HISTORICAL_MONTHS));
  // Cross-currency rules filter after conversion, so over-fetch to keep up to MAX_SUGGESTIONS.
  const fetchLimit = hasCrossCurrencyAmountRule ? MAX_SUGGESTIONS * 3 : MAX_SUGGESTIONS;

  const transactions = await findTransactions({
    planned: 'exclude',
    access: { creator: userId },
    balanceAdjustments: 'include',
    completeness: { cap: { limit: fetchLimit, onTruncated: 'log', context: { userId, subscriptionId } } },
    where: {
      time: { [Op.gte]: cutoffDate },
      transactionType: subscription.transactionType,
      ...(sqlConditions.length > 0 && { [Op.and]: sqlConditions }),
      ...(excludedIds.length > 0 && { id: { [Op.notIn]: excludedIds } }),
    },
    order: [['time', 'DESC']],
  });

  // Every rule is re-checked in memory with the matcher's own semantics; this is what applies
  // cross-currency amount rules (converted, ±5% tolerance).
  const fx = createFxConverter({ userId });
  const matching: typeof transactions = [];
  for (const tx of transactions) {
    const transaction = toScorableTransaction({ tx });
    let passes = true;
    for (const rule of rules) {
      if (!(await evaluateRule({ rule, transaction, fx }))) {
        passes = false;
        break;
      }
    }
    if (passes) matching.push(tx);
    if (matching.length === MAX_SUGGESTIONS) break;
  }

  return serializeTransactions(matching);
}
