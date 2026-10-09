<template>
  <div v-if="isLoading" class="grid gap-2" aria-hidden="true">
    <TransactionRecordSkeleton v-for="index in SKELETON_ROWS" :key="index" />
  </div>

  <div v-else-if="isError" class="flex flex-col items-center gap-3 py-12 text-center">
    <p class="text-muted-foreground text-sm">{{ $t('transactionReview.loadFailed') }}</p>
    <Button variant="outline" size="sm" @click="refetch()">
      <RotateCwIcon class="size-4" />
      {{ $t('common.actions.retry') }}
    </Button>
  </div>

  <div v-else-if="transactions.length === 0" class="flex flex-col items-center px-4 py-12 text-center">
    <div class="bg-muted flex size-12 items-center justify-center rounded-full">
      <component :is="emptyState.icon" class="text-muted-foreground size-6" />
    </div>
    <p class="mt-4 font-medium">{{ emptyState.title }}</p>
    <p class="text-muted-foreground mt-1 max-w-sm text-sm">{{ emptyState.description }}</p>
  </div>

  <TransactionsList
    v-else
    :transactions="transactions"
    :has-next-page="hasNextPage"
    :is-fetching-next-page="isFetchingNextPage"
    disable-grouping
    disable-transfer-dedup
    @fetch-next-page="fetchNextPage"
  >
    <template #row-trailing="{ tx }">
      <ReviewRowActions
        :status="status"
        @act="({ action }) => rowAction.mutate({ transactionId: tx.id, fromStatus: status, action })"
      />
    </template>
  </TransactionsList>
</template>

<script setup lang="ts">
import { Button } from '@/components/lib/ui/button';
import TransactionRecordSkeleton from '@/components/transactions-list/transaction-record-skeleton.vue';
import TransactionsList from '@/components/transactions-list/transactions-list.vue';
import { useTransactionReviewList, useTransactionReviewRowAction } from '@/composable/data-queries/transaction-review';
import { TRANSACTION_REVIEW_STATUS, type TransactionReviewListStatus } from '@bt/shared/types';
import { CircleCheckIcon, ListChecksIcon, RotateCwIcon, ShieldCheckIcon } from '@lucide/vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import ReviewRowActions from './review-row-actions.vue';

const SKELETON_ROWS = 6;

const props = defineProps<{
  status: TransactionReviewListStatus;
}>();

const { t } = useI18n();

const { transactions, isLoading, isError, refetch, hasNextPage, isFetchingNextPage, fetchNextPage } =
  useTransactionReviewList({ status: () => props.status });

const rowAction = useTransactionReviewRowAction();

const emptyState = computed(() => {
  if (props.status === TRANSACTION_REVIEW_STATUS.unreviewed) {
    return {
      icon: CircleCheckIcon,
      title: t('transactionReview.empty.unreviewed.title'),
      description: t('transactionReview.empty.unreviewed.description'),
    };
  }
  if (props.status === TRANSACTION_REVIEW_STATUS.reviewed) {
    return {
      icon: ListChecksIcon,
      title: t('transactionReview.empty.reviewed.title'),
      description: t('transactionReview.empty.reviewed.description'),
    };
  }
  return {
    icon: ShieldCheckIcon,
    title: t('transactionReview.empty.fraud.title'),
    description: t('transactionReview.empty.fraud.description'),
  };
});
</script>
