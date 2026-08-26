<script setup lang="ts">
import {
  createFutureBudgetEntry,
  deleteFutureBudgetEntry,
  loadFutureBudgetPlan,
  resolveSalaryChange,
  updateRecurringOverride,
  type FutureBudgetFrequency,
} from '@/api/future-budgets';
import Button from '@/components/lib/ui/button/Button.vue';
import CategorySelectField from '@/components/fields/category-select-field.vue';
import FutureBudgetDateField from './components/future-budget-date-field.vue';
import Input from '@/components/fields/input-field.vue';
import { useCategoriesStore } from '@/stores';
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query';
import { ArrowLeftIcon, PlusIcon, Trash2Icon } from '@lucide/vue';
import { storeToRefs } from 'pinia';
import { computed, reactive, watch } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
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
</script>

<template>
  <div v-if="isLoading" class="text-muted-foreground">Loading planned budget…</div>
  <div v-else-if="data" class="mx-auto max-w-6xl space-y-6">
    <router-link
      :to="{ name: 'dashboard.planned.future-budgets' }"
      class="text-muted-foreground hover:text-foreground inline-flex items-center gap-1 text-sm"
      ><ArrowLeftIcon class="size-4" /> Planned Budgets</router-link
    >
    <div class="flex flex-wrap justify-between gap-4">
      <div>
        <h1 class="text-2xl font-semibold">{{ data.plan.name }}</h1>
        <p class="text-muted-foreground mt-1">{{ data.plan.startDate }} – {{ data.plan.endDate }}</p>
      </div>
      <div class="grid grid-cols-3 gap-3 text-right">
        <div>
          <p class="text-muted-foreground text-xs">Income</p>
          <p class="font-semibold text-emerald-500">{{ currency(data.summary.income) }}</p>
        </div>
        <div>
          <p class="text-muted-foreground text-xs">Expenses</p>
          <p class="font-semibold text-rose-500">{{ currency(data.summary.expense) }}</p>
        </div>
        <div>
          <p class="text-muted-foreground text-xs">Net</p>
          <p class="font-semibold">{{ currency(data.summary.net) }}</p>
        </div>
      </div>
    </div>
    <section class="rounded-lg border p-5">
      <h2 class="font-semibold">Add a plan-only future transaction</h2>
      <p class="text-muted-foreground mb-4 text-sm">
        These entries stay in this plan only and never affect your real transactions.
      </p>
      <form class="grid gap-3 md:grid-cols-6" @submit.prevent="addEntry.mutate()">
        <select v-model="entry.transactionType" class="border-input bg-background h-10 rounded-md border px-3">
          <option value="expense">Expense</option>
          <option value="income">Income</option></select
        ><Input v-model.number="entry.amount" required min="0" type="number" placeholder="Amount" />
        <FutureBudgetDateField v-model="entry.date" label="Date" />
        <CategorySelectField
          :model-value="selectedCategory"
          :values="formattedCategories"
          placeholder="Category or group"
          @update:model-value="(value: any) => (entry.categoryId = value?.id ?? null)"
        /><select v-model="entry.frequency" class="border-input bg-background h-10 rounded-md border px-3">
          <option :value="null">One time</option>
          <option value="weekly">Weekly</option>
          <option value="biweekly">Biweekly</option>
          <option value="monthly">Monthly</option>
          <option value="quarterly">Quarterly</option>
          <option value="annual">Yearly</option>
          <option value="custom">Custom interval</option></select
        ><Input
          v-if="entry.frequency === 'custom'"
          v-model.number="entry.intervalDays"
          type="number"
          min="1"
          placeholder="Days"
        /><Input v-model="entry.note" placeholder="Note" /><Button type="submit"
          ><PlusIcon class="mr-2 size-4" />Add</Button
        >
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
      <div class="divide-y">
        <div
          v-for="item in data.occurrences"
          :key="`${item.source}-${item.id ?? item.subscriptionId ?? item.date}-${item.date}`"
          class="flex items-center justify-between gap-4 p-4"
        >
          <div>
            <p class="font-medium">
              {{ item.name ?? item.note ?? (item.source === 'salary' ? 'Salary' : 'Future transaction') }}
            </p>
            <p class="text-muted-foreground text-sm">
              {{ item.date }} ·
              {{ item.source === 'recurring' ? 'Bank recurring' : item.source === 'salary' ? 'Salary' : 'Plan only' }}
            </p>
          </div>
          <p :class="item.transactionType === 'income' ? 'text-emerald-500' : 'text-rose-500'">
            {{ item.transactionType === 'income' ? '+' : '-' }}{{ currency(item.amount) }}
          </p>
          <Button
            v-if="item.source === 'recurring' && item.subscriptionId"
            variant="ghost"
            size="sm"
            @click="updateRecurring.mutate({ subscriptionId: item.subscriptionId, isIncluded: false })"
            >Exclude from this plan</Button
          >
          <div v-if="item.source === 'recurring' && item.subscriptionId" class="flex items-center gap-2">
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
              class="w-44"
              :model-value="findCategory(recurringCategoryIds[item.subscriptionId || ''] ?? item.categoryId)"
              :values="formattedCategories"
              placeholder="Override category"
              @update:model-value="
                (value: any) => {
                  recurringCategoryIds[item.subscriptionId || ''] = value?.id ?? null;
                  updateRecurring.mutate({ subscriptionId: item.subscriptionId || '', categoryId: value?.id ?? null });
                }
              "
            />
            <FutureBudgetDateField
              class="w-36"
              :model-value="item.date"
              label="Next date"
              @update:model-value="
                updateRecurring.mutate({
                  subscriptionId: item.subscriptionId,
                  nextOccurrenceDate: $event,
                })
              "
            />
          </div>
        </div>
      </div>
    </section>
    <section v-if="data.entries.length" class="rounded-lg border p-5">
      <h2 class="mb-3 font-semibold">Plan-only entries</h2>
      <div v-for="item in data.entries" :key="item.id" class="flex items-center justify-between py-2">
        <span>{{ item.note || item.transactionType }} · {{ item.date }}</span
        ><Button variant="ghost" size="icon" @click="removeEntry.mutate(item.id)"><Trash2Icon class="size-4" /></Button>
      </div>
    </section>
  </div>
</template>
