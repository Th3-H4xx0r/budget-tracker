# Future Budget Planner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add isolated, manually created Future Budget Plans with salary and real-recurring-payment projections.

**Architecture:** New future-budget tables and services keep plans separate from normal budgets and transactions. A calculation service expands salary, plan-local recurring rules, and active real-bank recurring sources into transient occurrences. Vue pages reuse the normal budget visual language on separate routes.

**Tech Stack:** Express, Sequelize, PostgreSQL, Vue 3, Vue Query, Zod, Jest, and vue-i18n.

**Spec:** `docs/superpowers/specs/2026-08-26-future-budget-planner-design.md`

## Global Constraints

- Future-plan values never affect real balances, history, imports, reconciliation, or normal budgets.
- Plans are manually created and may overlap or duplicate each other.
- Plan-local entries, including recurrences, belong to one plan only.
- Only active recurring sources derived from real bank activity project automatically.
- Salary changes affect an existing plan only after the user accepts the plan-level prompt.

---

### Task 1: Persist future-plan configuration

**Files:**

- Create: `packages/backend/src/migrations/20260826000000-create-future-budget-planner.js`
- Create: `packages/backend/src/models/future-budget-settings.model.ts`
- Create: `packages/backend/src/models/future-budget-plans.model.ts`
- Create: `packages/backend/src/models/future-budget-entries.model.ts`
- Create: `packages/backend/src/models/future-budget-recurring-overrides.model.ts`
- Modify: `packages/backend/src/models/index.ts`
- Modify: `packages/shared/src/types/*`
- Test: `packages/backend/src/services/future-budgets/future-budgets.e2e.ts`

**Interfaces:** Produces user-owned settings, plan, entry, and source-override models plus `FutureBudgetPlan`, `FutureBudgetEntry`, `SalaryProfile`, and `FutureBudgetStats` contracts.

- [ ] Write tests that create two plans with the same dates and verify their entries remain isolated.
- [ ] Run `npm -w packages/backend run test:e2e -- future-budgets`; expect missing model/table failures.
- [ ] Create the four tables. Store salary snapshot fields and revision state on a plan. Store one-off and recurrence rule fields on entries. Store include/exclude and optional amount/category/next-date replacements on source overrides.
- [ ] Register models and shared types.
- [ ] Re-run the focused suite; expect PASS.
- [ ] Commit with `feat: add future budget planner persistence`.

### Task 2: Calculate isolated projections and expose APIs

**Files:**

- Create: `packages/backend/src/services/future-budgets/calculate-plan.ts`
- Create: `packages/backend/src/services/future-budgets/expand-occurrences.ts`
- Create: `packages/backend/src/services/future-budgets/plan-crud.ts`
- Create: `packages/backend/src/controllers/future-budgets/*`
- Create: `packages/backend/src/routes/future-budgets.route.ts`
- Modify: `packages/backend/src/routes/index.ts`
- Test: `packages/backend/src/services/future-budgets/*.e2e.ts`

**Interfaces:** `calculateFutureBudgetPlan({ planId, userId })` returns generated occurrences, totals, category/group breakdowns, warnings, and salary-update status.

- [ ] Write failing tests for monthly and biweekly salary dates, plan-local isolation, active-source projection, exclusion, override, and source edits changing the next calculation without changing plan rows.
- [ ] Implement occurrence expansion with inclusive plan dates. Expand plan salary, plan entries, and active recurring sources; apply source overrides last; group results by income, expense, category, group, and date.
- [ ] Add `/future-budgets` CRUD, plan stats, plan-entry CRUD, Salary Profile read/update, linked-source, override, apply-salary-profile, and dismiss-salary-profile routes.
- [ ] Reuse existing category/group permissions and base-currency conversion helpers. Reject invalid ranges, non-positive values, invalid recurrences, inaccessible categories/groups, and ineligible source overrides.
- [ ] Run the focused suite; expect PASS. Commit with `feat: calculate future budget projections`.

### Task 3: Add client routes, navigation, localization, and APIs

