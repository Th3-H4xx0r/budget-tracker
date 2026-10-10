import {
  type DismissSubscriptionSuggestionsResponse,
  type RecordId,
  SUBSCRIPTION_SUGGESTION_SOURCE,
  SUBSCRIPTION_SUGGESTION_STATUS,
} from '@bt/shared/types';
import { t } from '@i18n/index';
import { NotFoundError } from '@js/errors';
import SubscriptionMatchSuggestions from '@models/subscription-match-suggestions.model';
import { findTransactions } from '@models/transactions-query';
import { withTransaction } from '@services/common/with-transaction';
import { Op } from 'sequelize';

import { findSubscriptionOrThrow } from '../helpers';

/**
 * "Not this one": stores a dismissed row per (subscription, transaction) pair, so the matcher never
 * suggests or auto-links the pair again. An explicit link later deletes the row.
 */
export const dismissSubscriptionSuggestions = withTransaction(
  async ({
    userId,
    subscriptionId,
    transactionIds,
  }: {
    userId: number;
    subscriptionId: RecordId;
    transactionIds: RecordId[];
  }): Promise<DismissSubscriptionSuggestionsResponse> => {
    await findSubscriptionOrThrow({ id: subscriptionId, userId });

    const uniqueIds = [...new Set(transactionIds)];
    const txs = await findTransactions({
      where: { id: { [Op.in]: uniqueIds } },
      planned: 'include',
      access: { creator: userId },
      balanceAdjustments: 'include',
      completeness: 'all',
      attributes: ['id'],
    });
    if (txs.length !== uniqueIds.length) {
      throw new NotFoundError({ message: t({ key: 'subscriptions.transactionsNotFoundOrNotBelongToUser' }) });
    }

    await SubscriptionMatchSuggestions.bulkCreate(
      uniqueIds.map((transactionId) => ({
        subscriptionId,
        transactionId,
        userId,
        score: 0,
        reasons: [],
        status: SUBSCRIPTION_SUGGESTION_STATUS.dismissed,
        source: SUBSCRIPTION_SUGGESTION_SOURCE.engine,
      })),
      { updateOnDuplicate: ['status', 'updatedAt'] },
    );

    return { dismissed: uniqueIds.length };
  },
);
