<script setup lang="ts">
import {
  createFutureBudgetEntry,
  deleteFutureBudgetEntry,
  deleteFutureBudgetPlan,
  loadFutureBudgetPlan,
  resolveSalaryChange,
  updateFutureBudgetEntry,
  updateFutureBudgetPlan,
  updateRecurringOverride,
  type FutureBudgetFrequency,
} from '@/api/future-budgets';
import Button from '@/components/lib/ui/button/Button.vue';
import ActionButton from '@/components/lib/ui/action-button/action-button.vue';
import { Switch } from '@/components/lib/ui/switch';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/lib/ui/table';
import CategorySelectField from '@/components/fields/category-select-field.vue';
import FutureBudgetDateField from './components/future-budget-date-field.vue';
import Input from '@/components/fields/input-field.vue';
import ResponsiveDialog from '@/components/common/responsive-dialog.vue';
import ResponsiveAlertDialog from '@/components/common/responsive-alert-dialog.vue';
import SortHeaderButton from '@/pages/settings/subpages/payees/components/sort-header-button.vue';
import { DesktopOnlyTooltip } from '@/components/lib/ui/tooltip';
import { useNotificationCenter } from '@/components/notification-center';
import { useCategoriesStore } from '@/stores';
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query';
import {
  ArchiveIcon,
  ArchiveRestoreIcon,
  ArrowLeftIcon,
  CalendarClockIcon,
  PencilIcon,
  PlusIcon,
  Trash2Icon,
} from '@lucide/vue';
import { storeToRefs } from 'pinia';
import { computed, reactive, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';

type OccurrenceSortKey = 'name' | 'date' | 'source' | 'amount';

const route = useRoute();
const router = useRouter();
const { addSuccessNotification } = useNotificationCenter();
const { formattedCategories } = storeToRefs(useCategoriesStore());
const planId = computed(() => String(route.params.id));
const queryClient = useQueryClient();
const { data, isLoading } = useQuery({
  queryKey: ['future-budget-plan', planId],
  queryFn: () => loadFutureBudgetPlan(planId.value),
});
const entry = reactive({
  transactionType: 'expense' as 'income' | 'expense',
  amount: 0,
  date: new Date().toISOString().slice(0, 10),
  categoryId: null as string | null,
  note: null as string | null,
  frequency: null as FutureBudgetFrequency | null,
  intervalDays: null as number | null,
});
const selectedCategory = computed(() => {
  const find = (categories: typeof formattedCategories.value): (typeof formattedCategories.value)[0] | null => {
    for (const category of categories) {
      if (category.id === entry.categoryId) return category;
      const found = category.subCategories?.length ? find(category.subCategories) : null;
      if (found) return found;
    }
    return null;
  };
  return find(formattedCategories.value);
});
const recurringCategoryIds = reactive<Record<string, string | null>>({});
const findCategory = (id: string | null) => {
  const find = (categories: typeof formattedCategories.value): (typeof formattedCategories.value)[0] | null => {
    for (const category of categories) {
      if (category.id === id) return category;
      const found = category.subCategories?.length ? find(category.subCategories) : null;
      if (found) return found;
    }
    return null;
  };
  return find(formattedCategories.value);
};
const refresh = () => queryClient.invalidateQueries({ queryKey: ['future-budget-plan', planId] });
const addEntry = useMutation({ mutationFn: () => createFutureBudgetEntry(planId.value, entry), onSuccess: refresh });
const removeEntry = useMutation({
  mutationFn: (id: string) => deleteFutureBudgetEntry(planId.value, id),
  onSuccess: refresh,
});
const updatePlanSettings = useMutation({
  mutationFn: (payload: { autoAddSyncedTransactions: boolean }) => updateFutureBudgetPlan(planId.value, payload),
  onSuccess: refresh,
});
const isEditPlanOpen = ref(false);
const planNameDraft = ref('');
const renamePlan = useMutation({
  mutationFn: () => updateFutureBudgetPlan(planId.value, { name: planNameDraft.value }),
  onSuccess: () => {
    refresh();
    isEditPlanOpen.value = false;
    addSuccessNotification('Plan updated');
  },
});
const openEditPlan = () => {
  planNameDraft.value = data.value?.plan.name ?? '';
  isEditPlanOpen.value = true;
};
const toggleArchivePlan = async () => {
  const nextStatus = data.value?.plan.status === 'archived' ? 'active' : 'archived';
  await updateFutureBudgetPlan(planId.value, { status: nextStatus });
  await refresh();
};
const isDeletePlanOpen = ref(false);
const deletePlan = useMutation({
  mutationFn: () => deleteFutureBudgetPlan(planId.value),
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['future-budget-plans'] });
    addSuccessNotification('Plan deleted');
    router.push({ name: 'dashboard.planned.future-budgets' });
  },
});
const editingEntryId = ref<string | null>(null);
const entryDraft = reactive({
  transactionType: 'expense' as 'income' | 'expense',
  amount: 0,
  date: new Date().toISOString().slice(0, 10),
  categoryId: null as string | null,
  note: null as string | null,
});
const selectedEntryDraftCategory = computed(() => findCategory(entryDraft.categoryId));
const openEditEntry = (item: {
  id?: string;
  transactionType: 'income' | 'expense';
  amount: number;
  date: string;
  categoryId: string | null;
  note?: string | null;
}) => {
  if (!item.id) return;
  editingEntryId.value = item.id;
  entryDraft.transactionType = item.transactionType;
  entryDraft.amount = item.amount;
  entryDraft.date = item.date;
  entryDraft.categoryId = item.categoryId;
  entryDraft.note = item.note ?? null;
};
const editEntry = useMutation({
  mutationFn: () => updateFutureBudgetEntry(planId.value, editingEntryId.value as string, { ...entryDraft }),
  onSuccess: () => {
    refresh();
    editingEntryId.value = null;
    addSuccessNotification('Entry updated');
  },
});
const resolveSalary = useMutation({
  mutationFn: (apply: boolean) => resolveSalaryChange(planId.value, apply),
  onSuccess: refresh,
});
const updateRecurring = useMutation({
  mutationFn: ({
    subscriptionId,
    ...payload
  }: {
    subscriptionId: string;
    isIncluded?: boolean;
    amount?: number;
    categoryId?: string | null;
    nextOccurrenceDate?: string;
  }) => updateRecurringOverride(planId.value, subscriptionId, payload),
  onSuccess: refresh,
});
watch(
  () => data.value?.salaryProfileChanged,
  (changed) => {
    if (changed && window.confirm('Your salary profile has changed. Apply the new salary to this plan?'))
      resolveSalary.mutate(true);
    else if (changed) resolveSalary.mutate(false);
  },
  { immediate: true },
);
const currency = (amount: number) => amount.toLocaleString(undefined, { style: 'currency', currency: 'USD' });

