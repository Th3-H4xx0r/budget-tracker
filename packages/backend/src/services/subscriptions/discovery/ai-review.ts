import { AI_FEATURE, AI_PROVIDER, type DetectionAiStatus, SUBSCRIPTION_FREQUENCIES } from '@bt/shared/types';
import { Money } from '@common/types/money';
import { logger } from '@js/utils/logger';
import {
  AI_MAX_OUTPUT_TOKENS,
  aiCallGuards,
  classifyAiCallFailure,
  createAIClient,
  markCustomEndpointUnreachable,
} from '@services/ai';
import { generateText } from 'ai';
import { createHash } from 'crypto';
import { format } from 'date-fns';
import { z } from 'zod';

import type { AnalyzedCluster } from './types';

const MAX_CLUSTERS_PER_CALL = 40;
const MAX_DESCRIPTIONS = 3;
const MAX_DESCRIPTION_LENGTH = 60;
const MAX_OCCURRENCES = 24;
const REQUEST_TIMEOUT_MS = 45_000;

const AI_FREQUENCY_TO_SUBSCRIPTION: Record<string, SUBSCRIPTION_FREQUENCIES | null> = {
  weekly: SUBSCRIPTION_FREQUENCIES.weekly,
  biweekly: SUBSCRIPTION_FREQUENCIES.biweekly,
  monthly: SUBSCRIPTION_FREQUENCIES.monthly,
  quarterly: SUBSCRIPTION_FREQUENCIES.quarterly,
  semi_annual: SUBSCRIPTION_FREQUENCIES.semiAnnual,
  annual: SUBSCRIPTION_FREQUENCIES.annual,
  irregular: null,
};

const verdictSchema = z.object({
  id: z.string(),
  isRecurring: z.boolean(),
  name: z.string().trim().min(1).max(200).optional().nullable(),
  frequency: z
    .enum(Object.keys(AI_FREQUENCY_TO_SUBSCRIPTION) as [string, ...string[]])
    .optional()
    .nullable(),
  expectedAmount: z.number().nonnegative().optional().nullable(),
  amountVaries: z.boolean().optional().nullable(),
  confidence: z.number().min(0).max(1),
  reason: z.string().max(500).optional().nullable(),
});

export interface AiClusterVerdict {
  isRecurring: boolean;
  name: string | null;
  /** Null when the model answered `irregular` or omitted it. */
  frequency: SUBSCRIPTION_FREQUENCIES | null;
  /** Decimal, in the cluster's currency. */
  expectedAmount: number | null;
  confidence: number;
  reason: string | null;
}

export interface AiReviewResult {
  status: DetectionAiStatus;
  /** Verdicts keyed by cluster fingerprint. */
  verdicts: Map<string, AiClusterVerdict>;
  /** Fingerprints of every cluster sent, answered or not. */
  reviewedFingerprints: Set<string>;
}

const SYSTEM_PROMPT = `You review clusters of bank transactions that a heuristic flagged as possibly recurring payments (subscriptions, bills, rent, salary, other regular income).
For each cluster decide whether it is a genuinely recurring payment. One-off purchases at the same shop (groceries, restaurants, fuel, ride-hailing) are NOT recurring even if they happen often.
Respond with ONLY a JSON array, no prose and no code fences. One object per cluster you were given:
[{"id": "<cluster id>", "isRecurring": true|false, "name": "<clean merchant or payer name, e.g. Netflix>", "frequency": "weekly"|"biweekly"|"monthly"|"quarterly"|"semi_annual"|"annual"|"irregular", "expectedAmount": <number for the next charge>, "amountVaries": true|false, "confidence": <0..1>, "reason": "<one short sentence>"}]`;

/** sha256(merchantKey + sorted tx ids): an unchanged cluster is never sent twice. */
export function clusterFingerprint({ analyzed }: { analyzed: AnalyzedCluster }): string {
  const ids = analyzed.cluster.transactions.map((tx) => tx.id).sort();
  return createHash('sha256')
    .update(`${analyzed.cluster.merchantKey}|${ids.join(',')}`)
    .digest('hex');
}

/** Raw bank descriptors (an all-caps or digit-heavy token) benefit from an AI-cleaned name. */
const looksRaw = ({ name }: { name: string }): boolean =>
  name.split(/\s+/).some((token) => /^[^a-z]*[A-Z]{2,}[^a-z]*$/.test(token) || (token.match(/\d/g)?.length ?? 0) >= 3);

const maskDescription = ({ note }: { note: string }): string =>
  note.replace(/\d{4,}/g, '#').slice(0, MAX_DESCRIPTION_LENGTH);

/** Ambiguous clusters first, then accepted clusters with raw names; already-reviewed fingerprints are skipped. */
export function selectClustersForReview({
  clusters,
  alreadyReviewed,
}: {
  clusters: AnalyzedCluster[];
  alreadyReviewed: Set<string>;
}): AnalyzedCluster[] {
  const fresh = clusters.filter((analyzed) => !alreadyReviewed.has(clusterFingerprint({ analyzed })));
  const ambiguous = fresh.filter((analyzed) => analyzed.verdict === 'ambiguous');
  const rawAccepted = fresh.filter(
    (analyzed) => analyzed.verdict === 'accepted' && looksRaw({ name: analyzed.suggestedName }),
  );
  return [...ambiguous, ...rawAccepted].slice(0, MAX_CLUSTERS_PER_CALL);
}

