<template>
  <DesktopOnlyTooltip :content="$t('common.ui.actions')">
    <span class="inline-flex">
      <ResponsiveMenu v-model:open="isMenuOpen">
        <template #trigger>
          <Button variant="ghost" size="icon-sm" class="shrink-0" :aria-label="$t('common.ui.actions')">
            <MoreVerticalIcon class="size-4" />
          </Button>
        </template>

        <template #default="{ close }">
          <Button
            v-for="item in menuItems"
            :key="item.action"
            :variant="item.isDestructive ? 'ghost-destructive' : 'ghost'"
            size="sm"
            class="w-full justify-start"
            @click="select({ action: item.action, close })"
          >
            <component :is="item.icon" class="size-4" />
            {{ item.label }}
          </Button>
        </template>
      </ResponsiveMenu>
    </span>
  </DesktopOnlyTooltip>
</template>

<script setup lang="ts">
import ResponsiveMenu from '@/components/common/responsive-menu.vue';
import { Button } from '@/components/lib/ui/button';
import { DesktopOnlyTooltip } from '@/components/lib/ui/tooltip';
import type { TransactionReviewRowAction } from '@/composable/data-queries/transaction-review';
import {
  TRANSACTION_REVIEW_ACTION,
  TRANSACTION_REVIEW_STATUS,
  type TransactionReviewListStatus,
} from '@bt/shared/types';
import { CheckIcon, MoreVerticalIcon, ShieldAlertIcon, ShieldCheckIcon, Undo2Icon } from '@lucide/vue';
import { type Component, computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps<{
  /** Tab the row is listed under; decides which moves are offered. */
  status: TransactionReviewListStatus;
}>();

const emit = defineEmits<{
  act: [{ action: TransactionReviewRowAction }];
}>();

const { t } = useI18n();
const isMenuOpen = ref(false);

interface MenuItem {
  action: TransactionReviewRowAction;
  label: string;
  icon: Component;
  isDestructive?: boolean;
}

const menuItems = computed<MenuItem[]>(() => {
  const moveToUnreviewed: MenuItem = {
    action: TRANSACTION_REVIEW_ACTION.unreviewed,
    label: t('transactionReview.actions.moveToUnreviewed'),
    icon: Undo2Icon,
  };

  if (props.status === TRANSACTION_REVIEW_STATUS.unreviewed) {
    return [
      { action: TRANSACTION_REVIEW_ACTION.reviewed, label: t('transactionReview.actions.looksGood'), icon: CheckIcon },
      {
        action: TRANSACTION_REVIEW_ACTION.fraud,
        label: t('transactionReview.actions.fraud'),
        icon: ShieldAlertIcon,
        isDestructive: true,
      },
    ];
  }

  if (props.status === TRANSACTION_REVIEW_STATUS.reviewed) {
    return [
      {
        action: TRANSACTION_REVIEW_ACTION.fraud,
        label: t('transactionReview.actions.markAsFraud'),
        icon: ShieldAlertIcon,
        isDestructive: true,
      },
      moveToUnreviewed,
    ];
  }

  return [
    {
      action: TRANSACTION_REVIEW_ACTION.reviewed,
      label: t('transactionReview.actions.notFraud'),
      icon: ShieldCheckIcon,
    },
    moveToUnreviewed,
  ];
});

const select = ({ action, close }: { action: TransactionReviewRowAction; close: () => void }) => {
  close();
  emit('act', { action });
};
</script>
