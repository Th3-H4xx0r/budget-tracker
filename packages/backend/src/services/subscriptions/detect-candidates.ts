import {
  type DetectionAiStatus,
  SUBSCRIPTION_CANDIDATE_STATUS,
  SUBSCRIPTION_DETECTION_SOURCE,
  SUBSCRIPTION_LINK_STATUS,
  TRANSACTION_TYPES,
} from '@bt/shared/types';
import { Money } from '@common/types/money';
import { logger } from '@js/utils';
import PayeeAliases from '@models/payee-aliases.model';
import Payees from '@models/payees.model';
import SubscriptionCandidates from '@models/subscription-candidates.model';
import Subscriptions from '@models/subscriptions.model';
import { findTransactions } from '@models/transactions-query';
import { Op, QueryTypes } from 'sequelize';

import {
  type AiClusterVerdict,
  clusterFingerprint,
  reviewClustersWithAi,
  selectClustersForReview,
} from './discovery/ai-review';
import { analyzeCluster } from './discovery/analyze-cluster';
import { type PayeeIdentity, clusterMerchants } from './discovery/cluster-merchants';
import { routeClustersToExisting } from './discovery/route-to-existing';
import type { AnalyzedCluster, DiscoveryTransaction } from './discovery/types';
import { type SerializedCandidate, serializeCandidate } from './serialize-candidate';

const COOLDOWN_MS = 60 * 60 * 1000; // 1 hour
/** Two years plus a month, so an annual charge has two occurrences in the window. */
const LOOKBACK_MONTHS = 25;
const MAX_CANDIDATES_PER_RUN = 50;
const MAX_SAMPLE_TRANSACTIONS = 10;
/** A dismissed candidate comes back only once this many occurrences arrived after the dismissal. */
const RESURFACE_MIN_NEW_OCCURRENCES = 3;
const AI_ACCEPT_MIN_CONFIDENCE = 0.6;
const AI_REJECT_MIN_CONFIDENCE = 0.7;

interface DetectCandidatesResult {
  candidates: SerializedCandidate[];
  lastRunAt: string | null;
  isFromCache: boolean;
  /** Outcome of the optional AI review pass; `skipped` for cached results and when AI isn't configured. */
  aiStatus: DetectionAiStatus;
}

const candidateKey = ({
  merchantKey,
  transactionType,
  currencyCode,
}: {
  merchantKey: string | null;
  transactionType: TRANSACTION_TYPES;
  currencyCode: string;
}) => `${merchantKey ?? ''}|${transactionType}|${currencyCode}`;

const round3 = (value: number) => Math.round(value * 1000) / 1000;

async function loadPendingCandidates({ userId }: { userId: number }) {
  const [pending, userSubscriptions] = await Promise.all([
    SubscriptionCandidates.findAll({
      where: { userId, status: SUBSCRIPTION_CANDIDATE_STATUS.pending },
      order: [['confidenceScore', 'DESC']],
    }),
    Subscriptions.findAll({ where: { userId }, attributes: ['id', 'name'], raw: true }),
  ]);
  return pending.map((candidate) => serializeCandidate({ candidate, userSubscriptions }));
}

/**
 * Detect subscription candidates for a user. Returns cached results if
 * detection ran within the cooldown period, otherwise runs fresh detection.
 */
export async function detectCandidates({ userId }: { userId: number }): Promise<DetectCandidatesResult> {
  const mostRecent = await SubscriptionCandidates.findOne({
    where: { userId },
    order: [['detectedAt', 'DESC']],
    attributes: ['detectedAt'],
  });
  const lastRunAt = mostRecent?.detectedAt ?? null;

  if (lastRunAt && Date.now() - new Date(lastRunAt).getTime() < COOLDOWN_MS) {
    return {
      candidates: await loadPendingCandidates({ userId }),
      lastRunAt: new Date(lastRunAt).toISOString(),
      isFromCache: true,
      aiStatus: 'skipped',
    };
  }

  const { aiStatus } = await detect({ userId, withAiReview: true });

  return {
    candidates: await loadPendingCandidates({ userId }),
    lastRunAt: new Date().toISOString(),
    isFromCache: false,
    aiStatus,
  };
}

