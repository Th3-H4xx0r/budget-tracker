<script setup lang="ts">
import { linkTransactionsToSubscription, searchLinkableTransactions } from '@/api/subscriptions';
import { VUE_QUERY_CACHE_KEYS, VUE_QUERY_GLOBAL_PREFIXES } from '@/common/const';
import ResponsiveDialog from '@/components/common/responsive-dialog.vue';
import AccountMultiSelectField from '@/components/fields/account-multi-select-field.vue';
import DateField from '@/components/fields/date-field.vue';
import InputField from '@/components/fields/input-field.vue';
import Button from '@/components/lib/ui/button/Button.vue';
import { ScrollArea } from '@/components/lib/ui/scroll-area';
import { useNotificationCenter } from '@/components/notification-center';
import TransactionRecordSkeleton from '@/components/transactions-list/transaction-record-skeleton.vue';
import TransactionRecord from '@/components/transactions-list/transaction-record.vue';
import { useInvalidateSubscriptionQueries } from '@/composable/data-queries/subscriptions';
import { cn } from '@/lib/utils';
import { useInfiniteQuery, useMutation, useQueryClient } from '@tanstack/vue-query';
import { refDebounced, useIntersectionObserver } from '@vueuse/core';
import { format } from 'date-fns';
import { LinkIcon, SearchXIcon } from '@lucide/vue';
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps<{ subscriptionId: string }>();

const isOpen = defineModel<boolean>('open', { default: false });

const { t } = useI18n();
const queryClient = useQueryClient();
const invalidateSubscriptionQueries = useInvalidateSubscriptionQueries();
const { addSuccessNotification, addErrorNotification } = useNotificationCenter();

const PAGE_SIZE = 30;
const SEARCH_DEBOUNCE_MS = 300;
const SKELETON_ROWS = 6;
const API_DATE_FORMAT = 'yyyy-MM-dd';

const search = ref('');
const debouncedSearch = refDebounced(search, SEARCH_DEBOUNCE_MS);
const fromDate = ref<Date | undefined>(undefined);
const toDate = ref<Date | undefined>(undefined);
const accountIds = ref<string[]>([]);
const selectedIds = ref<Set<string>>(new Set());

const filters = computed(() => ({
  search: debouncedSearch.value.trim() || undefined,
  from: fromDate.value ? format(fromDate.value, API_DATE_FORMAT) : undefined,
  to: toDate.value ? format(toDate.value, API_DATE_FORMAT) : undefined,
  accountIds: accountIds.value.length ? [...accountIds.value] : undefined,
}));

const hasActiveFilters = computed(() => Object.values(filters.value).some((value) => value !== undefined));

const resetFilters = () => {
  search.value = '';
  fromDate.value = undefined;
  toDate.value = undefined;
  accountIds.value = [];
};

// Each opening starts from a clean picker so a stale selection can't be linked by accident.
watch(isOpen, (open) => {
  if (!open) return;
  selectedIds.value = new Set();
  resetFilters();
});

const { data, isLoading, fetchNextPage, hasNextPage, isFetchingNextPage } = useInfiniteQuery({
  queryKey: computed(() => [
    ...VUE_QUERY_CACHE_KEYS.subscriptionLinkableTransactions,
    props.subscriptionId,
    filters.value,
  ]),
  queryFn: ({ pageParam }) =>
    searchLinkableTransactions({
      id: props.subscriptionId,
      ...filters.value,
      // Relevance only means something against a search term; otherwise newest first.
      sort: filters.value.search ? 'relevance' : 'date',
      limit: PAGE_SIZE,
      offset: pageParam,
    }),
  initialPageParam: 0,
  getNextPageParam: (lastPage, pages) => (lastPage.hasMore ? pages.length * PAGE_SIZE : undefined),
  enabled: isOpen,
  staleTime: Infinity,
});

const items = computed(() => data.value?.pages.flatMap((page) => page.items) ?? []);

const sentinelRef = ref<HTMLElement | null>(null);
useIntersectionObserver(sentinelRef, ([entry]) => {
  if (entry?.isIntersecting && hasNextPage.value && !isFetchingNextPage.value) {
    fetchNextPage();
  }
});

const toggleSelection = ({ transactionId }: { transactionId: string }) => {
  const next = new Set(selectedIds.value);
  if (next.has(transactionId)) {
    next.delete(transactionId);
  } else {
    next.add(transactionId);
  }
  selectedIds.value = next;
};

const formatScore = ({ score }: { score: number }) => `${Math.round(score * 100)}%`;

const linkMutation = useMutation({
  mutationFn: () =>
    linkTransactionsToSubscription({ id: props.subscriptionId, transactionIds: Array.from(selectedIds.value) }),
  onSuccess: () => {
    invalidateSubscriptionQueries();
    queryClient.invalidateQueries({ queryKey: [VUE_QUERY_GLOBAL_PREFIXES.transactionChange] });
    addSuccessNotification(t('planned.subscriptions.linkSuccess'));
    isOpen.value = false;
  },
  onError: () => addErrorNotification(t('planned.subscriptions.linkError')),
});
</script>

