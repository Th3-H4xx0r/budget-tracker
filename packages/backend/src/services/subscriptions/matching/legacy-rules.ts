import type { SubscriptionMatchingRule } from '@bt/shared/types';
import { Money } from '@common/types/money';

import type { FxConvert, ScorableTransaction } from './types';

const CROSS_CURRENCY_TOLERANCE = 0.05;

/** Rule fields the user set explicitly as filters: a failing one excludes the transaction outright. */
const GATING_FIELDS = new Set(['amount', 'accountId', 'transactionType']);

export const isGatingRule = ({ rule }: { rule: SubscriptionMatchingRule }): boolean => GATING_FIELDS.has(rule.field);

/** Legacy rule semantics: note contains-any (case-insensitive), amount between, type / account equals. */
export async function evaluateRule({
  rule,
  transaction,
  fx,
}: {
  rule: SubscriptionMatchingRule;
  transaction: ScorableTransaction;
  fx: FxConvert;
}): Promise<boolean> {
  switch (rule.field) {
    case 'note': {
      if (rule.operator !== 'contains_any' || !Array.isArray(rule.value)) return false;
      const note = (transaction.note || '').toLowerCase();
      return (rule.value as string[]).some((value) => note.includes(value.toLowerCase()));
    }
    case 'amount': {
      if (rule.operator !== 'between' || typeof rule.value !== 'object' || Array.isArray(rule.value)) return false;
      const { min, max } = rule.value as { min: number; max: number };
      const minCents = Money.fromDecimal(min).toCents();
      const maxCents = Money.fromDecimal(max).toCents();
      const amount = transaction.amount.abs();

      if (!rule.currencyCode || rule.currencyCode === transaction.currencyCode) {
        const cents = amount.toCents();
        return cents >= minCents && cents <= maxCents;
      }

      const converted = await fx({
        amount,
        date: transaction.time,
        from: transaction.currencyCode,
        to: rule.currencyCode,
      });
      if (!converted) return false;

      const cents = converted.toCents();
      return (
        cents >= Math.floor(minCents * (1 - CROSS_CURRENCY_TOLERANCE)) &&
        cents <= Math.ceil(maxCents * (1 + CROSS_CURRENCY_TOLERANCE))
      );
    }
    case 'transactionType':
      return rule.operator === 'equals' && transaction.transactionType === rule.value;
    case 'accountId':
      return rule.operator === 'equals' && transaction.accountId === rule.value;
    default:
      return false;
  }
}