const sourceLabel = (source: 'salary' | 'recurring' | 'manual') =>
  source === 'recurring' ? 'Bank recurring' : source === 'salary' ? 'Salary' : 'Plan only';
const occurrenceName = (item: { name?: string; note?: string | null; source: 'salary' | 'recurring' | 'manual' }) =>
  item.name ?? item.note ?? (item.source === 'salary' ? 'Salary' : 'Future transaction');
const signedAmount = (item: { amount: number; transactionType: 'income' | 'expense' }) =>
  item.transactionType === 'income' ? item.amount : -item.amount;

const sortKey = ref<OccurrenceSortKey>('date');
const sortDir = ref<'asc' | 'desc'>('asc');
const setSort = (key: OccurrenceSortKey) => {
  if (sortKey.value === key) {
    sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc';
  } else {
    sortKey.value = key;
    sortDir.value = key === 'amount' ? 'desc' : 'asc';
  }
};
const sortedOccurrences = computed(() => {
  const occurrences = data.value?.occurrences ?? [];
  const dir = sortDir.value === 'asc' ? 1 : -1;
  return [...occurrences].sort((a, b) => {
    switch (sortKey.value) {
      case 'name':
        return occurrenceName(a).localeCompare(occurrenceName(b)) * dir;
      case 'source':
        return sourceLabel(a.source).localeCompare(sourceLabel(b.source)) * dir;
      case 'amount':
        return (signedAmount(a) - signedAmount(b)) * dir;
      case 'date':
      default:
        return a.date.localeCompare(b.date) * dir;
    }
  });
});
</script>

