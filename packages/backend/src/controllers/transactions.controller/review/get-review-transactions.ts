import { TRANSACTION_REVIEW_LIST_STATUSES } from '@bt/shared/types';
import { createController } from '@controllers/helpers/controller-factory';
import { serializeTransactions } from '@root/serializers';
import { getReviewTransactions } from '@services/transactions/review/get-review-transactions';
import { z } from 'zod';

const schema = z.object({
  query: z.object({
    status: z.enum(TRANSACTION_REVIEW_LIST_STATUSES),
    limit: z.coerce.number().int().min(1).max(100).default(50),
    offset: z.coerce.number().int().min(0).default(0),
  }),
});

export default createController(schema, async ({ user, query }) => {
  const transactions = await getReviewTransactions({
    userId: user.id,
    status: query.status,
    limit: query.limit,
    offset: query.offset,
  });

  return { data: serializeTransactions(transactions) };
});
