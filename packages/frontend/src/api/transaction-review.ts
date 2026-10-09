import { api } from '@/api/_api';
import type { TransactionModel } from '@bt/shared/types/db-models';
import { TRANSACTION_REVIEW_ACTION, type TransactionReviewListStatus } from '@bt/shared/types/enums';

export interface TransactionReviewSummary {
  unreviewedCount: number;
  fraudCount: number;
}

export const loadTransactionReviewSummary = async (): Promise<TransactionReviewSummary> => {
  return api.get('/transactions/review/summary');
};

/** Unreviewed rows come in queue order (fresh oldest-first, then deferred); the other tabs newest-first. */
export const loadTransactionsForReview = async ({
  status,
  limit,
  offset,
}: {
  status: TransactionReviewListStatus;
  limit: number;
  offset: number;
}): Promise<TransactionModel[]> => {
  return api.get('/transactions/review', { status, limit, offset });
};

export const updateTransactionsReview = async ({
  transactionIds,
  action,
}: {
  transactionIds: string[];
  action: TRANSACTION_REVIEW_ACTION;
}): Promise<{ updatedCount: number }> => {
  return api.put('/transactions/review', { transactionIds, action });
};
