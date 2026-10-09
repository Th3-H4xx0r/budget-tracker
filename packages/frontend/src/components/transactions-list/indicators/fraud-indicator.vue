<template>
  <TooltipProvider v-if="isFraud" :delay-duration="0">
    <Tooltip>
      <TooltipTrigger as-child>
        <div
          :class="
            cn(
              'text-destructive-text flex shrink-0 items-center',
              compact ? 'size-4 justify-center' : 'bg-destructive/15 h-5 gap-1 rounded-sm px-1.5 text-xs font-medium',
            )
          "
          :aria-label="t('common.transactions.record.fraudTooltip')"
        >
          <ShieldAlertIcon :class="compact ? 'size-3.5' : 'size-3'" />
          <template v-if="!compact">{{ t('common.transactions.record.fraudChip') }}</template>
        </div>
      </TooltipTrigger>
      <TooltipContent>{{ t('common.transactions.record.fraudTooltip') }}</TooltipContent>
    </Tooltip>
  </TooltipProvider>
</template>

<script lang="ts" setup>
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/lib/ui/tooltip';
import { cn } from '@/lib/utils';
import { TRANSACTION_REVIEW_STATUS } from '@bt/shared/types';
import { ShieldAlertIcon } from '@lucide/vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const props = withDefaults(
  defineProps<{
    /** Any row shape works: projections such as budget rows carry only `reviewStatus`. */
    transaction: { reviewStatus?: TRANSACTION_REVIEW_STATUS | null };
    /** Icon-only rendering for dense cells; the label moves into the tooltip. */
    compact?: boolean;
  }>(),
  { compact: false },
);

const isFraud = computed(() => props.transaction.reviewStatus === TRANSACTION_REVIEW_STATUS.fraud);
</script>
