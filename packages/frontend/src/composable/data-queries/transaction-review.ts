import {
  type TransactionReviewSummary,
  loadTransactionReviewSummary,
  loadTransactionsForReview,
  updateTransactionsReview,
} from '@/api/transaction-review';
import { VUE_QUERY_CACHE_KEYS, VUE_QUERY_GLOBAL_PREFIXES } from '@/common/const';
import { useNotificationCenter } from '@/components/notification-center';
import { extractApiErrorMessage } from '@/js/errors';
import {
  TRANSACTION_REVIEW_ACTION,
  TRANSACTION_REVIEW_STATUS,
  TRANSACTION_REVIEW_STATUS_BY_ACTION,
  type TransactionModel,
  type TransactionReviewListStatus,
} from '@bt/shared/types';
import { type InfiniteData, useInfiniteQuery, useMutation, useQuery, useQueryClient } from '@tanstack/vue-query';
import { type MaybeRefOrGetter, computed, toValue } from 'vue';
import { useI18n } from 'vue-i18n';

const TRANSACTION_REVIEW_PAGE_SIZE = 50;
const SUMMARY_STALE_TIME_MS = 60_000;

/** Actions the review page offers per row; "Check later" only exists in the card stack. */
export type TransactionReviewRowAction =
  | TRANSACTION_REVIEW_ACTION.reviewed
  | TRANSACTION_REVIEW_ACTION.fraud
  | TRANSACTION_REVIEW_ACTION.unreviewed;

const reviewListKey = ({ status }: { status: TransactionReviewListStatus }) =>
  [...VUE_QUERY_CACHE_KEYS.transactionReviewList, status] as const;

export const useTransactionReviewSummary = ({ enabled }: { enabled?: MaybeRefOrGetter<boolean> } = {}) => {
  const query = useQuery({
    queryKey: VUE_QUERY_CACHE_KEYS.transactionReviewSummary,
    queryFn: loadTransactionReviewSummary,
    // The sidebar keeps this mounted on every page; transaction writes invalidate it
    // through the transactionChange prefix, so a short stale window only saves focus refetches.
    staleTime: SUMMARY_STALE_TIME_MS,
    enabled: computed(() => (enabled === undefined ? true : toValue(enabled))),
  });

  // `null` means unknown (still loading, or the request failed). Callers must not read
  // it as zero: that would hide the dashboard card and disable "Start review".
  const unreviewedCount = computed<number | null>(() => query.data.value?.unreviewedCount ?? null);
  const fraudCount = computed<number | null>(() => query.data.value?.fraudCount ?? null);
  const isLoaded = computed(() => query.data.value !== undefined);

  return { ...query, unreviewedCount, fraudCount, isLoaded };
};

export const useTransactionReviewList = ({ status }: { status: MaybeRefOrGetter<TransactionReviewListStatus> }) => {
  const query = useInfiniteQuery({
    queryKey: computed(() => reviewListKey({ status: toValue(status) })),
    queryFn: ({ pageParam }) =>
      loadTransactionsForReview({
        status: toValue(status),
        limit: TRANSACTION_REVIEW_PAGE_SIZE,
        offset: pageParam * TRANSACTION_REVIEW_PAGE_SIZE,
      }),
    initialPageParam: 0,
    getNextPageParam: (lastPage, pages) => (lastPage.length < TRANSACTION_REVIEW_PAGE_SIZE ? undefined : pages.length),
  });

  const transactions = computed<TransactionModel[]>(() => query.data.value?.pages.flat() ?? []);

  return { ...query, transactions };
};

/** Invalidates the review summary only; the stack calls it after each write to keep badges current. */
export const invalidateTransactionReviewSummary = ({
  queryClient,
}: {
  queryClient: ReturnType<typeof useQueryClient>;
}) => queryClient.invalidateQueries({ queryKey: VUE_QUERY_CACHE_KEYS.transactionReviewSummary });

/**
 * Review status shows up in every transaction list (the fraud chip), so a finished write
 * refreshes the whole transactionChange scope, which includes the review summary and tabs.
 */
export const invalidateAfterReviewChange = ({ queryClient }: { queryClient: ReturnType<typeof useQueryClient> }) =>
  queryClient.invalidateQueries({ queryKey: [VUE_QUERY_GLOBAL_PREFIXES.transactionChange] });

const SUCCESS_KEY_BY_ACTION: Record<TransactionReviewRowAction, string> = {
  [TRANSACTION_REVIEW_ACTION.reviewed]: 'transactionReview.toasts.markedReviewed',
  [TRANSACTION_REVIEW_ACTION.fraud]: 'transactionReview.toasts.markedFraud',
  [TRANSACTION_REVIEW_ACTION.unreviewed]: 'transactionReview.toasts.movedToUnreviewed',
};

/**
 * Row action on the review page. The row leaves its tab immediately and the tab counts
 * shift with it. `fromStatus` is the tab the row sits in, which is the status the server
 * returned it under.
 *
 * A failed write is corrected by the refetch in `onSettled`, not by restoring a cache
 * snapshot: with several rows in flight, a snapshot from before this mutation would also
 * undo the optimistic changes of the others.
 */
export const useTransactionReviewRowAction = () => {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const { addSuccessNotification, addErrorNotification } = useNotificationCenter();

  return useMutation({
    mutationFn: ({
      transactionId,
      action,
    }: {
      transactionId: string;
      fromStatus: TransactionReviewListStatus;
      action: TransactionReviewRowAction;
    }) => updateTransactionsReview({ transactionIds: [transactionId], action }),
    onMutate: async ({ transactionId, fromStatus, action }) => {
      const toStatus = TRANSACTION_REVIEW_STATUS_BY_ACTION[action];
      const listKey = reviewListKey({ status: fromStatus });
      const summaryKey = VUE_QUERY_CACHE_KEYS.transactionReviewSummary;

      await Promise.all([
        queryClient.cancelQueries({ queryKey: listKey }),
        queryClient.cancelQueries({ queryKey: summaryKey }),
      ]);

      const cachedList = queryClient.getQueryData<InfiniteData<TransactionModel[], number>>(listKey);
      const cachedSummary = queryClient.getQueryData<TransactionReviewSummary>(summaryKey);

      if (cachedList && fromStatus !== toStatus) {
        queryClient.setQueryData<InfiniteData<TransactionModel[], number>>(listKey, {
          ...cachedList,
          pages: cachedList.pages.map((page) => page.filter((tx) => tx.id !== transactionId)),
        });
      }

      if (cachedSummary) {
        const shift = ({ status }: { status: TransactionReviewListStatus }) =>
          Number(toStatus === status) - Number(fromStatus === status);
        queryClient.setQueryData<TransactionReviewSummary>(summaryKey, {
          unreviewedCount: Math.max(
            0,
            cachedSummary.unreviewedCount + shift({ status: TRANSACTION_REVIEW_STATUS.unreviewed }),
          ),
          fraudCount: Math.max(0, cachedSummary.fraudCount + shift({ status: TRANSACTION_REVIEW_STATUS.fraud })),
        });
      }
    },
    onSuccess: (_data, { action }) => {
      addSuccessNotification(t(SUCCESS_KEY_BY_ACTION[action]));
    },
    onError: (error) => {
      addErrorNotification(extractApiErrorMessage(error) || t('transactionReview.toasts.updateFailed'));
    },
    onSettled: () => invalidateAfterReviewChange({ queryClient }),
  });
};
