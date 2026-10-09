<template>
  <PageWrapper class="flex max-w-4xl flex-col gap-4">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="min-w-0">
        <h1 class="text-2xl font-semibold tracking-tight">{{ $t('transactionReview.page.title') }}</h1>
        <p class="text-muted-foreground mt-1 text-sm">{{ $t('transactionReview.card.subtitle') }}</p>
      </div>
      <!-- Only a count known to be 0 disables it: while the summary loads or after it
           fails, the stack can still load the queue itself. -->
      <Button :disabled="unreviewedCount === 0" @click="isStackOpen = true">
        <PlayIcon class="size-4" />
        {{ $t('transactionReview.page.startReview') }}
      </Button>
    </div>

    <Tabs :model-value="activeTab" @update:model-value="onTabChange">
      <TabsList variant="underline">
        <TabsTrigger v-for="tab in tabs" :key="tab.status" :value="tab.status">
          {{ tab.label }}
          <span
            v-if="tab.count !== null"
            :class="
              cn(
                'rounded-full px-1.5 text-xs leading-5 tabular-nums',
                tab.status === TRANSACTION_REVIEW_STATUS.fraud && (tab.count ?? 0) > 0
                  ? 'bg-destructive/15 text-destructive-text'
                  : 'bg-muted text-muted-foreground',
              )
            "
          >
            {{ tab.count }}
          </span>
        </TabsTrigger>
      </TabsList>

      <TabsContent v-for="tab in tabs" :key="tab.status" :value="tab.status" class="mt-3">
        <ReviewTabList v-if="activeTab === tab.status" :status="tab.status" />
      </TabsContent>
    </Tabs>

    <ReviewStackDialog v-model:open="isStackOpen" />
  </PageWrapper>
</template>

<script setup lang="ts">
import PageWrapper from '@/components/common/page-wrapper.vue';
import { Button } from '@/components/lib/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/lib/ui/tabs';
import ReviewStackDialog from '@/components/transaction-review/review-stack-dialog.vue';
import { useTransactionReviewSummary } from '@/composable/data-queries/transaction-review';
import { cn } from '@/lib/utils';
import {
  TRANSACTION_REVIEW_LIST_STATUSES,
  TRANSACTION_REVIEW_STATUS,
  type TransactionReviewListStatus,
} from '@bt/shared/types';
import { PlayIcon } from '@lucide/vue';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import ReviewTabList from './components/review-tab-list.vue';

defineOptions({
  name: 'page-transactions-review',
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { unreviewedCount, fraudCount } = useTransactionReviewSummary();

const isStackOpen = ref(false);

const parseTabStatus = ({ value }: { value: unknown }): TransactionReviewListStatus | null =>
  TRANSACTION_REVIEW_LIST_STATUSES.find((status) => status === value) ?? null;

// The query string holds the tab, so the dashboard's fraud link can open the Fraud tab directly.
const activeTab = computed<TransactionReviewListStatus>(
  () => parseTabStatus({ value: route.query.tab }) ?? TRANSACTION_REVIEW_STATUS.unreviewed,
);

const onTabChange = (value: string | number) => {
  const tab = parseTabStatus({ value: String(value) });
  if (!tab || tab === activeTab.value) return;
  router.replace({ query: { ...route.query, tab } });
};

// A `null` count is unknown (loading or failed), so its pill stays hidden.
const tabs = computed(
  () =>
    [
      {
        status: TRANSACTION_REVIEW_STATUS.unreviewed,
        label: t('transactionReview.tabs.unreviewed'),
        count: unreviewedCount.value,
      },
      {
        status: TRANSACTION_REVIEW_STATUS.reviewed,
        label: t('transactionReview.tabs.reviewed'),
        count: null,
      },
      {
        status: TRANSACTION_REVIEW_STATUS.fraud,
        label: t('transactionReview.tabs.fraud'),
        count: fraudCount.value,
      },
    ] satisfies { status: TransactionReviewListStatus; label: string; count: number | null }[],
);
</script>
