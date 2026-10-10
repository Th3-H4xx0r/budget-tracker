import { commaSeparatedRecordIds, dateString, recordId } from '@common/lib/zod/custom-types';
import { createController } from '@controllers/helpers/controller-factory';
import { searchLinkableTransactions } from '@services/subscriptions/matching/search-linkable-transactions';
import { z } from 'zod';

const schema = z.object({
  params: z.object({ id: recordId() }),
  query: z
    .object({
      search: z.string().max(200).optional(),
      from: dateString().optional(),
      to: dateString().optional(),
      accountIds: commaSeparatedRecordIds.optional(),
      sort: z.enum(['date', 'relevance']).optional(),
      limit: z.coerce.number().int().min(1).max(100).optional(),
      offset: z.coerce.number().int().min(0).optional(),
    })
    .optional(),
});

export default createController(schema, async ({ user, params, query }) => {
  const data = await searchLinkableTransactions({
    userId: user.id,
    subscriptionId: params.id,
    search: query?.search,
    from: query?.from,
    to: query?.to,
    accountIds: query?.accountIds,
    sort: query?.sort,
    limit: query?.limit,
    offset: query?.offset,
  });

  return { data };
});
