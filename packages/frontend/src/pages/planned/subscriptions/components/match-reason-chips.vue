<script setup lang="ts">
import { cn } from '@/lib/utils';
import { MATCH_REASON_CODE, type MatchReason } from '@bt/shared/types';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps<{ reasons: MatchReason[] }>();

const { t } = useI18n();

type ChipTone = 'positive' | 'caution';

interface ReasonChip {
  code: string;
  label: string;
  tone: ChipTone;
}

const TONE_CLASSES: Record<ChipTone, string> = {
  positive: 'bg-primary/10 text-primary-text',
  caution: 'bg-warning-text/10 text-warning-text',
};

const REASON_KEY_PREFIX = 'planned.subscriptions.suggestions.reasons';

/** Signed whole-percent label ("+16%", "-4%"); null when it rounds to zero. */
const formatDeviation = ({ deviationPct }: { deviationPct: number }): string | null => {
  const rounded = Math.round(deviationPct);
  if (rounded === 0) return null;
  return `${rounded > 0 ? '+' : ''}${rounded}%`;
};

const buildDueDateLabel = ({ reason, fallbackKey }: { reason: MatchReason; fallbackKey: string }): string => {
  const days = reason.detail?.days;
  if (days === undefined) return t(`${REASON_KEY_PREFIX}.${fallbackKey}`);
  if (days === 0) return t(`${REASON_KEY_PREFIX}.onDueDate`);
  return t(`${REASON_KEY_PREFIX}.daysFromDue`, { count: Math.abs(days) });
};

const buildAmountLabel = ({ reason, fallbackKey }: { reason: MatchReason; fallbackKey: string }): string => {
  const deviationPct = reason.detail?.deviationPct;
  if (deviationPct === undefined) return t(`${REASON_KEY_PREFIX}.${fallbackKey}`);
  const pct = formatDeviation({ deviationPct });
  return pct ? t(`${REASON_KEY_PREFIX}.amountDeviation`, { pct }) : t(`${REASON_KEY_PREFIX}.amountSame`);
};

/** Reason codes the client doesn't know yet are skipped, so new server codes never break the row. */
const buildChip = ({ reason }: { reason: MatchReason }): ReasonChip | null => {
  const simple = ({ key, tone }: { key: string; tone: ChipTone }): ReasonChip => ({
    code: reason.code,
    label: t(`${REASON_KEY_PREFIX}.${key}`),
    tone,
  });

  switch (reason.code) {
    case MATCH_REASON_CODE.payeeMatch:
      return simple({ key: 'payeeMatch', tone: 'positive' });
    case MATCH_REASON_CODE.merchantSimilar:
      return simple({ key: 'merchantSimilar', tone: 'positive' });
    case MATCH_REASON_CODE.learnedMerchant:
      return simple({ key: 'learnedMerchant', tone: 'positive' });
    case MATCH_REASON_CODE.keywordMatch:
      return simple({ key: 'keywordMatch', tone: 'positive' });
    case MATCH_REASON_CODE.ruleMatch:
      return simple({ key: 'ruleMatch', tone: 'positive' });
    case MATCH_REASON_CODE.sameAccount:
      return simple({ key: 'sameAccount', tone: 'positive' });
    case MATCH_REASON_CODE.differentAccount:
      return simple({ key: 'differentAccount', tone: 'caution' });
    case MATCH_REASON_CODE.sameCategory:
      return simple({ key: 'sameCategory', tone: 'positive' });
    case MATCH_REASON_CODE.periodAlreadyCovered:
      return simple({ key: 'periodAlreadyCovered', tone: 'caution' });
    case MATCH_REASON_CODE.ambiguousWithOtherSubscription:
      return simple({ key: 'ambiguousWithOtherSubscription', tone: 'caution' });
    case MATCH_REASON_CODE.nearDueDate:
      return { code: reason.code, label: buildDueDateLabel({ reason, fallbackKey: 'nearDueDate' }), tone: 'positive' };
    case MATCH_REASON_CODE.farFromDueDate:
      return {
        code: reason.code,
        label: buildDueDateLabel({ reason, fallbackKey: 'farFromDueDate' }),
        tone: 'caution',
      };
    case MATCH_REASON_CODE.amountClose:
      return { code: reason.code, label: buildAmountLabel({ reason, fallbackKey: 'amountClose' }), tone: 'positive' };
    case MATCH_REASON_CODE.amountDiffers:
      return { code: reason.code, label: buildAmountLabel({ reason, fallbackKey: 'amountDiffers' }), tone: 'caution' };
    default:
      return null;
  }
};

const chips = computed(() =>
  props.reasons.flatMap((reason) => {
    const chip = buildChip({ reason });
    return chip ? [chip] : [];
  }),
);
</script>

<template>
  <ul v-if="chips.length" class="flex flex-wrap gap-1.5">
    <li
      v-for="chip in chips"
      :key="chip.code"
      :class="cn('inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-medium', TONE_CLASSES[chip.tone])"
    >
      {{ chip.label }}
    </li>
  </ul>
</template>
