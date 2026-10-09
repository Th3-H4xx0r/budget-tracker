<template>
  <ResponsiveDialog
    v-model:open="isOpen"
    sr-only-header
    custom-close
    no-internal-scroll
    dialog-content-class="gap-4"
    drawer-content-class="flex flex-col gap-4 pt-2"
  >
    <template #title>{{ $t('transactionReview.stack.title') }}</template>
    <template #description>{{ $t('transactionReview.stack.description') }}</template>

    <div class="flex items-center gap-1">
      <span class="text-muted-foreground text-sm tabular-nums" aria-live="polite">
        <template v-if="current">
          {{ $t('transactionReview.stack.progress', { n: position, total }) }}
        </template>
      </span>

      <Button variant="ghost" size="sm" class="ml-auto" :disabled="!canUndo" @click="handleUndo">
        <Undo2Icon class="size-4" />
        {{ $t('transactionReview.stack.undo') }}
        <kbd
          v-if="showShortcuts"
          aria-hidden="true"
          class="rounded bg-current/15 px-1 font-sans text-[10px] leading-4 font-medium"
        >
          {{ undoShortcutLabel }}
        </kbd>
      </Button>
      <DesktopOnlyTooltip :content="$t('common.ui.close')">
        <Button variant="ghost" size="icon-sm" :aria-label="$t('common.ui.close')" @click="isOpen = false">
          <XIcon class="size-4" />
        </Button>
      </DesktopOnlyTooltip>
    </div>

    <template v-if="current">
      <ReviewCard :key="current.id" :transaction="current" />
      <ReviewStackActions ref="actionsRef" :show-shortcuts="showShortcuts" @act="handleAct" />
    </template>

    <div v-else-if="isFinished" class="flex flex-col items-center gap-4 py-6 text-center">
      <div class="bg-success-text/15 text-success-text flex size-12 items-center justify-center rounded-full">
        <CircleCheckIcon class="size-6" />
      </div>
      <div>
        <p class="text-lg font-semibold">{{ $t('transactionReview.stack.allCaughtUp') }}</p>
        <p v-if="deferredCount > 0" class="text-muted-foreground mt-1 text-sm">
          {{ $t('transactionReview.stack.savedForLater', { count: deferredCount }, deferredCount) }}
        </p>
      </div>
      <Button class="w-full" @click="isOpen = false">{{ $t('common.actions.done') }}</Button>
    </div>

    <div v-else-if="loadError && !isFetching" class="flex flex-col items-center gap-3 py-8 text-center">
      <p class="text-muted-foreground text-sm">{{ $t('transactionReview.loadFailed') }}</p>
      <Button variant="outline" size="sm" @click="session.retry()">
        <RotateCwIcon class="size-4" />
        {{ $t('common.actions.retry') }}
      </Button>
    </div>

    <template v-else>
      <div class="bg-card rounded-xl border p-5" aria-hidden="true">
        <div class="bg-muted h-6 w-40 animate-pulse rounded" />
        <div class="bg-muted mt-5 h-9 w-32 animate-pulse rounded" />
        <div class="mt-5 grid gap-3">
          <div class="bg-muted h-4 w-36 animate-pulse rounded" />
          <div class="bg-muted h-4 w-44 animate-pulse rounded" />
          <div class="bg-muted h-4 w-28 animate-pulse rounded" />
        </div>
      </div>
      <div class="grid grid-cols-3 gap-2" aria-hidden="true">
        <div v-for="index in 3" :key="index" class="bg-muted h-11 animate-pulse rounded-md" />
      </div>
    </template>
  </ResponsiveDialog>
</template>

<script lang="ts" setup>
import { loadTransactionsForReview, updateTransactionsReview } from '@/api/transaction-review';
import { isMacPlatform } from '@/common/utils/platform';
import ResponsiveDialog from '@/components/common/responsive-dialog.vue';
import { Button } from '@/components/lib/ui/button';
import { DesktopOnlyTooltip } from '@/components/lib/ui/tooltip';
import { useNotificationCenter } from '@/components/notification-center';
import {
  invalidateAfterReviewChange,
  invalidateTransactionReviewSummary,
  useTransactionReviewSummary,
} from '@/composable/data-queries/transaction-review';
import { CUSTOM_BREAKPOINTS, useWindowBreakpoints } from '@/composable/window-breakpoints';
import { extractApiErrorMessage } from '@/js/errors';
import { TRANSACTION_REVIEW_STATUS } from '@bt/shared/types';
import { CircleCheckIcon, RotateCwIcon, Undo2Icon, XIcon } from '@lucide/vue';
import { useQueryClient } from '@tanstack/vue-query';
import { useEventListener } from '@vueuse/core';
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import ReviewCard from './review-card.vue';
import { type ReviewShortcutTarget, resolveReviewShortcut } from './review-shortcuts';
import ReviewStackActions from './review-stack-actions.vue';
import { type ReviewDecision, useReviewSession } from './use-review-session';

