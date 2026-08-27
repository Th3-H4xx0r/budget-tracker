import { makeRequest } from './common';

export interface FutureBudgetPlanResponse {
  id: string;
  userId: number;
  name: string;
  type: 'manual' | 'category';
  status: 'active' | 'archived';
  startDate: string;
  endDate: string;
  autoAddSyncedTransactions: boolean;
}

export interface FutureBudgetOccurrenceResponse {
  source: 'salary' | 'recurring' | 'manual';
  id?: string;
  subscriptionId?: string;
  name?: string;
  note?: string | null;
  transactionType: 'income' | 'expense';
  amount: number;
  date: string;
  categoryId: string | null;
}

export interface FutureBudgetPlanDetailsResponse {
  plan: FutureBudgetPlanResponse;
  categoryIds: string[];
  entries: Array<{ id: string; date: string; amount: number; note: string | null; categoryId: string | null }>;
  occurrences: FutureBudgetOccurrenceResponse[];
  summary: { income: number; expense: number; net: number };
}

interface CreateFutureBudgetPlanPayload {
  name?: string;
  type?: 'manual' | 'category';
  categoryIds?: string[];
  startDate: string;
  endDate: string;
  salaryAmount?: number;
  salaryFrequency?: string;
  salaryIntervalDays?: number | null;
  salaryAnchorDate?: string | null;
  salaryCategoryId?: string | null;
}

export async function createFutureBudgetPlan<R extends boolean | undefined = undefined>({
  raw,
  name = 'Test plan',
  type = 'manual',
  salaryAmount = 0,
  salaryFrequency = 'monthly',
  ...rest
}: CreateFutureBudgetPlanPayload & { raw?: R }) {
  return makeRequest<FutureBudgetPlanResponse, R>({
    method: 'post',
    url: '/future-budgets',
    payload: { name, type, salaryAmount, salaryFrequency, ...rest },
    raw,
  });
}

export async function getFutureBudgetPlan<R extends boolean | undefined = undefined>({
  id,
  raw,
}: {
  id: string;
  raw?: R;
}) {
  return makeRequest<FutureBudgetPlanDetailsResponse, R>({
    method: 'get',
    url: `/future-budgets/${id}`,
    raw,
  });
}

export async function updateFutureBudgetPlan<R extends boolean | undefined = undefined>({
  id,
  payload,
  raw,
}: {
  id: string;
  payload: Record<string, unknown>;
  raw?: R;
}) {
  return makeRequest<FutureBudgetPlanResponse, R>({
    method: 'put',
    url: `/future-budgets/${id}`,
    payload,
    raw,
  });
}