function buildUserMessage({ clusters }: { clusters: AnalyzedCluster[] }): string {
  return JSON.stringify({
    clusters: clusters.map((analyzed, index) => {
      const { cluster } = analyzed;
      const notes = [...new Set(cluster.transactions.map((tx) => tx.note?.trim()).filter(Boolean) as string[])];
      return {
        id: `c${index + 1}`,
        merchantKey: cluster.payeeName ?? cluster.merchantKey,
        descriptions: notes.slice(0, MAX_DESCRIPTIONS).map((note) => maskDescription({ note })),
        occurrences: cluster.occurrences.slice(-MAX_OCCURRENCES).map((occurrence) => ({
          date: format(occurrence.time, 'yyyy-MM-dd'),
          amount: Money.fromCents(occurrence.amountCents).toNumber(),
          currency: cluster.currencyCode,
        })),
        type: cluster.transactionType,
      };
    }),
  });
}

function parseVerdicts({ text }: { text: string }): Map<string, z.infer<typeof verdictSchema>> {
  const result = new Map<string, z.infer<typeof verdictSchema>>();
  const start = text.indexOf('[');
  const end = text.lastIndexOf(']');
  if (start === -1 || end <= start) return result;

  let parsed: unknown;
  try {
    parsed = JSON.parse(text.slice(start, end + 1));
  } catch {
    return result;
  }
  if (!Array.isArray(parsed)) return result;

  for (const item of parsed) {
    const verdict = verdictSchema.safeParse(item);
    if (verdict.success) result.set(verdict.data.id, verdict.data);
  }
  return result;
}

/**
 * Optional AI pass over clustered candidates. Runs only when the user has AI available for
 * `recurringDetection` (own key, custom endpoint, or server key under the operator entitlement,
 * all decided by `createAIClient`). One call per detection run; any failure leaves the heuristic
 * results in place with `status: 'failed'`.
 */
export async function reviewClustersWithAi({
  userId,
  clusters,
}: {
  userId: number;
  clusters: AnalyzedCluster[];
}): Promise<AiReviewResult> {
  const empty = { verdicts: new Map<string, AiClusterVerdict>(), reviewedFingerprints: new Set<string>() };
  if (clusters.length === 0) return { status: 'skipped', ...empty };

  let aiClient: Awaited<ReturnType<typeof createAIClient>>;
  try {
    aiClient = await createAIClient({ userId, feature: AI_FEATURE.recurringDetection });
  } catch (error) {
    logger.error({ message: '[detect-candidates] AI client could not be created', error: error as Error });
    return { status: 'failed', ...empty };
  }
  if (!aiClient) return { status: 'skipped', ...empty };

  const fingerprints = clusters.map((analyzed) => clusterFingerprint({ analyzed }));

  try {
    const guards = aiCallGuards({ provider: aiClient.provider });
    const { text, usage } = await generateText({
      model: aiClient.model,
      system: SYSTEM_PROMPT,
      prompt: buildUserMessage({ clusters }),
      abortSignal: AbortSignal.any([guards.abortSignal, AbortSignal.timeout(REQUEST_TIMEOUT_MS)]),
      maxRetries: guards.maxRetries,
      maxOutputTokens: AI_MAX_OUTPUT_TOKENS,
    });

    logger.info('[detect-candidates] AI review completed', {
      modelId: aiClient.modelId,
      clusterCount: clusters.length,
      inputTokens: usage?.inputTokens ?? 0,
      outputTokens: usage?.outputTokens ?? 0,
    });

    const parsed = parseVerdicts({ text });
    const verdicts = new Map<string, AiClusterVerdict>();
    clusters.forEach((_, index) => {
      const verdict = parsed.get(`c${index + 1}`);
      if (!verdict) return;
      verdicts.set(fingerprints[index]!, {
        isRecurring: verdict.isRecurring,
        name: verdict.name ?? null,
        frequency: verdict.frequency ? (AI_FREQUENCY_TO_SUBSCRIPTION[verdict.frequency] ?? null) : null,
        expectedAmount: verdict.expectedAmount ?? null,
        confidence: verdict.confidence,
        reason: verdict.reason ?? null,
      });
    });

    return { status: 'applied', verdicts, reviewedFingerprints: new Set(fingerprints) };
  } catch (error) {
    const { kind, cause } = classifyAiCallFailure({ error });

    if (kind === 'endpoint-down' && aiClient.provider === AI_PROVIDER.custom) {
      await markCustomEndpointUnreachable({ userId, aiClient });
    }

    if (kind === 'unknown') {
      logger.error({ message: '[detect-candidates] AI review failed', error: cause });
    } else {
      logger.info(`[detect-candidates] AI review failed (${kind}): ${cause.message}`);
    }

    return { status: 'failed', ...empty };
  }
}
