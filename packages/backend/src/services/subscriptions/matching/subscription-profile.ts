import { type RecordId, SUBSCRIPTION_LINK_STATUS } from '@bt/shared/types';
import { Money } from '@common/types/money';
import PayeeAliases from '@models/payee-aliases.model';
import Payees from '@models/payees.model';
import SubscriptionPeriods from '@models/subscription-periods.model';
import SubscriptionTransactions from '@models/subscription-transactions.model';
import Subscriptions from '@models/subscriptions.model';
import { findTransactions } from '@models/transactions-query';
import type Transactions from '@models/transactions.model';
import { Op } from 'sequelize';

import { toDateOnly } from './expected-dates';
import { buildMerchantKey } from './merchant-key';
import type { ProfileAmount, SubscriptionProfile } from './types';

const LEARNED_AMOUNT_SAMPLE = 6;
const LEARNED_TOKEN_MIN_SHARE = 0.3;
const LEARNED_TOKEN_MAX = 5;
const VARIABLE_AMOUNT_RATIO = 0.15;

const median = ({ values }: { values: number[] }): number => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid]! : (sorted[mid - 1]! + sorted[mid]!) / 2;
};

const learnAmount = ({ linked }: { linked: Transactions[] }): ProfileAmount | null => {
  const latest = linked[0];
  if (!latest) return null;

  const sample = linked
    .filter((tx) => tx.currencyCode === latest.currencyCode)
    .slice(0, LEARNED_AMOUNT_SAMPLE)
    .map((tx) => tx.amount.abs().toNumber());
  const center = median({ values: sample });
  if (center === 0) return null;

  const mad = median({ values: sample.map((value) => Math.abs(value - center)) });
  return {
    expected: Money.fromDecimal(center),
    currencyCode: latest.currencyCode,
    learned: true,
    variable: mad / center > VARIABLE_AMOUNT_RATIO,
  };
};

const learnTokens = ({ linked }: { linked: Transactions[] }): string[][] => {
  if (linked.length === 0) return [];

  const counts = new Map<string, { tokens: string[]; count: number }>();
  for (const tx of linked) {
    const merchantKey = buildMerchantKey({ raw: tx.note });
    if (!merchantKey.key) continue;
    const entry = counts.get(merchantKey.key) ?? { tokens: merchantKey.key.split(' '), count: 0 };
    entry.count += 1;
    counts.set(merchantKey.key, entry);
  }

  return [...counts.values()]
    .filter((entry) => entry.count / linked.length >= LEARNED_TOKEN_MIN_SHARE)
    .sort((a, b) => b.count - a.count)
    .slice(0, LEARNED_TOKEN_MAX)
    .map((entry) => entry.tokens);
};

/**
 * Loads the scoring profile of the user's recurring payments: the active ones by default, or exactly
 * `subscriptionIds` (active or not) when given.
 */
