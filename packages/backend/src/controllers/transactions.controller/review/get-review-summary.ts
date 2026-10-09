import { createController } from '@controllers/helpers/controller-factory';
import { getReviewSummary } from '@services/transactions/review/get-review-summary';
import { z } from 'zod';

const schema = z.object({});

export default createController(schema, async ({ user }) => {
  const data = await getReviewSummary({ userId: user.id });

  return { data };
});