<template>
  <div v-if="isLoading" class="text-muted-foreground">Loading planned budget…</div>
  <div v-else-if="data" class="mx-auto max-w-6xl space-y-6">
    <router-link
      :to="{ name: 'dashboard.planned.future-budgets' }"
      class="text-muted-foreground hover:text-foreground inline-flex items-center gap-1 text-sm"
      ><ArrowLeftIcon class="size-4" /> Planned Budgets</router-link
    >
    <div class="flex flex-wrap items-start justify-between gap-4">
      <div class="flex items-center gap-4">
        <div class="bg-muted flex size-12 shrink-0 items-center justify-center rounded-xl">
          <CalendarClockIcon class="text-muted-foreground size-6" />
        </div>
        <div>
          <div class="flex flex-wrap items-center gap-3">
            <h1 class="text-2xl font-semibold">{{ data.plan.name }}</h1>
            <span
              v-if="data.plan.status === 'archived'"
              class="bg-muted text-muted-foreground inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium"
            >
              <ArchiveIcon class="size-3" />
              Archived
            </span>
          </div>
          <p class="text-muted-foreground mt-1">{{ data.plan.startDate }} – {{ data.plan.endDate }}</p>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <ActionButton
          :action="toggleArchivePlan"
          :label="data.plan.status === 'archived' ? 'Unarchive' : 'Archive'"
          :icon="data.plan.status === 'archived' ? ArchiveRestoreIcon : ArchiveIcon"
          size="sm"
        />
        <Button variant="outline" size="sm" @click="openEditPlan"><PencilIcon class="size-4" />Edit</Button>
        <DesktopOnlyTooltip content="Delete plan">
          <Button
            variant="outline"
            size="sm"
            class="text-destructive-text hover:bg-destructive-text/10"
            @click="isDeletePlanOpen = true"
          >
            <Trash2Icon class="size-4" />
          </Button>
        </DesktopOnlyTooltip>
        <ResponsiveAlertDialog
          v-model:open="isDeletePlanOpen"
          confirm-label="Delete"
          confirm-variant="destructive"
          :confirm-disabled="deletePlan.isPending.value"
          @confirm="deletePlan.mutate()"
        >
          <template #title>Delete plan?</template>
          <template #description>This will permanently delete this planned budget and its entries.</template>
        </ResponsiveAlertDialog>
      </div>
    </div>

    <ResponsiveDialog v-model:open="isEditPlanOpen">
      <template #title>Edit plan</template>
      <div class="grid gap-4">
        <Input v-model="planNameDraft" placeholder="Plan name" :disabled="renamePlan.isPending.value" />
        <Button :disabled="renamePlan.isPending.value" @click="renamePlan.mutate()">
          {{ renamePlan.isPending.value ? 'Saving…' : 'Save changes' }}
        </Button>
      </div>
    </ResponsiveDialog>

    <div class="grid grid-cols-3 gap-3 text-right">
      <div>
        <p class="text-muted-foreground text-xs">Income</p>
        <p class="text-app-income-color font-semibold">{{ currency(data.summary.income) }}</p>
      </div>
      <div>
        <p class="text-muted-foreground text-xs">Expenses</p>
        <p class="text-app-expense-color font-semibold">{{ currency(data.summary.expense) }}</p>
      </div>
      <div>
        <p class="text-muted-foreground text-xs">Net</p>
        <p class="font-semibold">{{ currency(data.summary.net) }}</p>
      </div>
    </div>
    <section class="flex items-center justify-between gap-4 rounded-lg border p-5">
      <div>
        <h2 class="font-semibold">Auto-add synced transactions</h2>
        <p class="text-muted-foreground mt-1 text-sm">
          Automatically add real transactions to this plan when they sync and fall within
          {{ data.plan.startDate }}–{{ data.plan.endDate }}.
        </p>
      </div>
      <Switch
        :model-value="data.plan.autoAddSyncedTransactions"
        :disabled="updatePlanSettings.isPending.value"
        @update:model-value="(value: boolean) => updatePlanSettings.mutate({ autoAddSyncedTransactions: value })"
      />
    </section>
    <section class="rounded-lg border p-5">
      <h2 class="font-semibold">Add a plan-only future transaction</h2>
      <p class="text-muted-foreground mb-4 text-sm">
        These entries stay in this plan only and never affect your real transactions.
      </p>
      <form class="space-y-3" @submit.prevent="addEntry.mutate()">
        <div class="flex flex-wrap gap-3">
          <select
            v-model="entry.transactionType"
            class="border-input bg-background h-10 min-w-36 flex-1 rounded-md border px-3"
          >
            <option value="expense">Expense</option>
            <option value="income">Income</option>
          </select>
          <Input
            v-model.number="entry.amount"
            required
            min="0"
            type="number"
            placeholder="Amount"
            class="min-w-36 flex-1"
          />
          <FutureBudgetDateField v-model="entry.date" class="min-w-36 flex-1" />
          <CategorySelectField
            :model-value="selectedCategory"
            :values="formattedCategories"
            placeholder="Category or group"
            class="min-w-36 flex-1"
            @update:model-value="(value: any) => (entry.categoryId = value?.id ?? null)"
          />
          <select
            v-model="entry.frequency"
            class="border-input bg-background h-10 min-w-36 flex-1 rounded-md border px-3"
          >
            <option :value="null">One time</option>
            <option value="weekly">Weekly</option>
            <option value="biweekly">Biweekly</option>
            <option value="monthly">Monthly</option>
            <option value="quarterly">Quarterly</option>
            <option value="annual">Yearly</option>
            <option value="custom">Custom interval</option>
          </select>
          <Input
            v-if="entry.frequency === 'custom'"
            v-model.number="entry.intervalDays"
            type="number"
            min="1"
            placeholder="Days"
            class="min-w-24 flex-1"
          />
          <Input v-model="entry.note" placeholder="Note" class="min-w-36 flex-1" />
        </div>
        <div class="flex justify-end">
          <Button type="submit"><PlusIcon class="size-4" />Add</Button>
        </div>
      </form>
    </section>
    <section class="rounded-lg border">
      <div class="border-b p-5">
        <h2 class="font-semibold">Projected timeline</h2>
        <p class="text-muted-foreground text-sm">
          Salary and active bank-derived recurring payments update automatically. Manual entries are isolated to this
          plan.
        </p>
      </div>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead
              ><SortHeaderButton label="Name" :active="sortKey === 'name'" :dir="sortDir" @click="setSort('name')"
            /></TableHead>
            <TableHead
              ><SortHeaderButton label="Date" :active="sortKey === 'date'" :dir="sortDir" @click="setSort('date')"
            /></TableHead>
            <TableHead
              ><SortHeaderButton
                label="Source"
                :active="sortKey === 'source'"
                :dir="sortDir"
                @click="setSort('source')"
            /></TableHead>
            <TableHead class="text-right"
              ><SortHeaderButton
                label="Amount"
                align="right"
                :active="sortKey === 'amount'"
                :dir="sortDir"
                @click="setSort('amount')"
            /></TableHead>
            <TableHead>Actions</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow
            v-for="item in sortedOccurrences"
            :key="`${item.source}-${item.id ?? item.subscriptionId ?? item.date}-${item.date}`"
          >
            <TableCell class="font-medium">{{ occurrenceName(item) }}</TableCell>
            <TableCell class="text-muted-foreground">{{ item.date }}</TableCell>
            <TableCell class="text-muted-foreground">{{ sourceLabel(item.source) }}</TableCell>
            <TableCell
              class="text-right"
              :class="item.transactionType === 'income' ? 'text-app-income-color' : 'text-app-expense-color'"
            >
              {{ item.transactionType === 'income' ? '+' : '-' }}{{ currency(item.amount) }}
            </TableCell>
            <TableCell>
              <div v-if="item.source === 'recurring' && item.subscriptionId" class="flex flex-wrap items-center gap-2">
                <Input
                  class="w-24"
                  type="number"
                  min="0"
                  :model-value="item.amount"
                  aria-label="Override projected amount"
                  @change="
                    updateRecurring.mutate({
                      subscriptionId: item.subscriptionId,
                      amount: Number(($event.target as HTMLInputElement).value),
                    })
                  "
                />
                <CategorySelectField
                  class="w-40"
                  :model-value="findCategory(recurringCategoryIds[item.subscriptionId || ''] ?? item.categoryId)"
                  :values="formattedCategories"
                  placeholder="Override category"
                  @update:model-value="
                    (value: any) => {
                      recurringCategoryIds[item.subscriptionId || ''] = value?.id ?? null;
                      updateRecurring.mutate({
                        subscriptionId: item.subscriptionId || '',
                        categoryId: value?.id ?? null,
                      });
                    }
                  "
                />
                <FutureBudgetDateField
                  class="w-32"
                  :model-value="item.date"
                  label="Next date"
                  @update:model-value="
                    updateRecurring.mutate({
                      subscriptionId: item.subscriptionId,
                      nextOccurrenceDate: $event,
                    })
                  "
                />
                <DesktopOnlyTooltip content="Exclude from this plan">
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    @click="updateRecurring.mutate({ subscriptionId: item.subscriptionId, isIncluded: false })"
                    ><Trash2Icon class="size-4"
                  /></Button>
                </DesktopOnlyTooltip>
              </div>
              <div v-else-if="item.source === 'manual' && item.id" class="flex items-center gap-2">
                <DesktopOnlyTooltip content="Edit">
                  <Button variant="ghost" size="icon-sm" @click="openEditEntry(item)"
                    ><PencilIcon class="size-4"
                  /></Button>
                </DesktopOnlyTooltip>
                <DesktopOnlyTooltip content="Delete">
                  <Button variant="ghost-destructive" size="icon-sm" @click="removeEntry.mutate(item.id!)"
                    ><Trash2Icon class="size-4"
                  /></Button>
                </DesktopOnlyTooltip>
              </div>
            </TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </section>

    <ResponsiveDialog
      :open="editingEntryId !== null"
      @update:open="(value: boolean) => !value && (editingEntryId = null)"
    >
      <template #title>Edit entry</template>
      <div class="grid gap-4">
        <div class="flex flex-wrap gap-3">
          <select
            v-model="entryDraft.transactionType"
            class="border-input bg-background h-10 min-w-36 flex-1 rounded-md border px-3"
          >
            <option value="expense">Expense</option>
            <option value="income">Income</option>
          </select>
          <Input
            v-model.number="entryDraft.amount"
            type="number"
            min="0"
            placeholder="Amount"
            class="min-w-36 flex-1"
          />
        </div>
        <div class="flex flex-wrap gap-3">
          <FutureBudgetDateField v-model="entryDraft.date" class="min-w-36 flex-1" />
          <CategorySelectField
            :model-value="selectedEntryDraftCategory"
            :values="formattedCategories"
            placeholder="Category or group"
            class="min-w-36 flex-1"
            @update:model-value="(value: any) => (entryDraft.categoryId = value?.id ?? null)"
          />
        </div>
        <Input v-model="entryDraft.note" placeholder="Note" />
        <Button :disabled="editEntry.isPending.value" @click="editEntry.mutate()">
          {{ editEntry.isPending.value ? 'Saving…' : 'Save changes' }}
        </Button>
      </div>
    </ResponsiveDialog>
  </div>
</template>
