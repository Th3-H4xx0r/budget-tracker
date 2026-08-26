<script setup lang="ts">
import {
  createFutureBudgetPlan,
  loadFutureBudgetPlans,
  loadSalarySettings,
  updateSalarySettings,
  type FutureBudgetFrequency,
} from '@/api/future-budgets';
import Button from '@/components/lib/ui/button/Button.vue';
import CategorySelectField from '@/components/fields/category-select-field.vue';
import Input from '@/components/lib/ui/input/Input.vue';
import { ROUTES_NAMES } from '@/routes';
import { useCategoriesStore } from '@/stores';
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query';
import { PlusIcon, SparklesIcon } from '@lucide/vue';
import { storeToRefs } from 'pinia';
import { computed, reactive, ref, watch } from 'vue';

const queryClient = useQueryClient();
const { formattedCategories } = storeToRefs(useCategoriesStore());
const showCreate = ref(false);
const plansQuery = useQuery({ queryKey: ['future-budget-plans'], queryFn: loadFutureBudgetPlans });
const plans = computed(() => plansQuery.data.value ?? []);
const { data: salarySettings } = useQuery({ queryKey: ['future-budget-salary'], queryFn: loadSalarySettings });
const form = reactive({
  name: '',
  startDate: new Date().toISOString().slice(0, 10),
  endDate: new Date(new Date().setMonth(new Date().getMonth() + 1)).toISOString().slice(0, 10),
  salaryAmount: 0,
  salaryFrequency: 'monthly' as FutureBudgetFrequency,
  salaryIntervalDays: null as number | null,
  salaryAnchorDate: null as string | null,
  salaryCategoryId: null as string | null,
});
watch(
  salarySettings,
  (settings) => {
    if (settings) Object.assign(form, settings);
  },
  { immediate: true },
);
const salary = reactive({
  salaryAmount: 0,
  salaryFrequency: 'monthly' as FutureBudgetFrequency,
  salaryIntervalDays: null as number | null,
  salaryAnchorDate: null as string | null,
  salaryCategoryId: null as string | null,
});
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
watch(
  salarySettings,
  (settings) => {
    if (settings) Object.assign(salary, settings);
  },
  { immediate: true },
);
const saveSalary = useMutation({
  mutationFn: () => updateSalarySettings(salary),
  onSuccess: () => queryClient.invalidateQueries({ queryKey: ['future-budget-salary'] }),
});
const createPlan = useMutation({
  mutationFn: () => createFutureBudgetPlan({ ...form, type: 'manual' }),
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['future-budget-plans'] });
    showCreate.value = false;
    form.name = '';
  },
});
const frequencyLabel = computed(() =>
  form.salaryFrequency === 'custom' ? 'Custom days' : form.salaryFrequency.replace('_', ' '),
);
</script>

