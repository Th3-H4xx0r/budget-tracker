import type { AmountVariabilityClass, SUBSCRIPTION_FREQUENCIES, TRANSACTION_TYPES } from '@bt/shared/types';

/** A transaction as discovery sees it: amounts are absolute cents. */
export interface DiscoveryTransaction {
  id: string;
  amountCents: number;
  note: string | null;
  payeeId: string | null;
  time: Date;
  accountId: string;
  currencyCode: string;
  transactionType: TRANSACTION_TYPES;
}

/** One occurrence of a cluster after same-charge duplicates are collapsed. */
export interface ClusterOccurrence {
  time: Date;
  amountCents: number;
  transactionIds: string[];
}

export interface MerchantCluster {
  /** Dedupe key: `payee:<payeeId>` or the `buildMerchantKey` key. */
  merchantKey: string;
  tokens: string[];
  payeeId: string | null;
  /** Display name of the payee when the cluster is payee-keyed. */
  payeeName: string | null;
  transactionType: TRANSACTION_TYPES;
  currencyCode: string;
  /** Most frequent account of the cluster. */
  accountId: string;
  accountIds: string[];
  transactions: DiscoveryTransaction[];
  occurrences: ClusterOccurrence[];
}

export interface CadenceFit {
  frequency: SUBSCRIPTION_FREQUENCIES;
  periodDays: number;
  /** Fraction of the occurrences after the first that land within tolerance of a slot. */
  fit: number;
  /** Hit slots / slots between the first and last occurrence. */
  coverage: number;
  /** Circular day-of-month spread in days (monthly and longer only). */
  dayOfMonthSpread: number | null;
  score: number;
  /** Largest slot error of a fitted occurrence, in days. */
  maxFittedErrorDays: number;
}

export interface AmountProfile {
  medianCents: number;
  madCents: number;
  /** MAD / median. */
  variability: number;
  variabilityClass: AmountVariabilityClass;
  /** Median, or the latest level after a clear step change. */
  expectedCents: number;
}

export type ClusterVerdict = 'accepted' | 'ambiguous';

/** A cluster that passed (or nearly passed) the heuristics. */
export interface AnalyzedCluster {
  cluster: MerchantCluster;
  cadence: CadenceFit;
  amount: AmountProfile;
  confidence: number;
  verdict: ClusterVerdict;
  suggestedName: string;
  lastOccurrenceAt: Date;
  nextExpectedDate: string;
}
