import { api } from '@/api/_api';

export type FutureBudgetFrequency =
  | 'weekly'
  | 'biweekly'
  | 'monthly'
  | 'quarterly'
  | 'semi_annual'
  | 'annual'
  | 'custom';
export type FutureBudgetPlan = {
  id: string;
  name: string;
  type: 'manual' | 'category';
  status: 'active' | 'archived';
  startDate: string;
  endDate: string;
  salaryAmount: number;
  salaryFrequency: FutureBudgetFrequency;
  salaryIntervalDays: number | null;
  salaryAnchorDate: string | null;
  salaryCategoryId: string | null;
  salaryProfileRevision: number;
  dismissedSalaryProfileRevision: number | null;
  autoAddSyncedTransactions: boolean;
};
export type CreateFutureBudgetPlan = Omit<
  FutureBudgetPlan,
  'id' | 'status' | 'salaryProfileRevision' | 'dismissedSalaryProfileRevision' | 'autoAddSyncedTransactions'
> & { categoryIds?: string[] };
export type SalarySettings = {
  salaryAmount: number;
  salaryFrequency: FutureBudgetFrequency;
  salaryIntervalDays: number | null;
  salaryAnchorDate: string | null;
  salaryCategoryId: string | null;
  revision: number;
};
export type FutureEntry = {
  id: string;
  transactionType: 'income' | 'expense';
  amount: number;
  date: string;
  categoryId: string | null;
  note: string | null;
  frequency: FutureBudgetFrequency | null;
  intervalDays: number | null;
};

export const loadFutureBudgetPlans = (): Promise<FutureBudgetPlan[]> => api.get('/future-budgets');
export const loadSalarySettings = (): Promise<SalarySettings> => api.get('/future-budgets/salary-settings');
export const updateSalarySettings = (payload: Omit<SalarySettings, 'revision'>): Promise<SalarySettings> =>
  api.put('/future-budgets/salary-settings', payload);
export const createFutureBudgetPlan = (payload: CreateFutureBudgetPlan): Promise<FutureBudgetPlan> =>
  api.post('/future-budgets', payload);
export const loadFutureBudgetPlan = (
  id: string,
): Promise<{
  plan: FutureBudgetPlan;
  entries: FutureEntry[];
  occurrences: Array<
    FutureEntry & { source: 'salary' | 'recurring' | 'manual'; name?: string; subscriptionId?: string }
  >;
  summary: { income: number; expense: number; net: number };
  salaryProfileChanged: boolean;
  salarySettings: SalarySettings;
}> => api.get(`/future-budgets/${id}`);
export const updateFutureBudgetPlan = (
  id: string,
  payload: Partial<Pick<FutureBudgetPlan, 'autoAddSyncedTransactions'>>,
): Promise<FutureBudgetPlan> => api.put(`/future-budgets/${id}`, payload);
export const resolveSalaryChange = (id: string, apply: boolean) =>
  api.post(`/future-budgets/${id}/salary-profile`, { apply });
export const createFutureBudgetEntry = (planId: string, payload: Omit<FutureEntry, 'id'>): Promise<FutureEntry> =>
  api.post(`/future-budgets/${planId}/entries`, payload);
export const deleteFutureBudgetEntry = (planId: string, entryId: string) =>
  api.delete(`/future-budgets/${planId}/entries/${entryId}`);
export const updateRecurringOverride = (
  planId: string,
  subscriptionId: string,
  payload: {
    isIncluded?: boolean;
    amount?: number | null;
    categoryId?: string | null;
    nextOccurrenceDate?: string | null;
  },
) => api.put(`/future-budgets/${planId}/recurring/${subscriptionId}`, payload);