/**
 * Background detection (cron). Heuristics only: the AI pass runs when the user opens discovery,
 * so a scheduled sweep over every user never spends AI budget.
 */
export async function runDetection({ userId }: { userId: number }): Promise<SubscriptionCandidates[]> {
  const { saved } = await detect({ userId, withAiReview: false });
  return saved;
}

async function loadDiscoveryTransactions({ userId }: { userId: number }): Promise<DiscoveryTransaction[]> {
  const sinceDate = new Date();
  sinceDate.setMonth(sinceDate.getMonth() - LOOKBACK_MONTHS);

  const linked: { transactionId: string }[] = await SubscriptionCandidates.sequelize!.query(
    `SELECT st."transactionId"
       FROM "SubscriptionTransactions" st
       JOIN "Subscriptions" s ON s."id" = st."subscriptionId"
      WHERE st."status" = :status AND s."userId" = :userId`,
    { replacements: { status: SUBSCRIPTION_LINK_STATUS.active, userId }, type: QueryTypes.SELECT },
  );
  const linkedSet = new Set(linked.map((row) => row.transactionId));

  const rows = await findTransactions({
    where: {
      transactionType: { [Op.in]: [TRANSACTION_TYPES.expense, TRANSACTION_TYPES.income] },
      refundLinked: false,
      time: { [Op.gte]: sinceDate },
      [Op.or]: [{ payeeId: { [Op.ne]: null } }, { note: { [Op.and]: [{ [Op.ne]: null }, { [Op.ne]: '' }] } }],
    },
    planned: 'exclude',
    access: { creator: userId },
    transfers: 'exclude',
    balanceAdjustments: 'include',
    completeness: 'all',
    attributes: ['id', 'amount', 'note', 'payeeId', 'time', 'accountId', 'currencyCode', 'transactionType'],
    order: [['time', 'ASC']],
  });

  return rows
    .filter((tx) => !linkedSet.has(tx.id as string))
    .map((tx) => ({
      id: tx.id as string,
      amountCents: Math.abs(tx.amount.toCents()),
      note: tx.note,
      payeeId: (tx.payeeId as string | null) ?? null,
      time: new Date(tx.time),
      accountId: tx.accountId as string,
      currencyCode: tx.currencyCode,
      transactionType: tx.transactionType,
    }));
}

async function loadPayees({
  userId,
  payeeIds,
}: {
  userId: number;
  payeeIds: string[];
}): Promise<Map<string, PayeeIdentity>> {
  const result = new Map<string, PayeeIdentity>();
  if (payeeIds.length === 0) return result;

  const [payees, aliases] = await Promise.all([
    Payees.findAll({ where: { userId, id: { [Op.in]: payeeIds } }, attributes: ['id', 'name'] }),
    PayeeAliases.findAll({ where: { payeeId: { [Op.in]: payeeIds } }, attributes: ['payeeId', 'rawName'] }),
  ]);
  for (const payee of payees) result.set(payee.id, { name: payee.name, aliases: [] });
  for (const alias of aliases) result.get(alias.payeeId)?.aliases.push(alias.rawName);
  return result;
}

interface Decision {
  analyzed: AnalyzedCluster;
  existing: SubscriptionCandidates | null;
  status: SUBSCRIPTION_CANDIDATE_STATUS;
  suggestedName: string;
  frequency: AnalyzedCluster['cadence']['frequency'];
  expectedCents: number;
  confidence: number;
  detectionSource: SUBSCRIPTION_DETECTION_SOURCE;
  aiReason: string | null;
  aiFingerprint: string | null;
}

/**
 * Merges the heuristic result with the AI verdict (when there is one). Returns null for clusters
 * that are dropped: AI-rejected, or ambiguous without an AI confirmation.
 */
