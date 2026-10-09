import type { TRANSACTION_REVIEW_ACTION, TRANSACTION_REVIEW_STATUS } from '@bt/shared/types';
import type { TransactionApiResponse } from '@root/serializers/transactions.serializer';
import type { getReviewSummary as apiGetReviewSummary } from '@services/transactions/review/get-review-summary';
import type { updateReviewStatus as apiUpdateReviewStatus } from '@services/transactions/review/update-review-status';

import { makeRequest } from './common';

export function getReviewSummary<R extends boolean | undefined = undefined>({ raw }: { raw?: R } = {}) {
  return makeRequest<Awaited<ReturnType<typeof apiGetReviewSummary>>, R>({
    method: 'get',
    url: '/transactions/review/summary',
    raw,
  });
}

/** `status` takes every review status, not only the three listable ones, so tests can send
 *  `not_required` (or omit it) to exercise validation. */
export function getReviewTransactions<R extends boolean | undefined = undefined>({
  status,
  limit,
  offset,
  raw,
}: {
  status?: TRANSACTION_REVIEW_STATUS;
  limit?: number;
  offset?: number;
  raw?: R;
}) {
  return makeRequest<TransactionApiResponse[], R>({
    method: 'get',
    url: '/transactions/review',
    payload: {
      ...(status !== undefined && { status }),
      ...(limit !== undefined && { limit }),
      ...(offset !== undefined && { offset }),
    },
    raw,
  });
}

export function updateReviewStatus<R extends boolean | undefined = undefined>({
  payload,
  raw,
}: {
  payload: { transactionIds: string[]; action: TRANSACTION_REVIEW_ACTION };
  raw?: R;
}) {
  return makeRequest<Awaited<ReturnType<typeof apiUpdateReviewStatus>>, R>({
    method: 'put',
    url: '/transactions/review',
    payload,
    raw,
  });
}