<template>
  <div class="mx-auto max-w-6xl space-y-6">
    <div class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <div class="flex items-center gap-2">
          <h1 class="text-2xl font-semibold">Planned Budgets</h1>
          <span class="bg-primary/15 text-primary rounded px-2 py-0.5 text-xs font-semibold">NEW</span>
        </div>
        <p class="text-muted-foreground mt-1 text-sm">
          Model future income and spending without changing your real finances.
        </p>
      </div>
      <Button @click="showCreate = true"><PlusIcon class="mr-2 size-4" /> New planned budget</Button>
    </div>
    <section class="rounded-lg border p-5">
      <div class="mb-4 flex items-center gap-2">
        <SparklesIcon class="text-primary size-5" />
        <div>
          <h2 class="font-semibold">Salary profile</h2>
          <p class="text-muted-foreground text-sm">
            Used as the default for new plans. Existing plans remain unchanged until you apply the update.
          </p>
        </div>
      </div>
      <div class="grid gap-3 md:grid-cols-5">
        <Input v-model.number="salary.salaryAmount" type="number" min="0" placeholder="Salary amount" /><select
          v-model="salary.salaryFrequency"
          class="border-input bg-background h-10 rounded-md border px-3"
        >
          <option value="monthly">Monthly</option>
          <option value="biweekly">Biweekly</option>
          <option value="weekly">Weekly</option>
          <option value="quarterly">Quarterly</option>
          <option value="annual">Yearly</option>
          <option value="custom">Custom interval</option></select
        ><Input v-model="salary.salaryAnchorDate" type="date" /><Input
          v-if="salary.salaryFrequency === 'custom'"
          v-model.number="salary.salaryIntervalDays"
          type="number"
          min="1"
          placeholder="Days between payments"
        /><CategorySelectField
          :model-value="findCategory(salary.salaryCategoryId)"
          :values="formattedCategories"
          placeholder="Income category/group"
          @update:model-value="(value: any) => (salary.salaryCategoryId = value?.id ?? null)"
        />
      </div>
      <Button class="mt-3" variant="outline" :disabled="saveSalary.isPending.value" @click="saveSalary.mutate()"
        >Save salary profile</Button
      >
    </section>
    <div v-if="plans.length" class="grid gap-4 md:grid-cols-2">
      <router-link
        v-for="plan in plans"
        :key="plan.id"
        :to="{ name: ROUTES_NAMES.plannedFutureBudgetDetails, params: { id: plan.id } }"
        class="hover:border-primary rounded-lg border p-5 transition"
        ><div class="flex justify-between gap-3">
          <h2 class="font-semibold">{{ plan.name }}</h2>
          <span class="text-muted-foreground text-sm">{{ plan.startDate }} – {{ plan.endDate }}</span>
        </div>
        <p class="text-muted-foreground mt-3 text-sm">
          Salary: {{ plan.salaryAmount.toLocaleString(undefined, { style: 'currency', currency: 'USD' }) }} ·
          {{ plan.salaryFrequency }}
        </p></router-link
      >
    </div>
    <div v-else class="text-muted-foreground rounded-lg border border-dashed p-12 text-center">
      Create a plan for a pay period, trip, or any future date range.
    </div>
    <div v-if="showCreate" class="fixed inset-0 z-50 grid place-items-center bg-black/60 p-4">
      <form
        class="bg-background w-full max-w-xl space-y-4 rounded-lg border p-6 shadow-xl"
        @submit.prevent="createPlan.mutate()"
      >
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold">Create planned budget</h2>
          <Button type="button" variant="ghost" @click="showCreate = false">Cancel</Button>
        </div>
        <Input v-model="form.name" required placeholder="Plan name" />
        <div class="grid grid-cols-2 gap-3">
          <label class="text-sm">From<Input v-model="form.startDate" required type="date" /></label
          ><label class="text-sm">To<Input v-model="form.endDate" required type="date" /></label>
        </div>
        <div class="border-t pt-4">
          <p class="mb-2 text-sm font-medium">Salary projection</p>
          <div class="grid gap-3 md:grid-cols-2">
            <Input v-model.number="form.salaryAmount" type="number" min="0" placeholder="Amount" /><select
              v-model="form.salaryFrequency"
              class="border-input bg-background h-10 rounded-md border px-3"
            >
              <option value="monthly">Monthly</option>
              <option value="biweekly">Biweekly</option>
              <option value="weekly">Weekly</option>
              <option value="quarterly">Quarterly</option>
              <option value="annual">Yearly</option>
              <option value="custom">{{ frequencyLabel }}</option></select
            ><Input v-model="form.salaryAnchorDate" type="date" /><Input
              v-if="form.salaryFrequency === 'custom'"
              v-model.number="form.salaryIntervalDays"
              type="number"
              min="1"
              placeholder="Days between payments"
            /><CategorySelectField
              :model-value="findCategory(form.salaryCategoryId)"
              :values="formattedCategories"
              placeholder="Income category/group"
              @update:model-value="(value: any) => (form.salaryCategoryId = value?.id ?? null)"
            />
          </div>
        </div>
        <Button class="w-full" type="submit" :disabled="createPlan.isPending.value">Create plan</Button>
      </form>
    </div>
  </div>
</template>
