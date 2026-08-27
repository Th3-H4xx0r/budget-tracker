import { BUDGET_STATUSES, BUDGET_TYPES, RecordId, SUBSCRIPTION_LINK_STATUS, TRANSACTION_TYPES } from '@bt/shared/types';
import { recordId } from '@common/lib/zod/custom-types';
import { Money } from '@common/types/money';
import { createController } from '@controllers/helpers/controller-factory';
import FutureBudgetEntries from '@models/future-budget-entries.model';
import FutureBudgetPlanCategories from '@models/future-budget-plan-categories.model';
import FutureBudgetPlans from '@models/future-budget-plans.model';
import FutureBudgetRecurringOverrides from '@models/future-budget-recurring-overrides.model';
import FutureBudgetSettings from '@models/future-budget-settings.model';
import Subscriptions from '@models/subscriptions.model';
import Transactions from '@models/transactions.model';
import { z } from 'zod';

const frequencyValues = ['weekly', 'biweekly', 'monthly', 'quarterly', 'semi_annual', 'annual', 'custom'] as const;
const transactionTypeValues = Object.values(TRANSACTION_TYPES) as [TRANSACTION_TYPES, ...TRANSACTION_TYPES[]];
const budgetTypeValues = Object.values(BUDGET_TYPES) as [BUDGET_TYPES, ...BUDGET_TYPES[]];
const budgetStatusValues = Object.values(BUDGET_STATUSES) as [BUDGET_STATUSES, ...BUDGET_STATUSES[]];
const dateString = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Expected a date in YYYY-MM-DD format');
const money = z.number().finite().nonnegative();

const salaryShape = {
  salaryAmount: money,
  salaryFrequency: z.enum(frequencyValues),
  salaryIntervalDays: z.number().int().positive().nullable().optional(),
  salaryAnchorDate: dateString.nullable().optional(),
  salaryCategoryId: recordId().nullable().optional(),
};
const entryShape = {
  transactionType: z.enum(transactionTypeValues),
  amount: money,
  date: dateString,
  categoryId: recordId().nullable().optional(),
  note: z.string().max(5000).nullable().optional(),
  frequency: z.enum(frequencyValues).nullable().optional(),
  intervalDays: z.number().int().positive().nullable().optional(),
};

function startOfDay(value: string): Date {
  return new Date(`${value}T00:00:00.000Z`);
}

function asDate(value: Date): string {
  return value.toISOString().slice(0, 10);
}

function addOccurrence(date: Date, frequency: string, intervalDays?: number | null): Date {
  const next = new Date(date);
  if (frequency === 'weekly') next.setUTCDate(next.getUTCDate() + 7);
  else if (frequency === 'biweekly') next.setUTCDate(next.getUTCDate() + 14);
  else if (frequency === 'quarterly') next.setUTCMonth(next.getUTCMonth() + 3);
  else if (frequency === 'semi_annual') next.setUTCMonth(next.getUTCMonth() + 6);
  else if (frequency === 'annual') next.setUTCFullYear(next.getUTCFullYear() + 1);
  else if (frequency === 'custom') next.setUTCDate(next.getUTCDate() + (intervalDays ?? 30));
  else next.setUTCMonth(next.getUTCMonth() + 1);
  return next;
}

function occurrences(input: {
  startDate: string;
  endDate: string;
  anchorDate: string | null;
  frequency: string;
  intervalDays?: number | null;
}) {
  const rangeStart = startOfDay(input.startDate);
  const rangeEnd = startOfDay(input.endDate);
  let current = startOfDay(input.anchorDate ?? input.startDate);
  if (input.frequency === 'once') {
    return current >= rangeStart && current <= rangeEnd ? [asDate(current)] : [];
  }
  while (current < rangeStart) current = addOccurrence(current, input.frequency, input.intervalDays);
  const result: string[] = [];
  while (current <= rangeEnd) {
    result.push(asDate(current));
    current = addOccurrence(current, input.frequency, input.intervalDays);
  }
  return result;
}

function serializePlan(plan: FutureBudgetPlans) {
  return plan.toJSON();
}

function amountAsNumber(amount: Money | number): number {
  return Money.isMoney(amount) ? amount.toNumber() : amount;
}

