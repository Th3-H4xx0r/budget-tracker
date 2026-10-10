import { SUBSCRIPTION_FREQUENCIES } from '@bt/shared/types';

/**
 * Normalize a transaction note for grouping:
 * - Lowercase, trim
 * - Strip reference numbers (6+ digit sequences)
 * - Strip date-like patterns (dd/mm/yyyy, yyyy-mm-dd, etc.)
 * - Strip special chars except spaces
 * - Collapse whitespace
 */
export function normalizeNote({ note }: { note: string }): string {
  let normalized = note.toLowerCase().trim();

  // Strip reference numbers (6+ consecutive digits)
  normalized = normalized.replace(/\b\d{6,}\b/g, '');

  // Strip date patterns: dd/mm/yyyy, dd.mm.yyyy, yyyy-mm-dd, dd-mm-yyyy
  normalized = normalized.replace(/\b\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4}\b/g, '');

  // Strip remaining special characters (keep letters, digits, spaces)
  normalized = normalized.replace(/[^a-z0-9\s]/g, '');

  // Collapse whitespace
  normalized = normalized.replace(/\s+/g, ' ').trim();

  return normalized;
}

export interface TransactionForGrouping {
  id: string;
  amount: number;
  note: string;
  time: Date;
  accountId: string;
  currencyCode: string;
}

/**
 * Split a group into amount buckets with a given tolerance (fractional, e.g. 0.10 = 10%).
 * Returns sub-groups where each bucket's amounts are within tolerance of the bucket's mean.
 */
export function splitByAmountBuckets({
  transactions,
  tolerance = 0.1,
}: {
  transactions: TransactionForGrouping[];
  tolerance?: number;
}): TransactionForGrouping[][] {
  const sorted = transactions.toSorted((a, b) => Math.abs(a.amount) - Math.abs(b.amount));
  const buckets: TransactionForGrouping[][] = [];

  for (const tx of sorted) {
    const absAmount = Math.abs(tx.amount);
    let placed = false;

    for (const bucket of buckets) {
      const bucketMean = bucket.reduce((sum, t) => sum + Math.abs(t.amount), 0) / bucket.length;
      if (bucketMean > 0 && Math.abs(absAmount - bucketMean) / bucketMean <= tolerance) {
        bucket.push(tx);
        placed = true;
        break;
      }
    }

    if (!placed) {
      buckets.push([tx]);
    }
  }

  return buckets;
}

/**
 * Compute the median of a sorted or unsorted array of numbers.
 */
export function computeMedian({ values }: { values: number[] }): number {
  if (values.length === 0) return 0;

  const sorted = values.toSorted((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);

  if (sorted.length % 2 === 0) {
    return (sorted[mid - 1]! + sorted[mid]!) / 2;
  }
  return sorted[mid]!;
}

/**
 * Map a median interval (days) to the closest subscription frequency.
 */
export function mapIntervalToFrequency({ medianDays }: { medianDays: number }): SUBSCRIPTION_FREQUENCIES {
  if (medianDays <= 10) return SUBSCRIPTION_FREQUENCIES.weekly;
  if (medianDays <= 21) return SUBSCRIPTION_FREQUENCIES.biweekly;
  if (medianDays <= 50) return SUBSCRIPTION_FREQUENCIES.monthly;
  if (medianDays <= 120) return SUBSCRIPTION_FREQUENCIES.quarterly;
  if (medianDays <= 270) return SUBSCRIPTION_FREQUENCIES.semiAnnual;
  return SUBSCRIPTION_FREQUENCIES.annual;
}

/**
 * Check if two names are a fuzzy match by comparing their space-stripped
 * normalized forms. Also handles containment (e.g. "Netflix" matches
 * "Netflix subscription").
 */
export function isFuzzyNameMatch({ a, b }: { a: string; b: string }): boolean {
  const normA = normalizeNote({ note: a }).replace(/\s+/g, '');
  const normB = normalizeNote({ note: b }).replace(/\s+/g, '');

  if (!normA || !normB) return false;

  return normA === normB || normA.includes(normB) || normB.includes(normA);
}

/**
 * Find the most common raw note in a group (the suggested name).
 */
export function findMostCommonNote({ notes }: { notes: string[] }): string {
  const counts = new Map<string, number>();
  for (const note of notes) {
    counts.set(note, (counts.get(note) || 0) + 1);
  }

  let bestNote = notes[0] || '';
  let bestCount = 0;
  for (const [note, count] of counts) {
    if (count > bestCount) {
      bestCount = count;
      bestNote = note;
    }
  }
  return bestNote;
}
