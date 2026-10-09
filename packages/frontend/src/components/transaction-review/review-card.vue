<template>
  <div class="bg-card rounded-xl border p-5">
    <DesktopOnlyTooltip :content="title" only-when-truncated>
      <p class="truncate text-lg font-semibold">{{ title }}</p>
    </DesktopOnlyTooltip>
    <p v-if="secondaryNote" class="text-muted-foreground mt-0.5 line-clamp-2 text-sm [word-break:break-word]">
      {{ secondaryNote }}
    </p>

    <p :class="cn('text-amount mt-4 text-3xl font-semibold tabular-nums', amountColorClass)">
      {{ formattedAmount }}
    </p>

    <div class="mt-4 grid gap-2.5 text-sm">
      <div class="flex min-w-0 items-center gap-2">
        <AccountLogo v-if="account" :account="account" class="size-5 shrink-0" />
        <WalletIcon v-else class="text-muted-foreground size-4 shrink-0" aria-hidden="true" />
        <span class="truncate">{{ accountName }}</span>
      </div>
      <div class="flex min-w-0 items-center gap-2">
        <CalendarClockIcon class="text-muted-foreground size-4 shrink-0" aria-hidden="true" />
        <span class="truncate">{{ formattedDateTime }}</span>
      </div>
      <div class="flex min-w-0 items-center gap-2">
        <CategoryCircle v-if="category" :category="category" class="size-5 shrink-0" />
        <TagIcon v-else class="text-muted-foreground size-4 shrink-0" aria-hidden="true" />
        <span class="truncate">{{ categoryName }}</span>
      </div>
    </div>
  </div>
</template>

<script lang="ts" setup>
import AccountLogo from '@/components/common/account-logo.vue';
import CategoryCircle from '@/components/common/category-circle.vue';
import { DesktopOnlyTooltip } from '@/components/lib/ui/tooltip';
import { usePayeeLookup } from '@/composable/data-queries/payees';
import { useDateLocale } from '@/composable/use-date-locale';
import { formatUIAmount } from '@/js/helpers';
import { cn } from '@/lib/utils';
import { useAccountsStore, useCategoriesStore } from '@/stores';
import {
  isTwoLegTransfer,
  TRANSACTION_TRANSFER_NATURE,
  TRANSACTION_TYPES,
  type TransactionModel,
} from '@bt/shared/types';
import { CalendarClockIcon, TagIcon, WalletIcon } from '@lucide/vue';
import { storeToRefs } from 'pinia';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps<{
  transaction: TransactionModel;
}>();

const { t } = useI18n();
const { format } = useDateLocale();
const { accountsRecord } = storeToRefs(useAccountsStore());
const { categoriesMap } = storeToRefs(useCategoriesStore());
const { byId: payeesById } = usePayeeLookup();

const account = computed(() => accountsRecord.value[props.transaction.accountId]);
const category = computed(() => categoriesMap.value[props.transaction.categoryId]);
const payeeName = computed(() =>
  props.transaction.payeeId ? payeesById.value.get(props.transaction.payeeId)?.name : undefined,
);
const note = computed(() => props.transaction.note?.trim() || undefined);

const categoryName = computed(() => category.value?.name ?? t('common.ui.other'));
const accountName = computed(() => account.value?.name ?? t('common.transactions.record.hiddenAccount'));

// The payee is what a user recognizes a charge by; the bank note is the fallback.
const title = computed(() => payeeName.value ?? note.value ?? categoryName.value);
// With a payee as the title, the bank note still helps place the charge.
const secondaryNote = computed(() => (payeeName.value ? note.value : undefined));

// Same transfer test as `transaction-record.vue`, coloured like the transactions table,
// so a transfer leg doesn't read as income or spending.
const isTransfer = computed(
  () =>
    isTwoLegTransfer(props.transaction.transferNature) ||
    props.transaction.transferNature === TRANSACTION_TRANSFER_NATURE.transfer_out_wallet,
);

const amountColorClass = computed(() => {
  if (isTransfer.value) return 'text-app-transfer-color';
  if (props.transaction.transactionType === TRANSACTION_TYPES.income) return 'text-app-income-color';
  return 'text-app-expense-color';
});

const formattedAmount = computed(() => {
  const { amount, transactionType, currencyCode } = props.transaction;
  const signed = transactionType === TRANSACTION_TYPES.expense ? -amount : amount;
  return formatUIAmount(signed, { currency: currencyCode });
});

const formattedDateTime = computed(() => format(props.transaction.time, 'PPp'));
</script>