export async function loadSubscriptionProfiles({
  userId,
  subscriptionIds,
}: {
  userId: number;
  subscriptionIds?: RecordId[];
}): Promise<SubscriptionProfile[]> {
  const subscriptions = await Subscriptions.findAll({
    where: subscriptionIds ? { userId, id: { [Op.in]: subscriptionIds } } : { userId, isActive: true },
  });
  if (subscriptions.length === 0) return [];

  const ids = subscriptions.map((subscription) => subscription.id);

  const [periods, links] = await Promise.all([
    SubscriptionPeriods.findAll({ where: { subscriptionId: { [Op.in]: ids } }, order: [['dueDate', 'ASC']] }),
    SubscriptionTransactions.findAll({
      attributes: ['subscriptionId', 'transactionId'],
      where: { subscriptionId: { [Op.in]: ids }, status: SUBSCRIPTION_LINK_STATUS.active },
    }),
  ]);

  // Link ids come from this user's own subscriptions, so the row set is already authorized.
  const linkedTxs = links.length
    ? await findTransactions({
        where: { id: { [Op.in]: links.map((link) => link.transactionId) } },
        planned: 'exclude',
        access: 'unscoped-internal',
        balanceAdjustments: 'include',
        completeness: 'all',
        attributes: ['id', 'note', 'payeeId', 'amount', 'currencyCode', 'time', 'accountId'],
        order: [['time', 'DESC']],
      })
    : [];
  const txById = new Map(linkedTxs.map((tx) => [tx.id, tx]));

  const payeeIds = new Set<string>();
  for (const subscription of subscriptions) if (subscription.payeeId) payeeIds.add(subscription.payeeId);
  for (const tx of linkedTxs) if (tx.payeeId) payeeIds.add(tx.payeeId);

  const [payees, aliases] = payeeIds.size
    ? await Promise.all([
        Payees.findAll({ attributes: ['id', 'name'], where: { id: { [Op.in]: [...payeeIds] }, userId } }),
        PayeeAliases.findAll({ attributes: ['payeeId', 'rawName'], where: { payeeId: { [Op.in]: [...payeeIds] } } }),
      ])
    : [[], []];

  const namesByPayeeId = new Map<string, string[]>();
  for (const payee of payees) namesByPayeeId.set(payee.id, [payee.name]);
  for (const alias of aliases) namesByPayeeId.get(alias.payeeId)?.push(alias.rawName);

  return subscriptions.map((subscription) => {
    const linked = links
      .filter((link) => link.subscriptionId === subscription.id)
      .map((link) => txById.get(link.transactionId))
      .filter((tx): tx is Transactions => !!tx)
      .sort((a, b) => b.time.getTime() - a.time.getTime());

    const profilePayeeIds = new Set<string>();
    if (subscription.payeeId) profilePayeeIds.add(subscription.payeeId);
    for (const tx of linked) if (tx.payeeId) profilePayeeIds.add(tx.payeeId);

    const aliasTokens = [...profilePayeeIds]
      .flatMap((payeeId) => namesByPayeeId.get(payeeId) ?? [])
      .map((name) => buildMerchantKey({ raw: name }).tokens)
      .filter((tokens) => tokens.length > 0);

    const keywords = (subscription.matchingRules?.rules ?? [])
      .filter((rule) => rule.field === 'note' && rule.operator === 'contains_any' && Array.isArray(rule.value))
      .flatMap((rule) => (rule.value as string[]).map((value) => value.toLowerCase()));

    const accounts = new Set<string>();
    if (subscription.accountId) accounts.add(subscription.accountId);
    for (const tx of linked) accounts.add(tx.accountId);

    const expectedAmount =
      subscription.expectedAmount && subscription.expectedCurrencyCode && !subscription.expectedAmount.isZero()
        ? {
            expected: subscription.expectedAmount.abs(),
            currencyCode: subscription.expectedCurrencyCode,
            learned: false,
            variable: false,
          }
        : learnAmount({ linked });

    const anchor = subscription.dueDate ?? subscription.startDate ?? null;

    return {
      subscription,
      id: subscription.id,
      transactionType: subscription.transactionType,
      frequency: subscription.frequency,
      scopedAccountId: subscription.accountId,
      categoryId: subscription.categoryId,
      payeeIds: profilePayeeIds,
      nameTokens: buildMerchantKey({ raw: subscription.name }).tokens,
      aliasTokens,
      learnedTokens: learnTokens({ linked }),
      keywords,
      amount: expectedAmount,
      accounts,
      anchor,
      anchorDay: subscription.anchorDay ?? (anchor ? new Date(`${anchor}T00:00:00Z`).getUTCDate() : null),
      periods: periods
        .filter((period) => period.subscriptionId === subscription.id)
        .map((period) => ({
          id: period.id,
          dueDate: period.dueDate,
          status: period.status,
          transactionId: period.transactionId,
        })),
      linkedDates: linked.map((tx) => toDateOnly({ date: tx.time })),
      rules: subscription.matchingRules?.rules ?? [],
    };
  });
}