**Files:**

- Modify: `packages/frontend/src/routes/constants.ts`
- Modify: `packages/frontend/src/routes/index.ts`
- Modify: `packages/frontend/src/components/sidebar/navigation-links.vue`
- Create: `packages/frontend/src/api/future-budgets.ts`
- Modify: `packages/frontend/src/common/const/vue-query.ts`
- Modify: `packages/frontend/src/i18n/locales/chunks/en/pages/planned.json`
- Test: `packages/frontend/src/components/sidebar/navigation-links.spec.ts`

**Interfaces:** Adds `ROUTES_NAMES.plannedFutureBudgets`, `ROUTES_NAMES.plannedFutureBudgetDetails`, typed APIs, and query keys for settings, plans, and stats.

- [ ] Write a failing sidebar test for the Planned Budgets link and `NEW` tag.
- [ ] Add `/planned/planned-budgets` and `/planned/planned-budgets/:id` lazy-loaded routes.
- [ ] Add typed client operations and invalidate only future-plan query keys after mutations.
- [ ] Add concise localization copy. Run the focused frontend test; expect PASS. Commit with `feat: add planned budgets navigation`.

### Task 4: Build the list, creation, and Salary Profile UI

**Files:**

- Create: `packages/frontend/src/pages/future-budgets/index.vue`
- Create: `packages/frontend/src/pages/future-budgets/future-budget-list.vue`
- Create: `packages/frontend/src/pages/future-budgets/salary-profile-dialog.vue`
- Create: `packages/frontend/src/pages/future-budgets/future-budget-create-dialog.vue`
- Test: `packages/frontend/src/pages/future-budgets/*.spec.ts`

**Interfaces:** Consumes Task 3 APIs and existing category/group selectors. Produces a manual plan list and Salary Profile editor.

- [ ] Write failing tests for editing the Salary Profile, pre-filling creation, creating duplicate/overlapping plans, and overriding salary only on the new plan.
- [ ] Reuse normal budget card and form patterns. Include amount, schedule, next-pay date, and category/group. Do not validate against overlapping ranges or duplicate names.
- [ ] Run focused tests; expect PASS. Commit with `feat: add future budget creation and salary settings`.

### Task 5: Build plan detail and source controls

**Files:**

- Create: `packages/frontend/src/pages/future-budgets/future-budget-details.vue`
- Create: `packages/frontend/src/pages/future-budgets/plan-entry-dialog.vue`
- Create: `packages/frontend/src/pages/future-budgets/linked-recurring-sources.vue`
- Create: `packages/frontend/src/pages/future-budgets/salary-profile-update-dialog.vue`
- Test: `packages/frontend/src/pages/future-budgets/*.spec.ts`

**Interfaces:** Consumes Task 2 stats, entry, and override contracts. Produces an isolated plan ledger and projected budget summary.

- [ ] Write failing tests for salary apply/dismiss, plan-local recurrence, source exclusion, source override, and changing an entry without changing another plan.
- [ ] Display salary, linked recurring, and plan-only sections before combined income/expense/net cards, category/group breakdown, timeline, and warnings.
- [ ] Use existing budget components when their data contract fits; add focused components for source rows and plan entries.
- [ ] Run focused tests; expect PASS. Commit with `feat: add future budget plan detail`.

### Task 6: Verify isolation and document the feature

**Files:**

- Modify: planned-feature documentation selected by the repository
- Test: focused suites from Tasks 1-5

- [ ] Add isolation tests proving a future-plan entry changes neither normal-budget stats nor account balance, transaction count, bank matching, or another plan.
- [ ] Document the difference between Future Budget Planner, normal budgets, planned transactions, and recurring payments. Describe salary-update prompts and plan-local isolation.
- [ ] Run `npm -w packages/backend run test:e2e -- future-budgets`, `npm -w packages/frontend run test -- future-budgets`, both lint scripts, and `git diff --check`; expect exit code 0 while allowing pre-existing warnings.
- [ ] Commit with `docs: explain future budget planner`.
