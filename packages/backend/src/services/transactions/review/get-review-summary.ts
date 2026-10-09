import { TRANSACTION_REVIEW_STATUS } from '@bt/shared/types';
import { countTransactions } from '@models/transactions-query';

import { reviewScope } from './review-scope';

interface ReviewSummary {
  unreviewedCount: number;
  fraudCount: number;
}

const countByStatus = ({ userId, reviewStatus }: { userId: number; reviewStatus: TRANSACTION_REVIEW_STATUS }) =>
  countTransactions({ ...reviewScope({ userId }), where: { reviewStatus } });

export const getReviewSummary = async ({ userId }: { userId: number }): Promise<ReviewSummary> => {
  const [unreviewedCount, fraudCount] = await Promise.all([
    countByStatus({ userId, reviewStatus: TRANSACTION_REVIEW_STATUS.unreviewed }),
    countByStatus({ userId, reviewStatus: TRANSACTION_REVIEW_STATUS.fraud }),
  ]);

  return { unreviewedCount, fraudCount };
};
