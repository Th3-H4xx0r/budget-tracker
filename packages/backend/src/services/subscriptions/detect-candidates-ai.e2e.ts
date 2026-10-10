import type { RecordId } from '@bt/shared/types';
import {
  AI_PROVIDER,
  SUBSCRIPTION_FREQUENCIES,
  TRANSACTION_TRANSFER_NATURE,
  TRANSACTION_TYPES,
} from '@bt/shared/types';
import { describe, expect, it } from '@jest/globals';
import SubscriptionCandidates from '@models/subscription-candidates.model';
import * as helpers from '@tests/helpers';
import { useSelfHostWithoutServerAiKeys } from '@tests/helpers/ai-test-env';
import { buildTransactionPayload } from '@tests/helpers/transactions';
import { VALID_GEMINI_API_KEY, createGeminiJsonMock } from '@tests/mocks/gemini/mock-api';

const TEST_TIMEOUT_MS = 60_000;

async function createTransactionDaysAgo({
  accountId,
  note,
  amount,
  daysAgo,
}: {
  accountId: RecordId;
  note: string;
  amount: number;
  daysAgo: number;
}) {
  const time = new Date();
  time.setDate(time.getDate() - daysAgo);
  await helpers.createTransaction({
    raw: true,
    payload: buildTransactionPayload({
      accountId,
      amount,
      transactionType: TRANSACTION_TYPES.expense,
      transferNature: TRANSACTION_TRANSFER_NATURE.not_transfer,
      note,
      time: time.toISOString(),
    }),
  });
}

/** Stable amount, irregular timing: the heuristics rate it ambiguous, so it only survives with AI. */
async function seedAmbiguousCluster({ accountId }: { accountId: RecordId }) {
  for (const daysAgo of [115, 55, 48, 3, 0]) {
    await createTransactionDaysAgo({ accountId, note: 'CORNER GYM 5512', amount: 30, daysAgo });
  }
}

/** A regular monthly cluster with a raw (all-caps) descriptor, which is also sent for naming. */
async function seedMonthlyCluster({ accountId, note }: { accountId: RecordId; note: string }) {
  for (const daysAgo of [90, 60, 30, 0]) {
    await createTransactionDaysAgo({ accountId, note, amount: 15.99, daysAgo });
  }
}

/** Saves a user Gemini key; the key check is answered by a handler registered before the detection mock. */
async function configureUserGeminiKey() {
  global.mswMockServer.use(createGeminiJsonMock({ json: [] }));
  const response = await helpers.setAiApiKey({ apiKey: VALID_GEMINI_API_KEY, provider: AI_PROVIDER.google });
  expect(response.statusCode).toBe(200);
}

/** Cluster id the prompt assigned to a merchant key, e.g. "c1". */
function clusterIdFor({ prompt, merchantKey }: { prompt: string; merchantKey: string }): string | null {
  return new RegExp(`"id":"(c\\d+)","merchantKey":"${merchantKey}"`).exec(prompt)?.[1] ?? null;
}

async function expireCooldown({ userId }: { userId: number }) {
  const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000);
  await SubscriptionCandidates.update({ detectedAt: twoHoursAgo }, { where: { userId } });
}