function decide({
  analyzed,
  existing,
  verdict,
}: {
  analyzed: AnalyzedCluster;
  existing: SubscriptionCandidates | null;
  verdict: AiClusterVerdict | undefined;
}): Decision | null {
  const fingerprint = clusterFingerprint({ analyzed });
  const base: Decision = {
    analyzed,
    existing,
    status: SUBSCRIPTION_CANDIDATE_STATUS.pending,
    suggestedName: analyzed.suggestedName,
    frequency: analyzed.cadence.frequency,
    expectedCents: analyzed.amount.expectedCents,
    confidence: analyzed.confidence,
    detectionSource: SUBSCRIPTION_DETECTION_SOURCE.heuristic,
    aiReason: null,
    aiFingerprint: null,
  };

  if (verdict?.isRecurring && verdict.confidence >= AI_ACCEPT_MIN_CONFIDENCE) {
    const isAmbiguous = analyzed.verdict === 'ambiguous';
    return {
      ...base,
      suggestedName: verdict.name?.slice(0, 200) ?? base.suggestedName,
      frequency: isAmbiguous && verdict.frequency ? verdict.frequency : base.frequency,
      expectedCents:
        isAmbiguous && verdict.expectedAmount
          ? Money.fromDecimal(verdict.expectedAmount).toCents()
          : base.expectedCents,
      confidence: round3(0.5 * analyzed.confidence + 0.5 * verdict.confidence),
      detectionSource: SUBSCRIPTION_DETECTION_SOURCE.ai,
      aiReason: verdict.reason,
      aiFingerprint: fingerprint,
    };
  }

  if (verdict && !verdict.isRecurring && verdict.confidence >= AI_REJECT_MIN_CONFIDENCE) {
    // Stored as dismissed so the rejection is remembered (by fingerprint and the resurface rule).
    return {
      ...base,
      status: SUBSCRIPTION_CANDIDATE_STATUS.dismissed,
      detectionSource: SUBSCRIPTION_DETECTION_SOURCE.ai,
      aiReason: verdict.reason,
      aiFingerprint: fingerprint,
    };
  }

  // An unchanged cluster the AI already confirmed keeps the AI's naming without a new call.
  if (existing?.aiFingerprint === fingerprint && existing.detectionSource === SUBSCRIPTION_DETECTION_SOURCE.ai) {
    return {
      ...base,
      suggestedName: existing.suggestedName,
      frequency: existing.detectedFrequency,
      confidence: existing.confidenceScore,
      detectionSource: SUBSCRIPTION_DETECTION_SOURCE.ai,
      aiReason: existing.aiReason,
      aiFingerprint: fingerprint,
    };
  }

  if (analyzed.verdict === 'ambiguous') return null;
  return { ...base, aiFingerprint: verdict ? fingerprint : null };
}

/** Whether a cluster may produce or refresh a candidate given what is already stored for its key. */
function isEligible({ analyzed, existing }: { analyzed: AnalyzedCluster; existing: SubscriptionCandidates | null }) {
  if (!existing) return true;
  if (existing.status === SUBSCRIPTION_CANDIDATE_STATUS.accepted) return false;
  if (existing.status === SUBSCRIPTION_CANDIDATE_STATUS.dismissed) {
    const resolvedAt = existing.resolvedAt ? new Date(existing.resolvedAt).getTime() : 0;
    const newOccurrences = analyzed.cluster.occurrences.filter((o) => o.time.getTime() > resolvedAt).length;
    return newOccurrences >= RESURFACE_MIN_NEW_OCCURRENCES;
  }
  return true;
}

/**
 * Core detection: clusters the user's expense and income history by merchant, fits cadence and
 * amount profiles, routes clusters of existing recurring payments to link suggestions, optionally
 * asks AI to review the rest, and upserts candidates keyed on (merchantKey, transactionType, currency).
 */
