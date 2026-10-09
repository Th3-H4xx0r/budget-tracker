import { TRANSACTION_REVIEW_ACTION } from '@bt/shared/types';
import { uniqueRecordIds } from '@common/lib/zod/custom-types';
import { createController } from '@controllers/helpers/controller-factory';
import { updateReviewStatus } from '@services/transactions/review/update-review-status';
import { z } from 'zod';

const schema = z.object({
  body: z.object({
    transactionIds: uniqueRecordIds({ min: 1, max: 100 }),
    action: z.nativeEnum(TRANSACTION_REVIEW_ACTION),
  }),
});

export default createController(schema, async ({ user, body }) => {
  const data = await updateReviewStatus({
    userId: user.id,
    transactionIds: body.transactionIds,
    action: body.action,
  });

  return { data };
});
