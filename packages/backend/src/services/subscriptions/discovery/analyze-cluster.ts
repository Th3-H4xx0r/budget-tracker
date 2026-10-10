import { addDays, addMonths, format } from 'date-fns';

import { findMostCommonNote, splitByAmountBuckets } from '../detect-candidates-utils';
import { buildAmountProfile } from './amount-profile';
import { PERIOD_MONTHS, detectCadence } from './detect-cadence';
import type { AnalyzedCluster, ClusterOccurrence, MerchantCluster } from './types';

const DAY_MS = 24 * 60 * 60 * 1000;
// Matches the SubscriptionCandidates.suggestedName column width.
const MAX_SUGGESTED_NAME_LENGTH = 200;

export const ACCEPT_MIN_CONFIDENCE = 0.55;
export const AMBIGUOUS_MIN_CONFIDENCE = 0.35;
const REGULAR_MIN_FIT = 0.7;
const VARIABLE_AMOUNT_MIN_FIT = 0.8;
/** A two-occurrence pattern has no second interval to confirm it, so its one interval must be tight. */
const TWO_OCCURRENCE_MAX_ERROR_SHARE = 0.04;
const LEVEL_MIN_OCCURRENCES = 3;
const LEVEL_MIN_FIT = 0.8;

const round3 = (value: number) => Math.round(value * 1000) / 1000;

function recencyScore({
  lastOccurrenceAt,
  periodDays,
  now,
}: {
  lastOccurrenceAt: Date;
  periodDays: number;
  now: Date;
}) {
  const daysSince = (now.getTime() - lastOccurrenceAt.getTime()) / DAY_MS;
  if (daysSince <= 1.5 * periodDays) return 1;
  if (daysSince >= 3 * periodDays) return 0;
  return (3 * periodDays - daysSince) / (1.5 * periodDays);
}

function analyzeOccurrences({
  cluster,
  occurrences,
  now,
}: {
  cluster: MerchantCluster;
  occurrences: ClusterOccurrence[];
  now: Date;
}): AnalyzedCluster | null {
  if (occurrences.length < 2) return null;

  const cadence = detectCadence({ dates: occurrences.map((occurrence) => occurrence.time) });
  if (!cadence) return null;

  const amount = buildAmountProfile({ amounts: occurrences.map((occurrence) => occurrence.amountCents) });
  const count = occurrences.length;

  if (
    count === 2 &&
    (cadence.fit < 1 ||
      cadence.maxFittedErrorDays > TWO_OCCURRENCE_MAX_ERROR_SHARE * cadence.periodDays ||
      amount.variabilityClass === 'variable')
  ) {
    return null;
  }

  const lastOccurrenceAt = occurrences[count - 1]!.time;
  const recency = recencyScore({ lastOccurrenceAt, periodDays: cadence.periodDays, now });
  const confidence =
    0.35 * cadence.fit +
    0.2 * cadence.coverage +
    0.15 * Math.min(1, count / 6) +
    0.15 * (1 - Math.min(1, amount.variability / 0.5)) +
    0.15 * recency;

  const qualified =
    cadence.fit >= REGULAR_MIN_FIT &&
    (amount.variabilityClass !== 'variable' || cadence.fit >= VARIABLE_AMOUNT_MIN_FIT);

  let verdict: AnalyzedCluster['verdict'];
  if (qualified && confidence >= ACCEPT_MIN_CONFIDENCE) verdict = 'accepted';
  else if (confidence >= AMBIGUOUS_MIN_CONFIDENCE) verdict = 'ambiguous';
  else return null;

  const months = PERIOD_MONTHS[cadence.frequency];
  const nextExpected = months ? addMonths(lastOccurrenceAt, months) : addDays(lastOccurrenceAt, cadence.periodDays);
  const notes = cluster.transactions.map((tx) => tx.note ?? '').filter(Boolean);

  return {
    cluster,
    cadence,
    amount,
    confidence: round3(confidence),
    verdict,
    suggestedName: (cluster.payeeName ?? findMostCommonNote({ notes })).slice(0, MAX_SUGGESTED_NAME_LENGTH),
    lastOccurrenceAt,
    nextExpectedDate: format(nextExpected, 'yyyy-MM-dd'),
  };
}

/**
 * Two or more stable price levels billed side by side on the same cadence (two plans of one
 * merchant) are separate recurring payments. A level change over time (a price increase) is not:
 * the levels' time spans don't overlap, so the cluster stays whole.
 */
function splitInterleavedLevels({ occurrences }: { occurrences: ClusterOccurrence[] }): ClusterOccurrence[][] | null {
  const buckets = splitByAmountBuckets({
    transactions: occurrences.map((occurrence, index) => ({
      id: String(index),
      amount: occurrence.amountCents,
      note: '',
      time: occurrence.time,
      accountId: '',
      currencyCode: '',
    })),
  })
    .filter((bucket) => bucket.length >= LEVEL_MIN_OCCURRENCES)
    .map((bucket) =>
      bucket.map((item) => occurrences[Number(item.id)]!).sort((a, b) => a.time.getTime() - b.time.getTime()),
    );

  if (buckets.length < 2) return null;

  const fits = buckets.map((bucket) => detectCadence({ dates: bucket.map((occurrence) => occurrence.time) }));
  const frequency = fits[0]?.frequency;
  if (fits.some((fit) => !fit || fit.fit < LEVEL_MIN_FIT || fit.frequency !== frequency)) return null;

  const spans = buckets.map(
    (bucket) => [bucket[0]!.time.getTime(), bucket[bucket.length - 1]!.time.getTime()] as const,
  );
  const overlapping = spans.every(([start, end], i) =>
    spans.some(([otherStart, otherEnd], j) => i !== j && start <= otherEnd && otherStart <= end),
  );

  return overlapping ? buckets : null;
}

/**
 * Cadence, amount and confidence of a merchant cluster. Returns one analysis per recurring payment
 * found (two for interleaved price levels), each `accepted` or `ambiguous`; weak clusters return [].
 */
export function analyzeCluster({ cluster, now }: { cluster: MerchantCluster; now: Date }): AnalyzedCluster[] {
  const whole = analyzeOccurrences({ cluster, occurrences: cluster.occurrences, now });

  if (!whole || whole.amount.variabilityClass === 'variable') {
    const levels = splitInterleavedLevels({ occurrences: cluster.occurrences });
    if (levels) {
      return levels.flatMap((occurrences) => {
        const transactionIds = new Set(occurrences.flatMap((occurrence) => occurrence.transactionIds));
        const levelCluster: MerchantCluster = {
          ...cluster,
          transactions: cluster.transactions.filter((tx) => transactionIds.has(tx.id)),
          occurrences,
        };
        const analyzed = analyzeOccurrences({ cluster: levelCluster, occurrences, now });
        if (!analyzed) return [];
        // Each level is its own payment, so it needs its own dedupe key.
        levelCluster.merchantKey = `${cluster.merchantKey}#${analyzed.amount.expectedCents}`.slice(0, 200);
        return [analyzed];
      });
    }
  }

  return whole ? [whole] : [];
}