/** Only subscriptions backed by at least one active, real bank transaction are projected. */
export const realBankRecurringTransactionsInclude = () => ({
  model: Transactions,
  attributes: [],
  required: true,
  where: { isPlanned: false },
  through: {
    attributes: [],
    where: { status: SUBSCRIPTION_LINK_STATUS.active },
  },
});

async function getPlan(userId: number, id: RecordId) {
  const plan = await FutureBudgetPlans.findOne({ where: { id, userId } });
  if (!plan) throw new Error('Future budget plan not found');
  return plan;
}

async function getSettings(userId: number) {
  const [settings] = await FutureBudgetSettings.findOrCreate({
    where: { userId },
    defaults: {
      userId,
      salaryAmount: Money.zero(),
      salaryFrequency: 'monthly',
      salaryIntervalDays: null,
      salaryAnchorDate: null,
      salaryCategoryId: null,
      revision: 1,
    },
  });
  return settings;
}

export const listPlans = createController(z.object({}), async ({ user }) => {
  const plans = await FutureBudgetPlans.findAll({
    where: { userId: user.id },
    order: [
      ['startDate', 'DESC'],
      ['createdAt', 'DESC'],
    ],
  });
  return { data: plans.map(serializePlan) };
});

export const createPlan = createController(
  z.object({
    body: z
      .object({
        name: z.string().min(1).max(200).trim(),
        type: z.enum(budgetTypeValues).default(BUDGET_TYPES.manual),
        categoryIds: z.array(recordId()).optional().default([]),
        startDate: dateString,
        endDate: dateString,
        ...salaryShape,
      })
      .refine((value) => value.startDate <= value.endDate, {
        path: ['endDate'],
        message: 'End date must be on or after start date',
      })
      .refine((value) => value.type !== BUDGET_TYPES.category || value.categoryIds.length > 0, {
        path: ['categoryIds'],
        message: 'Category plans require at least one category',
      }),
  }),
  async ({ user, body }) => {
    const settings = await getSettings(user.id);
    const plan = await FutureBudgetPlans.create({
      userId: user.id,
      name: body.name,
      type: body.type,
      status: BUDGET_STATUSES.active,
      startDate: body.startDate,
      endDate: body.endDate,
      salaryAmount: Money.fromDecimal(body.salaryAmount),
      salaryFrequency: body.salaryFrequency,
      salaryIntervalDays: body.salaryIntervalDays ?? null,
      salaryAnchorDate: body.salaryAnchorDate ?? null,
      salaryCategoryId: body.salaryCategoryId ?? null,
      salaryProfileRevision: settings.revision,
      dismissedSalaryProfileRevision: null,
    });
    if (body.categoryIds.length) {
      await FutureBudgetPlanCategories.bulkCreate(
        body.categoryIds.map((categoryId) => ({ planId: plan.id, categoryId })),
      );
    }
    return { data: serializePlan(plan), statusCode: 201 };
  },
);

export const updatePlan = createController(
  z.object({
    params: z.object({ id: recordId() }),
    body: z
      .object({
        name: z.string().min(1).max(200).trim().optional(),
        status: z.enum(budgetStatusValues).optional(),
        autoAddSyncedTransactions: z.boolean().optional(),
        ...salaryShape,
      })
      .partial(),
  }),
  async ({ user, params, body }) => {
    const plan = await getPlan(user.id, params.id);
    const data = { ...body } as Record<string, unknown>;
    if (typeof data.salaryAmount === 'number') data.salaryAmount = Money.fromDecimal(data.salaryAmount);
    await plan.update(data);
    return { data: serializePlan(plan) };
  },
);

export const getSalarySettings = createController(z.object({}), async ({ user }) => ({
  data: (await getSettings(user.id)).toJSON(),
}));