describe('Subscription candidate detection with AI review', () => {
  useSelfHostWithoutServerAiKeys();

  it(
    'accepts and names an ambiguous cluster the AI confirms',
    async () => {
      const account = await helpers.createAccount({ raw: true });
      await seedAmbiguousCluster({ accountId: account.id });
      await configureUserGeminiKey();

      const prompts: string[] = [];
      global.mswMockServer.use(
        createGeminiJsonMock({
          onRequest: (prompt) => prompts.push(prompt),
          respond: (prompt) => [
            {
              id: clusterIdFor({ prompt, merchantKey: 'corner gym' }),
              isRecurring: true,
              name: 'Corner Gym',
              frequency: 'monthly',
              expectedAmount: 30,
              amountVaries: false,
              confidence: 0.9,
              reason: 'Same amount at a gym roughly every month',
            },
          ],
        }),
      );

      const result = await helpers.detectSubscriptionCandidates({ raw: true });

      expect(prompts).toHaveLength(1);
      expect(result.aiStatus).toBe('applied');
      const candidate = result.candidates.find((c) => c.suggestedName === 'Corner Gym');
      expect(candidate).toBeDefined();
      expect(candidate!.detectionSource).toBe('ai');
      expect(candidate!.aiReason).toBe('Same amount at a gym roughly every month');
      expect(candidate!.detectedFrequency).toBe(SUBSCRIPTION_FREQUENCIES.monthly);
    },
    TEST_TIMEOUT_MS,
  );

  it(
    'drops a cluster the AI rejects with high confidence',
    async () => {
      const account = await helpers.createAccount({ raw: true });
      await seedMonthlyCluster({ accountId: account.id, note: 'FRESHMART GROCERY' });
      await configureUserGeminiKey();

      global.mswMockServer.use(
        createGeminiJsonMock({
          respond: (prompt) => [
            {
              id: clusterIdFor({ prompt, merchantKey: 'freshmart grocery' }),
              isRecurring: false,
              confidence: 0.9,
              reason: 'Grocery shopping',
            },
          ],
        }),
      );

      const result = await helpers.detectSubscriptionCandidates({ raw: true });

      expect(result.aiStatus).toBe('applied');
      expect(result.candidates.find((c) => c.suggestedName.includes('FRESHMART'))).toBeUndefined();
    },
    TEST_TIMEOUT_MS,
  );

  it(
    'falls back to heuristic results when the provider fails',
    async () => {
      const account = await helpers.createAccount({ raw: true });
      await seedMonthlyCluster({ accountId: account.id, note: 'NETFLIX.COM' });
      await seedAmbiguousCluster({ accountId: account.id });
      await configureUserGeminiKey();

      global.mswMockServer.use(createGeminiJsonMock({ shouldFail: true, errorStatus: 500 }));

      const result = await helpers.detectSubscriptionCandidates({ raw: true });

      expect(result.aiStatus).toBe('failed');
      const netflix = result.candidates.find((c) => c.suggestedName.includes('NETFLIX'));
      expect(netflix).toBeDefined();
      expect(netflix!.detectionSource).toBe('heuristic');
      // Without an AI confirmation the ambiguous cluster stays out.
      expect(result.candidates.find((c) => c.suggestedName.includes('CORNER GYM'))).toBeUndefined();
    },
    TEST_TIMEOUT_MS,
  );

  it(
    'skips the AI pass without any outbound request when no AI is configured',
    async () => {
      const account = await helpers.createAccount({ raw: true });
      await seedMonthlyCluster({ accountId: account.id, note: 'NETFLIX.COM' });

      let requestCount = 0;
      global.mswMockServer.use(createGeminiJsonMock({ json: [], onRequest: () => (requestCount += 1) }));

      const result = await helpers.detectSubscriptionCandidates({ raw: true });

      expect(result.aiStatus).toBe('skipped');
      expect(requestCount).toBe(0);
      expect(result.candidates.find((c) => c.suggestedName.includes('NETFLIX'))).toBeDefined();
    },
    TEST_TIMEOUT_MS,
  );

  it(
    'does not re-send an unchanged cluster on the next run',
    async () => {
      const account = await helpers.createAccount({ raw: true });
      await seedAmbiguousCluster({ accountId: account.id });
      await configureUserGeminiKey();

      let requestCount = 0;
      global.mswMockServer.use(
        createGeminiJsonMock({
          onRequest: () => (requestCount += 1),
          respond: (prompt) => [
            {
              id: clusterIdFor({ prompt, merchantKey: 'corner gym' }),
              isRecurring: true,
              name: 'Corner Gym',
              frequency: 'monthly',
              confidence: 0.9,
              reason: 'Monthly gym fee',
            },
          ],
        }),
      );

      const first = await helpers.detectSubscriptionCandidates({ raw: true });
      expect(first.aiStatus).toBe('applied');
      expect(requestCount).toBe(1);

      await expireCooldown({ userId: account.userId });
      const second = await helpers.detectSubscriptionCandidates({ raw: true });

      expect(second.isFromCache).toBe(false);
      expect(requestCount).toBe(1);
      const candidate = second.candidates.find((c) => c.suggestedName === 'Corner Gym');
      expect(candidate).toBeDefined();
      expect(candidate!.detectionSource).toBe('ai');
    },
    TEST_TIMEOUT_MS,
  );
});