const isOpen = defineModel<boolean>('open', { required: true });

const { t } = useI18n();
const queryClient = useQueryClient();
const { addErrorNotification } = useNotificationCenter();
const isMobile = useWindowBreakpoints(CUSTOM_BREAKPOINTS.uiMobile);
const { unreviewedCount } = useTransactionReviewSummary();

const session = useReviewSession({
  fetchPage: ({ offset, limit }) =>
    loadTransactionsForReview({ status: TRANSACTION_REVIEW_STATUS.unreviewed, offset, limit }),
  submitAction: updateTransactionsReview,
  // Keeps the sidebar badge and dashboard count in step while the stack is open; the
  // tabs and transaction lists refresh once, when the stack closes.
  onSubmitSuccess: () => invalidateTransactionReviewSummary({ queryClient }),
  onSubmitError: ({ error, kind }) => {
    const fallbackKey =
      kind === 'undo' ? 'transactionReview.toasts.undoFailed' : 'transactionReview.toasts.actionFailed';
    addErrorNotification(extractApiErrorMessage(error) || t(fallbackKey));
  },
  onLoadMoreError: ({ error }) => {
    addErrorNotification(extractApiErrorMessage(error) || t('transactionReview.toasts.loadMoreFailed'));
  },
});

const { current, position, total, deferredCount, canUndo, isFinished, isFetching, loadError } = session;

const actionsRef = ref<InstanceType<typeof ReviewStackActions> | null>(null);
const showShortcuts = computed(() => !isMobile.value);
const undoShortcutLabel = isMacPlatform() ? '⌘Z' : 'Ctrl+Z';

let hasChanges = false;

// Review status shows in every transaction list (the fraud chip) and in the review tabs.
// Waiting for queued writes means the refetch sees their final state.
const refreshAfterChanges = () => {
  if (!hasChanges) return;
  hasChanges = false;
  void session.whenSettled().then(() => invalidateAfterReviewChange({ queryClient }));
};

const handleAct = ({ action }: { action: ReviewDecision }) => {
  if (!current.value) return;
  hasChanges = true;
  session.act({ action });
  // A mouse click leaves focus on the clicked button; Enter should keep meaning "Looks good".
  actionsRef.value?.focusPrimary();
};

const handleUndo = () => {
  if (!canUndo.value) return;
  hasChanges = true;
  session.undo();
  actionsRef.value?.focusPrimary();
};

watch(
  isOpen,
  (open) => {
    if (open) {
      hasChanges = false;
      // An unknown count (summary still loading or failed) is left out, and the progress
      // total falls back to the cards loaded so far, rather than a made-up 0.
      void session.start({ total: unreviewedCount.value ?? undefined });
      return;
    }
    refreshAfterChanges();
  },
  { immediate: true },
);

// Navigating away while the stack is open unmounts it without a close event.
onBeforeUnmount(refreshAfterChanges);

const getShortcutTarget = ({ target }: { target: EventTarget | null }): ReviewShortcutTarget => {
  if (!(target instanceof HTMLElement)) return 'other';
  if (target.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)) return 'editable';
  if (target.closest('button, a, [role="button"]')) return 'interactive';
  return 'other';
};

useEventListener(document, 'keydown', (event: KeyboardEvent) => {
  if (!isOpen.value || event.defaultPrevented) return;

  const shortcut = resolveReviewShortcut({
    key: event.key,
    repeat: event.repeat,
    metaKey: event.metaKey,
    ctrlKey: event.ctrlKey,
    altKey: event.altKey,
    shiftKey: event.shiftKey,
    target: getShortcutTarget({ target: event.target }),
    hasCard: !!current.value,
  });
  if (!shortcut) return;
  // Swallowing a held key applies everywhere, since a focused button would otherwise
  // click on every auto-repeat; the shortcuts themselves are desktop only.
  if (shortcut.kind !== 'swallow' && !showShortcuts.value) return;

  event.preventDefault();
  if (shortcut.kind === 'undo') handleUndo();
  if (shortcut.kind === 'act') handleAct({ action: shortcut.action });
});
</script>