<template>
  <ResponsiveDialog v-model:open="isOpen" dialog-content-class="max-w-2xl" no-internal-scroll>
    <template #title>{{ $t('planned.subscriptions.linkDialog.title') }}</template>
    <template #description>{{ $t('planned.subscriptions.linkDialog.description') }}</template>

    <div class="@container/link-picker flex min-h-0 flex-col gap-3">
      <InputField
        v-model="search"
        type="search"
        :aria-label="$t('planned.subscriptions.linkDialog.searchPlaceholder')"
        :placeholder="$t('planned.subscriptions.linkDialog.searchPlaceholder')"
      />

      <div class="grid grid-cols-1 gap-2 @md/link-picker:grid-cols-3">
        <DateField
          v-model="fromDate"
          :label="$t('planned.subscriptions.linkDialog.fromLabel')"
          :calendar-options="{ maxDate: toDate }"
        />
        <DateField
          v-model="toDate"
          :label="$t('planned.subscriptions.linkDialog.toLabel')"
          :calendar-options="{ minDate: fromDate }"
        />
        <AccountMultiSelectField
          v-model="accountIds"
          :label="$t('planned.subscriptions.linkDialog.accountsLabel')"
          :placeholder="$t('planned.subscriptions.linkDialog.allAccounts')"
        />
      </div>

      <ScrollArea class="h-[min(50vh,28rem)] rounded-lg border">
        <div v-if="isLoading" class="space-y-1 p-2">
          <TransactionRecordSkeleton v-for="i in SKELETON_ROWS" :key="i" />
        </div>

        <div
          v-else-if="!items.length"
          class="text-muted-foreground flex flex-col items-center justify-center gap-2 px-6 py-10 text-center"
        >
          <SearchXIcon class="size-8 opacity-50" />
          <p class="text-foreground text-sm font-medium">
            {{ $t('planned.subscriptions.linkDialog.emptyTitle') }}
          </p>
          <p class="text-sm">
            {{ $t('planned.subscriptions.linkDialog.emptyDescription') }}
          </p>
          <Button v-if="hasActiveFilters" variant="outline" size="sm" class="mt-1" @click="resetFilters">
            {{ $t('planned.subscriptions.linkDialog.resetFilters') }}
          </Button>
        </div>

        <div v-else class="divide-border divide-y">
          <div
            v-for="(item, index) in items"
            :key="item.transaction.id"
            :class="cn('py-1', item.linkedSubscription && 'opacity-60')"
          >
            <TransactionRecord
              :tx="item.transaction"
              :as-button="false"
              show-checkbox
              :is-selectable="!item.linkedSubscription"
              :is-selected="selectedIds.has(item.transaction.id)"
              :index="index"
              @selection-change="({ id }) => toggleSelection({ transactionId: id })"
              @record-click="() => !item.linkedSubscription && toggleSelection({ transactionId: item.transaction.id })"
            />
            <div
              v-if="item.linkedSubscription || item.isDismissed || item.score > 0"
              class="flex flex-wrap items-center gap-1.5 pr-2 pb-1 pl-12"
            >
              <span
                v-if="item.linkedSubscription"
                class="bg-muted text-muted-foreground inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium"
              >
                <LinkIcon class="size-3" />
                {{ $t('planned.subscriptions.linkDialog.linkedTo', { name: item.linkedSubscription.name }) }}
              </span>
              <span
                v-if="item.isDismissed"
                class="bg-muted text-muted-foreground inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-medium"
              >
                {{ $t('planned.subscriptions.linkDialog.dismissed') }}
              </span>
              <span v-if="item.score > 0" class="text-muted-foreground text-[11px] tabular-nums">
                {{ $t('planned.subscriptions.linkDialog.matchScore', { score: formatScore({ score: item.score }) }) }}
              </span>
            </div>
          </div>

          <div ref="sentinelRef" class="h-1" />
          <div v-if="isFetchingNextPage" class="p-2">
            <TransactionRecordSkeleton />
          </div>
        </div>
      </ScrollArea>
    </div>

    <template #footer>
      <div class="flex justify-end gap-2">
        <Button variant="outline" @click="isOpen = false">
          {{ $t('planned.subscriptions.cancel') }}
        </Button>
        <Button
          :disabled="selectedIds.size === 0 || linkMutation.isPending.value"
          :loading="linkMutation.isPending.value"
          @click="linkMutation.mutate()"
        >
          <LinkIcon class="size-4" />
          {{ $t('planned.subscriptions.linkSelected', { count: selectedIds.size }) }}
        </Button>
      </div>
    </template>
  </ResponsiveDialog>
</template>
