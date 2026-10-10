import type Subscriptions from '@models/subscriptions.model';
import type * as Transactions from '@models/transactions.model';
import { withTransaction } from '@services/common/with-transaction';

import { matchTransaction } from './matching/run-for-transaction';

/**
 * Entry point used by transaction create, bank sync and transaction update: scores the transaction
 * against the user's active recurring payments (see `matching/`) and auto-links it or records
 * suggestions. Returns the auto-linked subscription, or null.
 */
export const matchTransactionToSubscriptions = withTransaction(
  async ({
    transaction,
    userId,
  }: {
    transaction: Transactions.default;
    userId: number;
  }): Promise<Subscriptions | null> => matchTransaction({ transaction, userId }),
);
