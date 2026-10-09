<template>
  <div class="grid grid-cols-3 gap-2">
    <Button
      variant="soft-destructive"
      class="h-auto min-h-11 px-2 py-2 whitespace-normal"
      @click="emit('act', { action: TRANSACTION_REVIEW_ACTION.fraud })"
    >
      <ShieldAlertIcon class="size-4 shrink-0" />
      {{ $t('transactionReview.actions.fraud') }}
      <kbd v-if="showShortcuts" aria-hidden="true" :class="kbdClass">F</kbd>
    </Button>
    <Button
      variant="outline"
      class="h-auto min-h-11 px-2 py-2 whitespace-normal"
      @click="emit('act', { action: TRANSACTION_REVIEW_ACTION.checkLater })"
    >
      <ClockIcon class="size-4 shrink-0" />
      {{ $t('transactionReview.actions.checkLater') }}
      <kbd v-if="showShortcuts" aria-hidden="true" :class="kbdClass">←</kbd>
    </Button>
    <Button
      ref="primaryButtonRef"
      class="h-auto min-h-11 px-2 py-2 whitespace-normal"
      @click="emit('act', { action: TRANSACTION_REVIEW_ACTION.reviewed })"
    >
      <CheckIcon class="size-4 shrink-0" />
      {{ $t('transactionReview.actions.looksGood') }}
      <kbd v-if="showShortcuts" aria-hidden="true" :class="kbdClass">→</kbd>
    </Button>
  </div>
</template>

<script lang="ts" setup>
import { Button } from '@/components/lib/ui/button';
import { TRANSACTION_REVIEW_ACTION } from '@bt/shared/types';
import { CheckIcon, ClockIcon, ShieldAlertIcon } from '@lucide/vue';
import { onMounted, ref } from 'vue';

import type { ReviewDecision } from './use-review-session';

const props = defineProps<{
  /** Desktop only: shows key hints and keeps focus on "Looks good" so Enter confirms. */
  showShortcuts: boolean;
}>();

const emit = defineEmits<{
  act: [{ action: ReviewDecision }];
}>();

const kbdClass = 'rounded bg-current/15 px-1 font-sans text-[10px] leading-4 font-medium';

const primaryButtonRef = ref<InstanceType<typeof Button> | null>(null);

const focusPrimary = () => {
  if (!props.showShortcuts) return;
  const element = primaryButtonRef.value?.$el as HTMLElement | undefined;
  element?.focus({ preventScroll: true });
};

// Focus moves to "Looks good" whenever the buttons appear, so Enter confirms without
// tabbing. The dialog's focus scope only picks a target when focus is outside it, so it
// leaves this alone.
onMounted(focusPrimary);

defineExpose({ focusPrimary });
</script>