async function detect({
  userId,
  withAiReview,
}: {
  userId: number;
  withAiReview: boolean;
}): Promise<{ saved: SubscriptionCandidates[]; aiStatus: DetectionAiStatus }> {
  const transactions = await loadDiscoveryTransactions({ userId });
  if (transactions.length === 0) {
    logger.info(`[detect-candidates] No qualifying transactions for user ${userId}`);
    return { saved: [], aiStatus: 'skipped' };
  }

  const payeeIds = [...new Set(transactions.map((tx) => tx.payeeId).filter((id): id is string => !!id))];
  const payees = await loadPayees({ userId, payeeIds });

  const now = new Date();
  const analyzed = clusterMerchants({ transactions, payees }).flatMap((cluster) => analyzeCluster({ cluster, now }));
  const { unrouted, suggestionsCreated } = await routeClustersToExisting({ userId, clusters: analyzed });
  if (suggestionsCreated > 0) {
    logger.info(
      `[detect-candidates] Routed ${suggestionsCreated} transactions to existing payments for user ${userId}`,
    );
  }

  const existingCandidates = await SubscriptionCandidates.findAll({ where: { userId } });
  const existingByKey = new Map(existingCandidates.map((candidate) => [candidateKey(candidate), candidate]));
  const findExisting = ({ analyzed: item }: { analyzed: AnalyzedCluster }) =>
    existingByKey.get(
      candidateKey({
        merchantKey: item.cluster.merchantKey,
        transactionType: item.cluster.transactionType,
        currencyCode: item.cluster.currencyCode,
      }),
    ) ?? null;

  const eligible = unrouted.filter((item) =>
    isEligible({ analyzed: item, existing: findExisting({ analyzed: item }) }),
  );

  let aiStatus: DetectionAiStatus = 'skipped';
  let verdicts = new Map<string, AiClusterVerdict>();
  if (withAiReview) {
    const alreadyReviewed = new Set(
      existingCandidates.map((candidate) => candidate.aiFingerprint).filter((fp): fp is string => !!fp),
    );
    const toReview = selectClustersForReview({ clusters: eligible, alreadyReviewed });
    const review = await reviewClustersWithAi({ userId, clusters: toReview });
    aiStatus = review.status;
    verdicts = review.verdicts;
  }

  const decisions = eligible
    .map((item) =>
      decide({
        analyzed: item,
        existing: findExisting({ analyzed: item }),
        verdict: verdicts.get(clusterFingerprint({ analyzed: item })),
      }),
    )
    .filter((decision): decision is Decision => decision !== null)
    .sort((a, b) => b.confidence - a.confidence)
    .slice(0, MAX_CANDIDATES_PER_RUN);

  const saved: SubscriptionCandidates[] = [];
  for (const decision of decisions) {
    const { analyzed: item, existing } = decision;
    const { cluster, cadence, amount } = item;
    const isDismissal = decision.status === SUBSCRIPTION_CANDIDATE_STATUS.dismissed;
    // An AI rejection of an existing pending candidate dismisses it; one of an unseen cluster only
    // needs a row when it carries the memory (a dismissed existing row already does).
    if (isDismissal && existing?.status === SUBSCRIPTION_CANDIDATE_STATUS.dismissed) continue;

    const values = {
      userId,
      suggestedName: decision.suggestedName,
      detectedFrequency: decision.frequency,
      averageAmount: decision.expectedCents,
      currencyCode: cluster.currencyCode,
      accountId: cluster.accountId,
      sampleTransactionIds: cluster.transactions
        .toReversed()
        .slice(0, MAX_SAMPLE_TRANSACTIONS)
        .map((tx) => tx.id),
      occurrenceCount: cluster.occurrences.length,
      confidenceScore: decision.confidence,
      medianIntervalDays: Math.round(cadence.periodDays * 10) / 10,
      status: decision.status,
      detectedAt: now,
      lastOccurrenceAt: item.lastOccurrenceAt,
      resolvedAt: isDismissal ? now : null,
      merchantKey: cluster.merchantKey,
      transactionType: cluster.transactionType,
      amountVariability: round3(amount.variability),
      detectionSource: decision.detectionSource,
      aiReason: decision.aiReason,
      aiFingerprint: decision.aiFingerprint ?? existing?.aiFingerprint ?? null,
      nextExpectedDate: item.nextExpectedDate,
    };

    saved.push(existing ? await existing.update(values) : await SubscriptionCandidates.create(values));
  }

  logger.info(`[detect-candidates] Saved ${saved.length} candidates for user ${userId} (AI: ${aiStatus})`);
  return { saved, aiStatus };
}
