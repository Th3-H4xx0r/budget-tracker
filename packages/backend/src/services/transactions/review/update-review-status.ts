import { TRANSACTION_REVIEW_ACTION, TRANSACTION_REVIEW_STATUS_BY_ACTION } from '@bt/shared/types';
import { t } from '@i18n/index';
import { NotFoundError } from '@js/errors';
import { updateTransactions } from '@models/transactions-query';
import { withTransaction } from '@services/common/with-transaction';
import { Op } from 'sequelize';

import { reviewScope } from './review-scope';

/**
 * Applies one review action to every listed transaction. Only `check_later` stamps
 * `reviewDeferredAt`; every other action clears it, so `unreviewed` returns a deferred row
 * to the fresh part of the queue. `transactionIds` must be unique (the controller enforces it),
 * since the update count is compared against its length.
 */
const updateReviewStatusImpl = async ({
  userId,
  transactionIds,
  action,
}: {
  userId: number;
  transactionIds: string[];
  action: TRANSACTION_REVIEW_ACTION;
}): Promise<{ updatedCount: number }> => {
  const [updatedCount] = await updateTransactions({
    ...reviewScope({ userId }),
    where: { id: { [Op.in]: transactionIds } },
    values: {
      reviewStatus: TRANSACTION_REVIEW_STATUS_BY_ACTION[action],
      reviewDeferredAt: action === TRANSACTION_REVIEW_ACTION.checkLater ? new Date() : null,
    },
  });

  // A shortfall means an id is missing or owned by someone else. Throwing rolls back the
  // rows already updated, so the batch applies to all ids or none.
  if (updatedCount !== transactionIds.length) {
    throw new NotFoundError({ message: t({ key: 'transactions.notFound' }) });
  }

  return { updatedCount };
};

export const updateReviewStatus = withTransaction(updateReviewStatusImpl);
