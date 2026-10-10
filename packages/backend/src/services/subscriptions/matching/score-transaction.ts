import {
  MATCH_REASON_CODE,
  type MatchReason,
  SUBSCRIPTION_AUTO_LINK_MIN_SCORE,
  SUBSCRIPTION_FREQUENCIES,
  SUBSCRIPTION_SUGGESTION_MIN_SCORE,
  isTwoLegTransfer,
} from '@bt/shared/types';

import { MATCH_WINDOW_DAYS, daysBetween, expectedDatesAround, nearestExpectedDate } from './expected-dates';
import { evaluateRule, isGatingRule } from './legacy-rules';
import { buildMerchantKey, tokenSimilarity } from './merchant-key';
import type { FxConvert, MatchScore, MatchTier, ScorableTransaction, SubscriptionProfile } from './types';

const SIGNAL_WEIGHTS = {
  merchant: 0.4,
  keyword: 0.1,
  date: 0.25,
  amount: 0.15,
  account: 0.05,
  category: 0.05,
} as const;

const RULE_MATCH_FLOOR = 0.95;
const AMOUNT_EXACT_RATIO = 0.02;
const AMOUNT_ZERO_RATIO = 0.5;
const AMOUNT_CLOSE_RATIO = 0.1;

const round3 = (value: number): number => Math.round(value * 1000) / 1000;

const mapMerchantSimilarity = ({ similarity }: { similarity: number }): number => {
  if (similarity >= 0.8) return 1;
  if (similarity >= 0.5) return 0.5 + ((similarity - 0.5) / 0.3) * 0.5;
  return 0;
};

const scoreMerchant = ({
  profile,
  transaction,
}: {
  profile: SubscriptionProfile;
  transaction: ScorableTransaction;
}): { value: number; reason: MatchReason | null } => {
  const weight = SIGNAL_WEIGHTS.merchant;
  if (transaction.payeeId && profile.payeeIds.has(transaction.payeeId)) {
    return { value: 1, reason: { code: MATCH_REASON_CODE.payeeMatch, weight, value: 1 } };
  }

  const txTokens = [
    ...new Set([
      ...buildMerchantKey({ raw: transaction.note }).tokens,
      ...buildMerchantKey({ raw: transaction.payeeName }).tokens,
    ]),
  ];
  if (txTokens.length === 0) return { value: 0, reason: null };

  let best = 0;
  let code = MATCH_REASON_CODE.merchantSimilar;
  for (const tokens of [profile.nameTokens, ...profile.aliasTokens]) {
    best = Math.max(best, tokenSimilarity({ a: txTokens, b: tokens }));
  }
  for (const tokens of profile.learnedTokens) {
    const similarity = tokenSimilarity({ a: txTokens, b: tokens });
    if (similarity > best) {
      best = similarity;
      code = MATCH_REASON_CODE.learnedMerchant;
    }
  }

  const value = mapMerchantSimilarity({ similarity: best });
  return { value, reason: value > 0 ? { code, weight, value: round3(value) } : null };
};

/**
 * Scores one (recurring payment, transaction) pair. Returns null when a hard gate excludes the pair:
 * type mismatch, two-leg transfer, or a failing explicit amount / account / type rule.
 * Link-state gates (active links, dismissals, unlinks) are the caller's job.
 */
