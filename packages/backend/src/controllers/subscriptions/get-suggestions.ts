import { recordId } from '@common/lib/zod/custom-types';
import { createController } from '@controllers/helpers/controller-factory';
import { getSubscriptionSuggestions } from '@services/subscriptions/matching/get-suggestions';
import { z } from 'zod';

const schema = z.object({
  params: z.object({ id: recordId() }),
  query: z
    .object({
      limit: z.coerce.number().int().min(1).max(100).optional(),
    })
    .optional(),
});

export default createController(schema, async ({ user, params, query }) => {
  const data = await getSubscriptionSuggestions({
    userId: user.id,
    subscriptionId: params.id,
    limit: query?.limit,
  });

  return { data };
});
