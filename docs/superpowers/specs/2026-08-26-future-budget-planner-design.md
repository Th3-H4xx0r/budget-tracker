# Future Budget Planner Design

## Purpose

Future Budget Planner lets a user compare expected income and spending across a chosen future date range. It is a what-if tool. It never changes balances, transaction history, bank imports, bank matching, or normal budgets.

Users create plans manually. Plans may overlap and may have the same name and dates.

## Scope

Each future plan provides the existing budget experience in an isolated workspace:

- Manual and category-based plan modes.
- Date range, category and category-group selection, budget cards, detail page, charts, archive state, and existing budget access controls.
- Plan-local income and expense entries with amount, date, currency, category or group, note, and optional recurrence.
- Projected income, expenses, net result, category and group usage, timeline, and over-limit warnings.
- Existing recurring-payment sources derived from real bank activity.

The first version does not create real transactions, alter real recurring-payment records, or copy entries between plans.

## Navigation and UI

The Planned sidebar group gains a **Planned Budgets** item directly below **Budgets**. It displays a `NEW` tag.

The list, create dialog, detail page, cards, category/group pickers, and charts reuse the existing budget UI where their semantics match. The new page uses separate routes and API data so normal budgets remain unchanged.

The create dialog accepts the same plan name, type, dates, categories or groups, and options as a normal budget. It pre-fills the current Salary Profile. Users may change the salary values for that plan before creation.

The detail page separates three inputs:

1. Salary projections.
2. Bank-derived recurring projections.
3. Plan-only future entries.

The page combines them in every total, chart, and warning.

## Salary Profile

Planned Budgets has one reusable Salary Profile per user. It stores:

- Amount and currency.
- Pay schedule: weekly, biweekly, monthly, yearly, or custom interval.
- Anchor or next-pay date.
- Income category or category group.

Creating a plan copies the profile into that plan as a salary snapshot. The plan generates every salary occurrence that falls inside its date range and includes it in projected income and the plan total.

Changing the shared profile never changes existing plans in the background. When a user opens a plan whose salary snapshot differs from the current profile, the UI asks: **“Your salary changed. Apply it to this plan?”**

- **Apply** replaces the plan's salary snapshot and regenerates its occurrences for the complete plan range.
- **Keep current plan** retains its snapshot and suppresses the prompt until the shared profile changes again.

## Plan-local entries

Every manual future entry belongs to exactly one plan. A plan-local recurrence generates occurrences only within that plan's date range. Deleting, editing, archiving, or creating a plan never changes another plan.

Entries support income and expenses. They use the existing category and category-group system, including its validation and display behavior.

## Bank-derived recurring projections

The planner automatically includes active recurring-payment sources that the application identified from real bank activity. It projects occurrences into each plan that covers the occurrence date.

The planner stores no copied transaction rows for these sources. It derives them when it loads or recalculates a plan. Therefore amount, schedule, category, and status changes to an eligible source update every affected plan automatically.

Each plan may exclude a source or override its amount, category or group, and next occurrence. An override applies only to that plan and leaves the real recurring-payment source unchanged. The source itself remains read-only in the planner.

Candidate or inactive recurring items do not affect a plan until they become active recurring-payment sources based on real bank data.

## Data model

The feature uses separate persistence from normal budgets and transactions:

- `FutureBudgetSettings`: user-owned Salary Profile and its revision.
- `FutureBudgetPlans`: user-owned plan metadata, normal-budget-like settings, salary snapshot, and the most recently dismissed Salary Profile revision.
- `FutureBudgetEntries`: one-off and recurring plan-local income or expense rules.
- `FutureBudgetRecurringOverrides`: plan-specific inclusion and override settings for bank-derived recurring sources.
- Plan sharing records or shareable integration, matching the existing budget access model.

The API derives occurrence rows for salary, plan-local recurrences, and bank-derived sources. It does not persist those derived rows. Each response identifies whether an occurrence is salary, source-linked, or plan-local and whether a plan override applies.

## APIs and calculation rules

The backend exposes list, detail, create, edit, archive, and delete operations for future plans; CRUD operations for plan-local entries; Salary Profile read and update operations; and source override operations.

The plan-calculation service receives a plan and its date range, then:

1. Expands the plan's salary snapshot into occurrences.
2. Expands plan-local recurring entries and includes plan-local one-off entries.
3. Loads eligible bank-derived recurring sources and expands them into occurrences.
4. Applies the plan's source exclusions and overrides.
5. Groups the resulting values by income, expense, category, group, date, and plan budget mode.

It returns totals, timeline points, category/group breakdowns, and warnings. It uses the same base-currency conversion and category/group rules as normal budget statistics.

## Error handling and permissions

Only users with the corresponding existing budget access may view or edit a plan. Source data remains visible only when the user already has access to the underlying recurring source.

The backend rejects invalid date ranges, non-positive amounts, invalid recurrence intervals, inaccessible categories or groups, and overrides for ineligible recurring sources. It returns an empty linked-source section when no eligible source exists.

## Testing

Backend tests cover:

- Creation of overlapping and duplicate plans.
- Salary occurrence generation for every supported schedule and date boundary.
- Salary Profile change prompts, apply behavior, and keep behavior.
- Isolation of plan-local entries across overlapping plans.
- Automatic updates from real recurring sources.
- Exclusions and overrides without mutation of the source.
- Category/group totals, income/expense/net totals, permissions, archives, and currency conversion.

Frontend tests cover navigation, the `NEW` tag, Salary Profile create/edit flow, salary-change prompt, plan create/edit forms, plan-local entry editing, source overrides, and summary/chart states.

## Acceptance criteria

- A user can create two identical or overlapping future plans manually.
- A plan contains only its own manual entries.
- Salary occurrences cover the selected plan range according to the plan's salary snapshot.
- A changed shared Salary Profile updates an existing plan only after the user accepts the prompt.
- Active real-bank recurring sources update plan projections automatically.
- Per-plan source changes do not modify the real source or another plan.
- Future-plan values never affect normal budgets, actual balances, transaction history, or bank reconciliation.
