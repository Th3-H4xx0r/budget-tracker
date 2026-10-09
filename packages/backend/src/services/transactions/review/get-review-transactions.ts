import { TRANSACTION_REVIEW_STATUS, type TransactionReviewListStatus } from '@bt/shared/types';
import { findTransactions } from '@models/transactions-query';
import { hasAttachmentsAttribute, prepareTXInclude, tagsDisplayInclude } from '@models/transactions.model';
import { Order } from 'sequelize';

import { reviewScope } from './review-scope';

const NEWEST_FIRST: Order = [
  ['time', 'DESC'],
  ['id', 'DESC'],
];

const ORDER_BY_STATUS: Record<TransactionReviewListStatus, Order> = {
  // Never-deferred rows (NULL) come first, oldest transaction first; deferred rows follow in
  // the order they were deferred. Matches the partial index on the unreviewed queue.
  [TRANSACTION_REVIEW_STATUS.unreviewed]: [
    ['reviewDeferredAt', 'ASC NULLS FIRST'],
    ['time', 'ASC'],
    ['id', 'ASC'],
  ],
  [TRANSACTION_REVIEW_STATUS.reviewed]: NEWEST_FIRST,
  [TRANSACTION_REVIEW_STATUS.fraud]: NEWEST_FIRST,
};

/** One page of a review tab, with the splits, tags and `hasAttachments` flag the transaction row renders. */
export const getReviewTransactions = ({
  userId,
  status,
  limit,
  offset,
}: {
  userId: number;
  status: TransactionReviewListStatus;
  limit: number;
  offset: number;
}) =>
  findTransactions({
    ...reviewScope({ userId }),
    completeness: { page: { offset, limit } },
    where: { reviewStatus: status },
    include: [...prepareTXInclude({ includeSplits: true }), tagsDisplayInclude({ required: false })],
    attributes: { include: [hasAttachmentsAttribute] },
    order: ORDER_BY_STATUS[status],
  });
