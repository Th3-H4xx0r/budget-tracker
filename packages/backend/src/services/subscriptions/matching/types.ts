import type {
  MatchReason,
  RecordId,
  SUBSCRIPTION_FREQUENCIES,
  SubscriptionPeriodStatus,
  SubscriptionMatchingRule,
  TRANSACTION_TRANSFER_NATURE,
  TRANSACTION_TYPES,
} from '@bt/shared/types';
import type { Money } from '@common/types/money';
import type Subscriptions from '@models/subscriptions.model';

export interface ProfilePeriod {
  id: RecordId;
  dueDate: string;
  status: SubscriptionPeriodStatus;
  transactionId: RecordId | null;
}

export interface ProfileAmount {
  expected: Money;
  currencyCode: string;
  /** Derived from linked transactions rather than `expectedAmount`. */
  learned: boolean;
  /** Learned amounts whose MAD/median exceeds 15%: deviations are judged leniently. */
  variable: boolean;
}

/** Everything the scorer needs about one recurring payment, loaded once per run. */
export interface SubscriptionProfile {
  subscription: Subscriptions;
  id: RecordId;
  transactionType: TRANSACTION_TYPES;
  frequency: SUBSCRIPTION_FREQUENCIES;
  /** `subscription.accountId`; a tx on another account is capped at the suggested tier. */
  scopedAccountId: RecordId | null;
  categoryId: RecordId | null;
  payeeIds: Set<string>;
  nameTokens: string[];
  /** Token sets of the names and aliases of the subscription payee and linked-tx payees. */
  aliasTokens: string[][];
  /** Token sets of merchant keys covering at least 30% of the active linked transactions. */
  learnedTokens: string[][];
  /** Explicit `note contains_any` rule values, lowercased. */
  keywords: string[];
  amount: ProfileAmount | null;
  accounts: Set<string>;
  /** `dueDate ?? startDate`, YYYY-MM-DD; null when neither is set. */
  anchor: string | null;
  anchorDay: number | null;
  periods: ProfilePeriod[];
  /** Dates (YYYY-MM-DD) of actively linked real transactions, for the period-already-covered cap. */
  linkedDates: string[];
  rules: SubscriptionMatchingRule[];
}

/** The transaction fields the scorer reads. */
export interface ScorableTransaction {
  id: RecordId;
  transactionType: TRANSACTION_TYPES;
  transferNature: TRANSACTION_TRANSFER_NATURE;
  amount: Money;
  currencyCode: string;
  time: Date;
  note: string | null;
  payeeId: RecordId | null;
  /** Name of `payeeId`, when loaded. */
  payeeName?: string | null;
  accountId: RecordId;
  categoryId: RecordId | null;
  isPlanned: boolean;
}

export type FxConvert = (params: { amount: Money; date: Date; from: string; to: string }) => Promise<Money | null>;

export interface MatchSignals {
  merchant: number;
  keyword: number;
  date: number;
  amount: number;
  account: number;
  category: number;
}

export interface MatchScore {
  subscriptionId: RecordId;
  transactionId: RecordId;
  /** Σ w·s in [0, 1], rounded to 3 dp. */
  score: number;
  signals: MatchSignals;
  reasons: MatchReason[];
  /** All explicit matching rules passed (legacy rule path). */
  ruleMatch: boolean;
  /** Legacy tie-break between rule-path subscriptions: 1 − amount deviation, clamped to [0, 1]. */
  amountCloseness: number;
  /** Caps found while scoring (different account, covered period, planned without rule). */
  capped: boolean;
  nearestDueDate: string | null;
  daysFromDue: number | null;
  amountDeviationPct: number | null;
}

export type MatchTier = 'auto' | 'suggested' | 'none';
