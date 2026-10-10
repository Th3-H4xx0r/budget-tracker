import type { TransactionModel } from './db-models';
import {
  SUBSCRIPTION_DETECTION_SOURCE,
  SUBSCRIPTION_SUGGESTION_SOURCE,
  SUBSCRIPTION_SUGGESTION_STATUS,
  TRANSACTION_TYPES,
} from './enums';
import type { RecordId } from './record-id';

/**
 * Why the scoring matcher scored a transaction against a recurring payment the way it did.
 * Clients localise the codes; unknown codes must be tolerated (forward compatibility).
 */
export enum MATCH_REASON_CODE {
  payeeMatch = 'payee_match',
  merchantSimilar = 'merchant_similar',
  learnedMerchant = 'learned_merchant',
  keywordMatch = 'keyword_match',
  ruleMatch = 'rule_match',
  nearDueDate = 'near_due_date',
  farFromDueDate = 'far_from_due_date',
  amountClose = 'amount_close',
  amountDiffers = 'amount_differs',
  sameAccount = 'same_account',
  differentAccount = 'different_account',
  sameCategory = 'same_category',
  periodAlreadyCovered = 'period_already_covered',
  ambiguousWithOtherSubscription = 'ambiguous_with_other_subscription',
}

export type MatchReasonCode = `${MATCH_REASON_CODE}`;

/** Extra context for the reason codes that carry it. */
export interface MatchReasonDetail {
  /** `near_due_date` / `far_from_due_date`: the expected date the tx was compared against (YYYY-MM-DD). */
  dueDate?: string;
  /** `near_due_date` / `far_from_due_date`: absolute days between the tx and `dueDate`. */
  days?: number;
  /** `amount_close` / `amount_differs`: signed deviation from the expected amount, in percent. */
  deviationPct?: number;
  /** `ambiguous_with_other_subscription`: the competing subscription. */
  otherSubscriptionId?: RecordId;
}

export interface MatchReason {
  code: MatchReasonCode;
  /** Signal weight in the total score (0 for caps, which limit the tier rather than add score). */
  weight: number;
  /** Signal value in [0, 1]. */
  value: number;
  detail?: MatchReasonDetail;
}

/** `high` when score >= 0.8 (auto-link tier), otherwise `medium`. */
export type MatchConfidence = 'high' | 'medium';

/** Score at or above which a scored pair is surfaced as a suggestion. */
export const SUBSCRIPTION_SUGGESTION_MIN_SCORE = 0.5;
/** Score at or above which a scored pair (with identity evidence and no caps) is auto-linked. */
export const SUBSCRIPTION_AUTO_LINK_MIN_SCORE = 0.8;

/** Persisted row of `SubscriptionMatchSuggestions`. */
export interface SubscriptionMatchSuggestionModel {
  subscriptionId: RecordId;
  transactionId: RecordId;
  userId: number;
  score: number;
  reasons: MatchReason[];
  status: SUBSCRIPTION_SUGGESTION_STATUS;
  source: SUBSCRIPTION_SUGGESTION_SOURCE;
  createdAt: Date;
  updatedAt: Date;
}

/** One item of `GET /subscriptions/:id/suggestions`. */
export interface SubscriptionSuggestion<TTransaction = TransactionModel> {
  transaction: TTransaction;
  /** 0..1, rounded to 3 decimal places. */
  score: number;
  confidence: MatchConfidence;
  reasons: MatchReason[];
  /** YYYY-MM-DD */
  nearestDueDate: string | null;
  daysFromDue: number | null;
  amountDeviationPct: number | null;
}

/** Response `data` of `GET /subscriptions/:id/suggestions`. */
export interface SubscriptionSuggestionsResponse<TTransaction = TransactionModel> {
  suggestions: SubscriptionSuggestion<TTransaction>[];
  dismissedCount: number;
}

export type LinkableTransactionsSort = 'date' | 'relevance';

/** Query of `GET /subscriptions/:id/linkable-transactions`. */
export interface LinkableTransactionsQuery {
  search?: string;
  /** YYYY-MM-DD */
  from?: string;
  /** YYYY-MM-DD */
  to?: string;
  accountIds?: RecordId[];
  sort?: LinkableTransactionsSort;
  /** 1..100, default 30. */
  limit?: number;
  offset?: number;
}

/** One item of `GET /subscriptions/:id/linkable-transactions`. */
export interface LinkableTransactionItem<TTransaction = TransactionModel> {
  transaction: TTransaction;
  score: number;
  reasons: MatchReason[];
  /** Set when the tx is actively linked to another subscription; the pickers disable such rows. */
  linkedSubscription: { id: RecordId; name: string } | null;
  isDismissed: boolean;
}

/** Response `data` of `GET /subscriptions/:id/linkable-transactions`. */
export interface LinkableTransactionsResponse<TTransaction = TransactionModel> {
  items: LinkableTransactionItem<TTransaction>[];
  hasMore: boolean;
}

/** Body of `POST /subscriptions/:id/suggestions/dismiss` (1..100 ids). */
export interface DismissSubscriptionSuggestionsBody {
  transactionIds: RecordId[];
}

/** Response `data` of `POST /subscriptions/:id/suggestions/dismiss`. */
export interface DismissSubscriptionSuggestionsResponse {
  dismissed: number;
}

/** Added to `GET /subscriptions` list items and `GET /subscriptions/:id`. */
export interface SubscriptionSuggestionCounts {
  pendingSuggestionsCount: number;
}

/** Fields the scoring matcher adds to a `SubscriptionTransactions` link. Null for manual links. */
export interface SubscriptionLinkMatchFields {
  matchScore: number | null;
  matchReasons: MatchReason[] | null;
}

/** Outcome of the optional AI review pass of `GET /subscriptions/detect-candidates`. */
export type DetectionAiStatus = 'applied' | 'skipped' | 'failed';

/** Amount variability class of a detected cluster: MAD/median ≤ 3% fixed, ≤ 15% stable, else variable. */
export type AmountVariabilityClass = 'fixed' | 'stable' | 'variable';

/** Fields smarter discovery adds to a subscription candidate (stored and serialized). */
export interface SubscriptionCandidateDetectionFields {
  /** Dedupe key: `payee:<payeeId>` or the `buildMerchantKey` key. */
  merchantKey: string | null;
  transactionType: TRANSACTION_TYPES;
  /** MAD / median of the cluster amounts. */
  amountVariability: number | null;
  detectionSource: SUBSCRIPTION_DETECTION_SOURCE;
  aiReason: string | null;
  /** YYYY-MM-DD */
  nextExpectedDate: string | null;
}