export const updateSalarySettings = createController(
  z.object({ body: z.object(salaryShape) }),
  async ({ user, body }) => {
    const settings = await getSettings(user.id);
    const changed =
      settings.salaryAmount.toJSON() !== body.salaryAmount ||
      settings.salaryFrequency !== body.salaryFrequency ||
      settings.salaryIntervalDays !== (body.salaryIntervalDays ?? null) ||
      settings.salaryAnchorDate !== (body.salaryAnchorDate ?? null) ||
      settings.salaryCategoryId !== (body.salaryCategoryId ?? null);
    await settings.update({
      salaryAmount: Money.fromDecimal(body.salaryAmount),
      salaryFrequency: body.salaryFrequency,
      salaryIntervalDays: body.salaryIntervalDays ?? null,
      salaryAnchorDate: body.salaryAnchorDate ?? null,
      salaryCategoryId: body.salaryCategoryId ?? null,
      revision: changed ? settings.revision + 1 : settings.revision,
    });
    return { data: settings.toJSON() };
  },
);

export const getPlanDetails = createController(
  z.object({ params: z.object({ id: recordId() }) }),
  async ({ user, params }) => {
    const plan = await getPlan(user.id, params.id);
    const [settings, entries, categories, overrides, subscriptions] = await Promise.all([
      getSettings(user.id),
      FutureBudgetEntries.findAll({ where: { planId: plan.id }, order: [['date', 'ASC']] }),
      FutureBudgetPlanCategories.findAll({ where: { planId: plan.id } }),
      FutureBudgetRecurringOverrides.findAll({ where: { planId: plan.id } }),
      // A subscription only projects when it still has a live link to real activity.
      // Manually-created reminders have no link and are excluded by `required: true`.
      Subscriptions.findAll({
        where: { userId: user.id, isActive: true },
        include: [realBankRecurringTransactionsInclude()],
      }),
    ]);
    const categoryIds = new Set(categories.map((category) => category.categoryId));
    const overrideBySubscription = new Map(overrides.map((override) => [override.subscriptionId, override]));
    const salaryOccurrences = plan.salaryAmount.isPositive()
      ? occurrences({
          startDate: plan.startDate,
          endDate: plan.endDate,
          anchorDate: plan.salaryAnchorDate,
          frequency: plan.salaryFrequency,
          intervalDays: plan.salaryIntervalDays,
        }).map((date) => ({
          source: 'salary',
          transactionType: TRANSACTION_TYPES.income,
          amount: plan.salaryAmount,
          date,
          categoryId: plan.salaryCategoryId,
          note: 'Salary',
        }))
      : [];
    const recurringOccurrences = subscriptions.flatMap((subscription) => {
      const override = overrideBySubscription.get(subscription.id);
      if (override?.isIncluded === false || !subscription.expectedAmount) return [];
      const anchor = override?.nextOccurrenceDate ?? subscription.dueDate ?? subscription.startDate;
      return occurrences({
        startDate: plan.startDate,
        endDate: plan.endDate,
        anchorDate: anchor,
        frequency: subscription.frequency,
      }).map((date) => ({
        source: 'recurring',
        subscriptionId: subscription.id,
        name: subscription.name,
        transactionType: subscription.transactionType,
        amount: override?.amount ?? subscription.expectedAmount,
        date,
        categoryId: override?.categoryId ?? subscription.categoryId,
      }));
    });
    const manualOccurrences = entries.flatMap((entry) =>
      occurrences({
        startDate: plan.startDate,
        endDate: plan.endDate,
        anchorDate: entry.date,
        frequency: entry.frequency ?? 'once',
        intervalDays: entry.intervalDays,
      }).map((date) => ({ ...entry.toJSON(), source: 'manual', date })),
    );
    const all = [...salaryOccurrences, ...recurringOccurrences, ...manualOccurrences].filter(
      (item) => plan.type !== BUDGET_TYPES.category || (item.categoryId && categoryIds.has(item.categoryId)),
    ) as Array<{
      transactionType: TRANSACTION_TYPES;
      amount: Money | number;
      date: string;
    }>;
    const summary = all.reduce(
      (value, item) => ({
        income: value.income + (item.transactionType === TRANSACTION_TYPES.income ? amountAsNumber(item.amount) : 0),
        expense: value.expense + (item.transactionType === TRANSACTION_TYPES.expense ? amountAsNumber(item.amount) : 0),
      }),
      { income: 0, expense: 0 },
    );
    return {
      data: {
        plan: serializePlan(plan),
        categoryIds: [...categoryIds],
        entries: entries.map((entry) => entry.toJSON()),
        overrides: overrides.map((override) => override.toJSON()),
        occurrences: all.toSorted((a, b) => a.date.localeCompare(b.date)),
        summary: { ...summary, net: summary.income - summary.expense },
        salaryProfileChanged:
          settings.revision !== plan.salaryProfileRevision && settings.revision !== plan.dismissedSalaryProfileRevision,
        salarySettings: settings.toJSON(),
      },
    };
  },
);

