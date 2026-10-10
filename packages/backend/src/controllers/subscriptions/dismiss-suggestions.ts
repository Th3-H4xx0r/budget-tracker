import { recordId } from '@common/lib/zod/custom-types';
import { createController } from '@controllers/helpers/controller-factory';
import { dismissSubscriptionSuggestions } from '@services/subscriptions/matching/dismiss-suggestions';
import { z } from 'zod';

const schema = z.object({
  params: z.object({ id: recordId() }),
  body: z.object({
    transactionIds: z.array(recordId()).min(1).max(100),
  }),
});

export default createController(schema, async ({ user, params, body }) => {
  const data = await dismissSubscriptionSuggestions({
    userId: user.id,
    subscriptionId: params.id,
    transactionIds: body.transactionIds,
  });

  return { data };
});
