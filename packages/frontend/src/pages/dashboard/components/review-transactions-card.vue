<template>
  <!-- Without counts the card can't say anything, but silently hiding it would also hide
       the review entry point, so a failed load gets its own compact card. -->
  <div v-if="isSummaryUnavailable" class="mb-4 flex items-center gap-3 rounded-lg border px-4 py-2.5">
    <ShieldAlertIcon class="text-warning-text size-4 shrink-0" />
    <p class="text-muted-foreground min-w-0 flex-1 text-sm">{{ $t('transactionReview.card.loadFailed') }}</p>
    <Button variant="outline" size="sm" class="shrink-0" :disabled="isFetching" @click="refetch()">
      <RotateCwIcon :class="cn('size-4', isFetching && 'animate-spin')" />
      {{ $t('common.actions.retry') }}
    </Button>
  </div>

  <div v-else-if="pendingCount > 0" class="@container/review-card mb-4">
    <div
      class="bg-card flex flex-col gap-3 rounded-lg border px-4 py-3 @lg/review-card:flex-row @lg/review-card:items-center @lg/review-card:gap-4"
    >
      <div class="flex min-w-0 flex-1 items-start gap-3">
        <ShieldCheckIcon class="text-primary-text mt-0.5 size-5 shrink-0" />
        <div class="min-w-0">
          <p class="font-medium">
            {{ $t('transactionReview.card.title', { count: pendingCount }, pendingCount) }}
          </p>
          <p class="text-muted-foreground mt-1 text-sm">{{ $t('transactionReview.card.subtitle') }}</p>
          <RouterLink
            v-if="flaggedCount > 0"
            :to="{ name: ROUTES_NAMES.transactionsReview, query: { tab: TRANSACTION_REVIEW_STATUS.fraud } }"
            class="text-destructive-text mt-1 inline-flex items-center gap-1 text-sm font-medium hover:underline"
          >
            <ShieldAlertIcon class="size-3.5" />
            {{ $t('transactionReview.card.fraudLink', { count: flaggedCount }, flaggedCount) }}
          </RouterLink>
        </div>
      </div>
      <Button class="w-full @lg/review-card:w-auto @lg/review-card:shrink-0" @click="isStackOpen = true">
        {{ $t('transactionReview.card.reviewButton') }}
      </Button>
    </div>
  </div>

  <!-- Outside the v-if: reviewing the last row drops the count to 0 while the stack
       still has to show its "All caught up" state. -->
  <ReviewStackDialog v-model:open="isStackOpen" />
</template>

<script setup lang="ts">
import { Button } from '@/components/lib/ui/button';
import ReviewStackDialog from '@/components/transaction-review/review-stack-dialog.vue';
import { useTransactionReviewSummary } from '@/composable/data-queries/transaction-review';
import { cn } from '@/lib/utils';
import { ROUTES_NAMES } from '@/routes/constants';
import { TRANSACTION_REVIEW_STATUS } from '@bt/shared/types';
import { RotateCwIcon, ShieldAlertIcon, ShieldCheckIcon } from '@lucide/vue';
import { computed, ref } from 'vue';

const { unreviewedCount, fraudCount, isLoaded, isError, isFetching, refetch } = useTransactionReviewSummary();

// A failed background refetch keeps the last known counts on screen; only a summary
// that never loaded falls back to the error card.
const isSummaryUnavailable = computed(() => isError.value && !isLoaded.value);
const pendingCount = computed(() => unreviewedCount.value ?? 0);
const flaggedCount = computed(() => fraudCount.value ?? 0);

const isStackOpen = ref(false);
</script>
