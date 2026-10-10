import {
  type LinkableTransactionItem,
  type LinkableTransactionsResponse,
  type LinkableTransactionsSort,
  type RecordId,
  SUBSCRIPTION_LINK_STATUS,
} from '@bt/shared/types';
import { Money } from '@common/types/money';
import { t } from '@i18n/index';
import { ValidationError } from '@js/errors';
import SubscriptionTransactions from '@models/subscription-transactions.model';
import Subscriptions from '@models/subscriptions.model';
import { findTransactions } from '@models/transactions-query';
import { type TransactionApiResponse, serializeTransaction } from '@root/serializers/transactions.serializer';
import { Op, type WhereOptions } from 'sequelize';

import { findSubscriptionOrThrow } from '../helpers';
import { payeeNameInclude, toScorableTransaction } from './candidate-transactions';
import { createFxConverter, loadLinkState, pairKey } from './link-state';
import { scoreTransaction } from './score-transaction';
import { loadSubscriptionProfiles } from './subscription-profile';

const DEFAULT_LINKABLE_LIMIT = 30;
/** Rows scored when sorting by relevance, which has to rank before paging. */
const RELEVANCE_SCAN_LIMIT = 500;
const MIN_SEARCH_LENGTH = 2;
const AMOUNT_SEARCH_PATTERN = /^-?\d+(?:[.,]\d{1,2})?$/;

type LinkableTransactionApiItem = LinkableTransactionItem<TransactionApiResponse>;

interface SearchLinkableTransactionsParams {
  userId: number;
  subscriptionId: RecordId;
  search?: string;
  /** YYYY-MM-DD, inclusive. */
  from?: string;
  /** YYYY-MM-DD, inclusive. */
  to?: string;
  accountIds?: RecordId[];
  sort?: LinkableTransactionsSort;
  limit?: number;
  offset?: number;
}

const buildSearchWhere = ({ search }: { search: string }): WhereOptions => {
  const pattern = `%${search.replace(/[\\%_]/g, (char) => `\\${char}`)}%`;
  const anyOf: WhereOptions[] = [{ note: { [Op.iLike]: pattern } }, { '$payee.name$': { [Op.iLike]: pattern } }];

  if (AMOUNT_SEARCH_PATTERN.test(search)) {
    const cents = Money.fromDecimal(search.replace(',', '.')).abs().toCents();
    anyOf.push(
      { amount: { [Op.between]: [cents - 1, cents + 1] } },
      { amount: { [Op.between]: [-cents - 1, -cents + 1] } },
    );
  }

  return { [Op.or]: anyOf };
};

/**
 * Searches all of the user's real transactions of the subscription's type for manual linking: no
 * amount, account or date gating beyond the caller's filters. Each row carries the scorer's view of the
 * pair, the subscription it is already linked to (other than this one), and whether the user dismissed
 * it here. Rows already linked to this subscription are left out.
 */
export async function searchLinkableTransactions({
  userId,
  subscriptionId,
  search,
  from,
  to,
  accountIds,
  sort = 'date',
  limit = DEFAULT_LINKABLE_LIMIT,
  offset = 0,
}: SearchLinkableTransactionsParams): Promise<LinkableTransactionsResponse<TransactionApiResponse>> {
  await findSubscriptionOrThrow({ id: subscriptionId, userId });

  if (from && to && from > to) {
    throw new ValidationError({ message: t({ key: 'subscriptions.invalidDateRange' }) });
  }

  const [profile] = await loadSubscriptionProfiles({ userId, subscriptionIds: [subscriptionId] });
  if (!profile) return { items: [], hasMore: false };

  const linkedHere = await SubscriptionTransactions.findAll({
    attributes: ['transactionId'],
    where: { subscriptionId, status: SUBSCRIPTION_LINK_STATUS.active },
  });
  const conditions: WhereOptions[] = [{ transactionType: profile.transactionType }];
  if (linkedHere.length) conditions.push({ id: { [Op.notIn]: linkedHere.map((link) => link.transactionId) } });
  const trimmed = search?.trim();
  if (trimmed && trimmed.length >= MIN_SEARCH_LENGTH) conditions.push(buildSearchWhere({ search: trimmed }));
  if (from) conditions.push({ time: { [Op.gte]: new Date(`${from}T00:00:00.000Z`) } });
  if (to) conditions.push({ time: { [Op.lte]: new Date(`${to}T23:59:59.999Z`) } });
  if (accountIds?.length) conditions.push({ accountId: { [Op.in]: accountIds } });

  const byRelevance = sort === 'relevance';
  const rows = await findTransactions({
    planned: 'exclude',
    access: { accountOwner: userId },
    balanceAdjustments: 'include',
    completeness: byRelevance
      ? { cap: { limit: RELEVANCE_SCAN_LIMIT, onTruncated: 'log', context: { userId, subscriptionId } } }
      : { page: { offset, limit: limit + 1 } },
    where: { [Op.and]: conditions },
    include: [payeeNameInclude()],
    order: [
      ['time', 'DESC'],
      ['id', 'DESC'],
    ],
    subQuery: false,
  });

  const linkState = await loadLinkState({ transactionIds: rows.map((tx) => tx.id) });
  const linkedSubscriptionIds = [...new Set(linkState.activeLinks.values())];
  const linkedSubscriptions = linkedSubscriptionIds.length
    ? await Subscriptions.findAll({ attributes: ['id', 'name'], where: { id: { [Op.in]: linkedSubscriptionIds } } })
    : [];
  const nameById = new Map(linkedSubscriptions.map((subscription) => [subscription.id as string, subscription.name]));
  const fx = createFxConverter({ userId });

  const items: LinkableTransactionApiItem[] = [];
  for (const tx of rows) {
    const match = await scoreTransaction({ profile, transaction: toScorableTransaction({ tx }), fx });
    const linkedId = linkState.activeLinks.get(tx.id);
    items.push({
      transaction: serializeTransaction(tx),
      score: match?.score ?? 0,
      reasons: match?.reasons ?? [],
      linkedSubscription: linkedId ? { id: linkedId as RecordId, name: nameById.get(linkedId) ?? '' } : null,
      isDismissed: linkState.dismissedPairs.has(pairKey({ subscriptionId, transactionId: tx.id })),
    });
  }

  if (byRelevance) {
    items.sort((a, b) => b.score - a.score);
    return { items: items.slice(offset, offset + limit), hasMore: items.length > offset + limit };
  }

  return { items: items.slice(0, limit), hasMore: items.length > limit };
}
