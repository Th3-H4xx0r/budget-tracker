<script setup lang="ts">
import {
  dismissSubscriptionSuggestions,
  linkTransactionsToSubscription,
  loadSubscriptionSuggestions,
} from '@/api/subscriptions';
import { VUE_QUERY_CACHE_KEYS, VUE_QUERY_GLOBAL_PREFIXES } from '@/common/const';
import Button from '@/components/lib/ui/button/Button.vue';
import { useNotificationCenter } from '@/components/notification-center';
import TransactionRecordSkeleton from '@/components/transactions-list/transaction-record-skeleton.vue';
import TransactionRecord from '@/components/transactions-list/transaction-record.vue';
import { useInvalidateSubscriptionQueries } from '@/composable/data-queries/subscriptions';
import { cn } from '@/lib/utils';
import type { MatchConfidence, SubscriptionSuggestionsResponse } from '@bt/shared/types';
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query';
import { LinkIcon, SparklesIcon, XIcon } from '@lucide/vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import MatchReasonChips from './match-reason-chips.vue';

const props = defineProps<{
  subscriptionId: string;
  /** Server-side pending count; drives the skeleton so the section doesn't pop in empty. */
  pendingSuggestionsCount: number;
}>();

const { t } = useI18n();
const queryClient = useQueryClient();
const invalidateSubscriptionQueries = useInvalidateSubscriptionQueries();
const { addSuccessNotification, addErrorNotification } = useNotificationCenter();

const SUGGESTIONS_LIMIT = 20;
const SKELETON_ROWS_MAX = 3;

const queryKey = computed(() => [...VUE_QUERY_CACHE_KEYS.subscriptionSuggestions, props.subscriptionId] as const);

const { data, isLoading } = useQuery({
  queryKey,
  queryFn: () => loadSubscriptionSuggestions({ id: props.subscriptionId, limit: SUGGESTIONS_LIMIT }),
  staleTime: Infinity,
});

const suggestions = computed(() => data.value?.suggestions ?? []);
const skeletonRows = computed(() => Math.min(SKELETON_ROWS_MAX, Math.max(1, props.pendingSuggestionsCount)));
const showSection = computed(
  () => suggestions.value.length > 0 || (isLoading.value && props.pendingSuggestionsCount > 0),
);

const CONFIDENCE_CLASSES: Record<MatchConfidence, string> = {
  high: 'bg-success-text/10 text-success-text',
  medium: 'bg-muted text-muted-foreground',
};

/** Drops the given rows from the cached list right away; returns the snapshot for rollback. */
const removeOptimistically = async ({ transactionIds }: { transactionIds: string[] }) => {
  await queryClient.cancelQueries({ queryKey: queryKey.value });
  const previous = queryClient.getQueryData<SubscriptionSuggestionsResponse>(queryKey.value);
  const ids = new Set(transactionIds);
  queryClient.setQueryData<SubscriptionSuggestionsResponse>(queryKey.value, (old) =>
    old ? { ...old, suggestions: old.suggestions.filter((s) => !ids.has(s.transaction.id)) } : old,
  );
  return { previous };
};

const rollback = ({ previous }: { previous?: SubscriptionSuggestionsResponse }) => {
  if (previous) queryClient.setQueryData(queryKey.value, previous);
};

const linkMutation = useMutation({
  mutationFn: ({ transactionId }: { transactionId: string }) =>
    linkTransactionsToSubscription({ id: props.subscriptionId, transactionIds: [transactionId] }),
  onMutate: ({ transactionId }) => removeOptimistically({ transactionIds: [transactionId] }),
  onSuccess: () => addSuccessNotification(t('planned.subscriptions.linkSuccess')),
  onError: (_err, _vars, context) => {
    rollback({ previous: context?.previous });
    addErrorNotification(t('planned.subscriptions.linkError'));
  },
  // Linking changes the payment's history, periods and plan entries, so every transaction view refreshes.
  onSettled: () => {
    invalidateSubscriptionQueries();
    queryClient.invalidateQueries({ queryKey: [VUE_QUERY_GLOBAL_PREFIXES.transactionChange] });
  },
});

const dismissMutation = useMutation({
  mutationFn: ({ transactionId }: { transactionId: string }) =>
    dismissSubscriptionSuggestions({ id: props.subscriptionId, transactionIds: [transactionId] }),
  onMutate: ({ transactionId }) => removeOptimistically({ transactionIds: [transactionId] }),
  onSuccess: () => addSuccessNotification(t('planned.subscriptions.suggestions.dismissSuccess')),
  onError: (_err, _vars, context) => {
    rollback({ previous: context?.previous });
    addErrorNotification(t('planned.subscriptions.suggestions.dismissError'));
  },
  onSettled: () => invalidateSubscriptionQueries(),
});

const isRowPending = ({ transactionId }: { transactionId: string }) =>
  (linkMutation.isPending.value && linkMutation.variables.value?.transactionId === transactionId) ||
  (dismissMutation.isPending.value && dismissMutation.variables.value?.transactionId === transactionId);
</script>

<template>
  <section v-if="showSection" class="@container/suggested mb-6">
    <div class="mb-3">
      <h2 class="flex items-center gap-2 text-lg font-semibold">
        <SparklesIcon class="text-primary-text size-4" />
        {{ $t('planned.subscriptions.suggestions.title') }}
        <span v-if="suggestions.length" class="text-muted-foreground text-sm font-normal">
          {{ suggestions.length }}
        </span>
      </h2>
      <p class="text-muted-foreground text-sm">
        {{ $t('planned.subscriptions.suggestions.description') }}
      </p>
    </div>

    <div class="border-border bg-card divide-border divide-y overflow-hidden rounded-lg border">
      <template v-if="isLoading">
        <div v-for="i in skeletonRows" :key="i" class="p-2">
          <TransactionRecordSkeleton />
        </div>
      </template>

      <template v-else>
        <div
          v-for="(suggestion, index) in suggestions"
          :key="suggestion.transaction.id"
          class="flex flex-col gap-2 p-2 @lg/suggested:flex-row @lg/suggested:items-center"
        >
          <div class="min-w-0 flex-1">
            <TransactionRecord :tx="suggestion.transaction" :as-button="false" :index="index" />
            <div class="mt-1 flex flex-wrap items-center gap-1.5 px-2">
              <span
                :class="
                  cn(
                    'inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-semibold',
                    CONFIDENCE_CLASSES[suggestion.confidence],
                  )
                "
              >
                {{ $t(`planned.subscriptions.suggestions.confidence.${suggestion.confidence}`) }}
              </span>
              <MatchReasonChips :reasons="suggestion.reasons" />
            </div>
          </div>

          <div class="flex shrink-0 justify-end gap-2 px-2">
            <Button
              variant="ghost"
              size="sm"
              :disabled="isRowPending({ transactionId: suggestion.transaction.id })"
              @click="dismissMutation.mutate({ transactionId: suggestion.transaction.id })"
            >
              <XIcon class="size-4" />
              {{ $t('planned.subscriptions.suggestions.dismiss') }}
            </Button>
            <Button
              variant="soft-primary"
              size="sm"
              :disabled="isRowPending({ transactionId: suggestion.transaction.id })"
              @click="linkMutation.mutate({ transactionId: suggestion.transaction.id })"
            >
              <LinkIcon class="size-4" />
              {{ $t('planned.subscriptions.suggestions.link') }}
            </Button>
          </div>
        </div>
      </template>
    </div>
  </section>
</template>