export async function scoreTransaction({
  profile,
  transaction,
  fx,
}: {
  profile: SubscriptionProfile;
  transaction: ScorableTransaction;
  fx: FxConvert;
}): Promise<MatchScore | null> {
  if (transaction.transactionType !== profile.transactionType) return null;
  if (isTwoLegTransfer(transaction.transferNature)) return null;

  let allRulesPass = profile.rules.length > 0;
  for (const rule of profile.rules) {
    const passed = await evaluateRule({ rule, transaction, fx });
    if (!passed && isGatingRule({ rule })) return null;
    if (!passed) allRulesPass = false;
  }

  const reasons: MatchReason[] = [];

  const merchant = scoreMerchant({ profile, transaction });
  if (merchant.reason) reasons.push(merchant.reason);

  const note = (transaction.note || '').toLowerCase();
  const keyword = profile.keywords.some((value) => value && note.includes(value)) ? 1 : 0;
  if (keyword) reasons.push({ code: MATCH_REASON_CODE.keywordMatch, weight: SIGNAL_WEIGHTS.keyword, value: 1 });

  // Date proximity to the nearest expected occurrence.
  const windowDays = MATCH_WINDOW_DAYS[profile.frequency];
  const nearest = nearestExpectedDate({
    dates: expectedDatesAround({
      anchor: profile.anchor,
      anchorDay: profile.anchorDay,
      frequency: profile.frequency,
      periodDueDates: profile.periods.map((period) => period.dueDate),
      around: transaction.time,
      windowDays,
    }),
    date: transaction.time,
  });
  let date = 0.5;
  if (nearest) {
    date = Math.max(0, 1 - nearest.days / windowDays);
    reasons.push({
      code: date > 0 ? MATCH_REASON_CODE.nearDueDate : MATCH_REASON_CODE.farFromDueDate,
      weight: SIGNAL_WEIGHTS.date,
      value: round3(date),
      detail: { dueDate: nearest.dueDate, days: nearest.days },
    });
  }

  // Amount is a soft signal: a price change lowers the score instead of hiding the match.
  let amount = 0.5;
  let amountCloseness = 0;
  let amountDeviationPct: number | null = null;
  if (profile.amount && !profile.amount.expected.isZero()) {
    const txAmount =
      transaction.currencyCode === profile.amount.currencyCode
        ? transaction.amount.abs()
        : await fx({
            amount: transaction.amount.abs(),
            date: transaction.time,
            from: transaction.currencyCode,
            to: profile.amount.currencyCode,
          });

    if (txAmount) {
      const expected = profile.amount.expected.toNumber();
      const signed = (txAmount.toNumber() - expected) / expected;
      amountDeviationPct = Math.round(signed * 1000) / 10;
      amountCloseness = Math.max(0, 1 - Math.abs(signed));
      const ratio = profile.amount.learned && profile.amount.variable ? Math.abs(signed) / 2 : Math.abs(signed);
      if (ratio <= AMOUNT_EXACT_RATIO) amount = 1;
      else if (ratio >= AMOUNT_ZERO_RATIO) amount = 0;
      else amount = 1 - (ratio - AMOUNT_EXACT_RATIO) / (AMOUNT_ZERO_RATIO - AMOUNT_EXACT_RATIO);

      reasons.push({
        code: ratio <= AMOUNT_CLOSE_RATIO ? MATCH_REASON_CODE.amountClose : MATCH_REASON_CODE.amountDiffers,
        weight: SIGNAL_WEIGHTS.amount,
        value: round3(amount),
        detail: { deviationPct: amountDeviationPct },
      });
    }
  }

  let account = 0.5;
  if (profile.accounts.size > 0) {
    account = profile.accounts.has(transaction.accountId) ? 1 : 0;
    if (account === 1) reasons.push({ code: MATCH_REASON_CODE.sameAccount, weight: SIGNAL_WEIGHTS.account, value: 1 });
  }

  let category = 0.5;
  if (profile.categoryId && transaction.categoryId) {
    category = profile.categoryId === transaction.categoryId ? 1 : 0;
    if (category === 1) {
      reasons.push({ code: MATCH_REASON_CODE.sameCategory, weight: SIGNAL_WEIGHTS.category, value: 1 });
    }
  }

  const signals = { merchant: merchant.value, keyword, date, amount, account, category };
  let score =
    SIGNAL_WEIGHTS.merchant * signals.merchant +
    SIGNAL_WEIGHTS.keyword * signals.keyword +
    SIGNAL_WEIGHTS.date * signals.date +
    SIGNAL_WEIGHTS.amount * signals.amount +
    SIGNAL_WEIGHTS.account * signals.account +
    SIGNAL_WEIGHTS.category * signals.category;

  if (allRulesPass) {
    score = Math.max(score, RULE_MATCH_FLOOR);
    reasons.unshift({ code: MATCH_REASON_CODE.ruleMatch, weight: 0, value: 1 });
  }

  // Caps: each limits the pair to the suggested tier.
  let capped = false;
  if (profile.scopedAccountId && profile.scopedAccountId !== transaction.accountId) {
    capped = true;
    reasons.push({ code: MATCH_REASON_CODE.differentAccount, weight: 0, value: 0 });
  }
  if (!allRulesPass && profile.frequency !== SUBSCRIPTION_FREQUENCIES.weekly && nearest && nearest.days <= windowDays) {
    const coveredByPeriod = profile.periods.some(
      (period) => period.dueDate === nearest.dueDate && period.transactionId && period.transactionId !== transaction.id,
    );
    const coveredByLink = profile.linkedDates.some(
      (linkedDate) =>
        daysBetween({ dueDate: nearest.dueDate, date: new Date(`${linkedDate}T00:00:00Z`) }) <= windowDays,
    );
    if (coveredByPeriod || coveredByLink) {
      capped = true;
      reasons.push({
        code: MATCH_REASON_CODE.periodAlreadyCovered,
        weight: 0,
        value: 0,
        detail: { dueDate: nearest.dueDate },
      });
    }
  }
  if (transaction.isPlanned && !allRulesPass) capped = true;

  return {
    subscriptionId: profile.id,
    transactionId: transaction.id,
    score: round3(Math.min(1, score)),
    signals,
    reasons,
    ruleMatch: allRulesPass,
    amountCloseness,
    capped,
    nearestDueDate: nearest?.dueDate ?? null,
    daysFromDue: nearest?.days ?? null,
    amountDeviationPct,
  };
}

/** Tier of a single scored pair, before the cross-subscription ambiguity check. */
export function tierOf({ match }: { match: MatchScore }): MatchTier {
  const { score, signals, ruleMatch, capped } = match;
  const hasIdentity = ruleMatch || signals.merchant >= 0.6 || signals.keyword === 1;
  if (!capped && score >= SUBSCRIPTION_AUTO_LINK_MIN_SCORE && hasIdentity) return 'auto';

  const hasEvidence =
    ruleMatch || signals.merchant >= 0.3 || signals.keyword === 1 || (signals.amount >= 0.9 && signals.date >= 0.7);
  if (score >= SUBSCRIPTION_SUGGESTION_MIN_SCORE && hasEvidence) return 'suggested';

  return 'none';
}
