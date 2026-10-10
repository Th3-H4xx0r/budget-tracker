import { SUBSCRIPTION_LINK_STATUS } from '@bt/shared/types';
import Payees from '@models/payees.model';
import { findTransactions } from '@models/transactions-query';
import type Transactions from '@models/transactions.model';
import { Op, type WhereOptions, literal } from 'sequelize';

import type { ScorableTransaction, SubscriptionProfile } from './types';

const MIN_ILIKE_TOKEN_LENGTH = 3;
const AMOUNT_BAND = 0.5;
export const CANDIDATE_LIMIT = 2000;

/** Excludes transactions with an active link to any subscription. */
export const notActivelyLinkedWhere = (): WhereOptions =>
  literal(
    `NOT EXISTS (SELECT 1 FROM "SubscriptionTransactions" AS st WHERE st."transactionId" = "Transactions"."id" AND st."status" = '${SUBSCRIPTION_LINK_STATUS.active}')`,
  ) as unknown as WhereOptions;

export const payeeNameInclude = () => ({ model: Payees, attributes: ['id', 'name'], required: false });

export const toScorableTransaction = ({ tx }: { tx: Transactions }): ScorableTransaction => ({
  id: tx.id,
  transactionType: tx.transactionType,
  transferNature: tx.transferNature,
  amount: tx.amount,
  currencyCode: tx.currencyCode,
  time: tx.time,
  note: tx.note,
  payeeId: tx.payeeId,
  payeeName: tx.payee?.name ?? null,
  accountId: tx.accountId,
  categoryId: tx.categoryId,
  isPlanned: tx.isPlanned,
});

const escapeLike = ({ value }: { value: string }) => value.replace(/[\\%_]/g, (char) => `\\${char}`);

/**
 * SQL prefilter for backfill and live suggestions: the user's real, not actively linked transactions
 * of the subscription's type inside [from, to] that share a payee, contain a name/alias/keyword/learned
 * token, or sit within ±50% of the expected amount. Newest first, at most 2,000 rows.
 */
export async function findCandidateTransactions({
  userId,
  profile,
  from,
  to,
  limit = CANDIDATE_LIMIT,
}: {
  userId: number;
  profile: SubscriptionProfile;
  from: Date;
  to: Date;
  limit?: number;
}): Promise<Transactions[]> {
  const tokens = new Set<string>();
  for (const list of [profile.nameTokens, ...profile.aliasTokens, ...profile.learnedTokens]) {
    for (const token of list) if (token.length >= MIN_ILIKE_TOKEN_LENGTH) tokens.add(token);
  }
  for (const keyword of profile.keywords) if (keyword.length >= MIN_ILIKE_TOKEN_LENGTH) tokens.add(keyword);

  const anyOf: WhereOptions[] = [];
  if (profile.payeeIds.size > 0) anyOf.push({ payeeId: { [Op.in]: [...profile.payeeIds] } });
  if (tokens.size > 0) {
    anyOf.push({ note: { [Op.iLike]: { [Op.any]: [...tokens].map((token) => `%${escapeLike({ value: token })}%`) } } });
  }
  if (profile.amount) {
    const expectedCents = profile.amount.expected.toCents();
    const min = Math.floor(expectedCents * (1 - AMOUNT_BAND));
    const max = Math.ceil(expectedCents * (1 + AMOUNT_BAND));
    anyOf.push({
      currencyCode: profile.amount.currencyCode,
      [Op.or]: [{ amount: { [Op.between]: [min, max] } }, { amount: { [Op.between]: [-max, -min] } }],
    });
  }
  if (anyOf.length === 0) return [];

  return findTransactions({
    planned: 'exclude',
    access: { accountOwner: userId },
    balanceAdjustments: 'include',
    completeness: { cap: { limit, onTruncated: 'log', context: { userId, subscriptionId: profile.id } } },
    where: {
      transactionType: profile.transactionType,
      time: { [Op.between]: [from, to] },
      [Op.and]: [notActivelyLinkedWhere(), { [Op.or]: anyOf }],
    },
    include: [payeeNameInclude()],
    order: [['time', 'DESC']],
  });
}