export const applyCurrentSalary = createController(
  z.object({ params: z.object({ id: recordId() }), body: z.object({ apply: z.boolean() }) }),
  async ({ user, params, body }) => {
    const [plan, settings] = await Promise.all([getPlan(user.id, params.id), getSettings(user.id)]);
    if (body.apply)
      await plan.update({
        salaryAmount: settings.salaryAmount,
        salaryFrequency: settings.salaryFrequency,
        salaryIntervalDays: settings.salaryIntervalDays,
        salaryAnchorDate: settings.salaryAnchorDate,
        salaryCategoryId: settings.salaryCategoryId,
        salaryProfileRevision: settings.revision,
        dismissedSalaryProfileRevision: null,
      });
    else await plan.update({ dismissedSalaryProfileRevision: settings.revision });
    return { data: serializePlan(plan) };
  },
);

export const createEntry = createController(
  z.object({ params: z.object({ id: recordId() }), body: z.object(entryShape) }),
  async ({ user, params, body }) => {
    const plan = await getPlan(user.id, params.id);
    const entry = await FutureBudgetEntries.create({
      ...body,
      planId: plan.id,
      amount: Money.fromDecimal(body.amount),
      categoryId: body.categoryId ?? null,
      note: body.note ?? null,
      frequency: body.frequency ?? null,
      intervalDays: body.intervalDays ?? null,
    });
    return { data: entry.toJSON(), statusCode: 201 };
  },
);

export const deleteEntry = createController(
  z.object({ params: z.object({ id: recordId(), entryId: recordId() }) }),
  async ({ user, params }) => {
    const plan = await getPlan(user.id, params.id);
    await FutureBudgetEntries.destroy({ where: { id: params.entryId, planId: plan.id } });
    return {};
  },
);

export const updateEntry = createController(
  z.object({
    params: z.object({ id: recordId(), entryId: recordId() }),
    body: z.object(entryShape).partial(),
  }),
  async ({ user, params, body }) => {
    const plan = await getPlan(user.id, params.id);
    const entry = await FutureBudgetEntries.findOne({ where: { id: params.entryId, planId: plan.id } });
    if (!entry) throw new Error('Future budget entry not found');
    const data = { ...body } as Record<string, unknown>;
    if (typeof data.amount === 'number') data.amount = Money.fromDecimal(data.amount);
    await entry.update(data);
    return { data: entry.toJSON() };
  },
);

export const deletePlan = createController(
  z.object({ params: z.object({ id: recordId() }) }),
  async ({ user, params }) => {
    const plan = await getPlan(user.id, params.id);
    await plan.destroy();
    return {};
  },
);

export const updateRecurringOverride = createController(
  z.object({
    params: z.object({ id: recordId(), subscriptionId: recordId() }),
    body: z.object({
      isIncluded: z.boolean().optional(),
      amount: money.nullable().optional(),
      categoryId: recordId().nullable().optional(),
      nextOccurrenceDate: dateString.nullable().optional(),
    }),
  }),
  async ({ user, params, body }) => {
    const plan = await getPlan(user.id, params.id);
    const subscription = await Subscriptions.findOne({
      where: { id: params.subscriptionId, userId: user.id, isActive: true },
    });
    if (!subscription) throw new Error('Recurring payment not found');
    const [override] = await FutureBudgetRecurringOverrides.findOrCreate({
      where: { planId: plan.id, subscriptionId: subscription.id },
      defaults: {
        planId: plan.id,
        subscriptionId: subscription.id,
        isIncluded: body.isIncluded ?? true,
        amount: body.amount == null ? null : Money.fromDecimal(body.amount),
        categoryId: body.categoryId ?? null,
        nextOccurrenceDate: body.nextOccurrenceDate ?? null,
      },
    });
    if (!override.isNewRecord)
      await override.update({ ...body, amount: body.amount == null ? body.amount : Money.fromDecimal(body.amount) });
    return { data: override.toJSON() };
  },
);
