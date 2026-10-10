# Smart recurring-payment matching, discovery, and planned-budget sync: design

Date: 2026-10-10. Status: proposed. Scope: backend (`packages/backend`), web (`packages/frontend`), iOS (`ios/`).

All paths are relative to `packages/backend/src` unless they say otherwise.

## 0. The user's report

1. Recurring payments are poorly recognised. Transactions can't be found and linked to recurring payments the user created by hand. An amount mismatch shouldn't mean "not associated".
2. Discovery should use AI and smarter heuristics.
3. With "auto-add synced transactions" on, planned budgets don't link the transactions of manually added recurring payments.

---

## 1. Findings: root causes, with evidence

### 1.1 Matching today

Entry points (the only places the engine runs):

- `services/transactions/create-transaction.ts:638-649` calls `matchTransactionToSubscriptions` for every non-transfer create. This covers manual creates, CSV imports and bank sync, because providers create rows through `createTransaction`.
- `services/subscriptions/event-listeners.ts:13-69` handles `TRANSACTIONS_SYNCED`. It is emitted only by `services/bank-data-providers/utils/emit-transactions-sync-event.ts:19`, debounced 5 s with a 15 s max wait, and runs the same engine again. Rows that already have a link are skipped.

Algorithm (`services/subscriptions/matching-engine.ts`):

| Step                                        | Line    | Behaviour                                                                                                                                                                                            |
| ------------------------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Any existing link row blocks matching       | 31-34   | `SubscriptionTransactions.findOne({ transactionId })` with **no status or subscription filter**. A tx unlinked from subscription A can never auto-match subscription B.                              |
| transactionType must be equal               | 45      | hard gate                                                                                                                                                                                            |
| `subscription.accountId` must be equal      | 50-52   | hard gate                                                                                                                                                                                            |
| **No rules means no match**                 | 54-55   | `if (!rules \|\| rules.length === 0) continue;`                                                                                                                                                      |
| All rules ANDed, any failure means no match | 60-68   | hard gates                                                                                                                                                                                           |
| `note contains_any`                         | 179-183 | case-insensitive substring on `note` only. **Payee is never looked at**, even though `Subscriptions.payeeId` exists and `transaction.payeeId` is resolved earlier (`create-transaction.ts:490-502`). |
| `amount between`                            | 184-218 | **hard gate**. Same currency is exact; cross-currency allows ±5%.                                                                                                                                    |
| Score                                       | 128-175 | amount closeness, used **only to break ties between rule-matching subscriptions**                                                                                                                    |
| Date                                        | none    | no date or due-date proximity signal at all                                                                                                                                                          |
| Category                                    | none    | not used as a signal                                                                                                                                                                                 |

**Why a manually created recurring payment never gets matches:**

- **R1. Rules default to empty.** `services/subscriptions/create-subscription.ts:57` defaults `matchingRules = { rules: [] }`. The iOS form only sends rules in "match" mode (`ios/MoneyMatter/Features/Planning/Recurring/RecurringPaymentFormSheet.swift:429`), and web quick-add sends none. `matching-engine.ts:55` then skips the subscription forever. `assertAutoRecordConsistent` (`create-subscription.ts:98-104`) even makes auto-record and rules mutually exclusive, so auto-record subscriptions can _never_ match.
- **R2. Amount is a hard gate** whenever the user (or an accepted candidate) has an amount rule (`matching-engine.ts:184-218`). "Price went from 15.49 to 17.99" means silently no match.
- **R3. The account becomes a hidden hard gate.** `services/subscriptions/mark-period-paid.ts:70-73` silently persists the first pay-time `accountId` onto the subscription. After that, `matching-engine.ts:50` and `suggest-historical-matches.ts:60` ignore every transaction on any other account, for example a card change.
- **R4. Payee, merchant similarity and due-date proximity are not signals at all**, as the table above shows.
- **R5. Two disconnected link concepts.** `mark-period-paid.ts:80-141` (LINK and CREATE modes, and `process-auto-record.ts:78-88`) writes only `SubscriptionPeriods.transactionId`. It never writes `SubscriptionTransactions`. Conversely, the matcher and manual link (`link-transactions.ts`, `matching-engine.ts:82-86`) never mark the corresponding period paid. A recurring payment the user pays with "Mark paid" therefore has **zero rows in `SubscriptionTransactions`**. That is the table "linked transactions", the plan projection (§1.3) and discovery exclusion all read.
- **R6. No backfill.** Nothing re-scans history when a subscription is created, edited or accepted from a candidate. `update-subscription.ts:246` documents "applies to later matches only".

**Why the user can't _find_ transactions to link:**

- **R7. The only picker is "suggested matches", and it is rules-gated.** `services/subscriptions/suggest-historical-matches.ts:27-29` returns `[]` when there are no rules, and 43-45 returns `[]` when no SQL-able rule exists. When rules do exist, it ANDs them as SQL hard filters (100-154): amount `BETWEEN` and note `ILIKE`. On top of that it applies a 12-month cutoff (13, 33), `accountId` (60), `planned: 'exclude'`, and `MAX_SUGGESTIONS = 100`.
- Web: `packages/frontend/src/pages/planned/subscriptions/subscription-details.vue:163-173` and `1015-1063` render only `loadSuggestedMatches` (`packages/frontend/src/api/subscriptions.ts:139-141`, `GET /subscriptions/:id/suggest-matches`). The empty state's only call to action is "Add matching rules" (1037-1055). The web mark-paid dialog (`components/subscription-mark-paid-dialog.vue`) has no "pick an existing transaction" mode, although the API supports `transactionId`.
- iOS: `RecurringLinkTransactionsSheet` (`ios/MoneyMatter/Features/Planning/Recurring/RecurringPaymentSheets.swift:151-222`) loads only `Endpoints.recurringSuggestedMatches` (`ios/MoneyMatterKit/Sources/MoneyMatterKit/Planning/RecurringEndpoints.swift:238-240`) and shows "No unlinked transactions look like this payment." It has no search, date or account filter.
- **There is no backend endpoint to search all of a user's transactions in the context of a subscription.** `GET /transactions` has `noteSearch`, date range and `accountIds` (`controllers/transactions.controller/get-transaction.ts:46-100`), but it does not search payee names or annotate link state.

### 1.2 Discovery today

`services/subscriptions/detect-candidates.ts` and `detect-candidates-utils.ts`:

- **Input** (`detect-candidates.ts:114-128`): expenses only, 12-month lookback (`LOOKBACK_MONTHS = 12`, line 25), `note` must be non-empty (119), transfers excluded, already-linked rows excluded. The linked-tx query at 105-111 is **not scoped to the user** and scans every user's links. Income recurring payments (salary, rent received) are never discovered.
- **Grouping** (`detect-candidates-utils.ts:66-101`): exact `normalizeNote` string + `accountId` + `currencyCode`. `normalizeNote` (11-27) only strips runs of 6 or more digits and dates. As a result, `NETFLIX.COM 8822 AMSTERDAM` and `NETFLIX.COM 1931 LOS GATOS` fall into different groups. `payeeId` is ignored. The same merchant on two cards splits into two groups.
- **Amount** (`detect-candidates.ts:263-276`): coefficient of variation (CV) ≤ 0.2, otherwise 10% buckets, each needing at least 3 transactions. Utilities and usage-based bills fail.
- **Cadence** (`detect-candidates.ts:278-287`): the CV of raw intervals must be ≤ 0.5. One skipped month (intervals 30, 30, 61, 30) or a duplicate charge (an interval of 1 day) kills the group. There is no tolerance-based slot fitting and no day-of-month logic. `mapIntervalToFrequency` (`utils:187-194`) is just thresholds.
- **Annual charges are impossible**: they need at least 3 occurrences (`MIN_OCCURRENCES = 3`, line 27) inside a 12-month window.
- **Dedupe** (`detect-candidates.ts:158-182`) is keyed on `suggestedName`, so dismissed candidates stay suppressed forever. Clusters that already correspond to an _existing_ subscription are reported again as new candidates rather than turned into link suggestions. `serialize-candidate.ts` only adds a fuzzy name hint.
- **No AI** is involved anywhere. `SUBSCRIPTION_MATCH_SOURCE.ai` exists (`packages/shared/src/types/enums.ts:506-510`) but is unused.

**AI infrastructure available for reuse:**

- `services/ai/ai-client-factory.ts:73-105`: `createAIClient({ userId, feature })` returns `null` when nothing is configured. It covers user keys, custom endpoints, and server keys gated by the `FEATURES.operator_ai` entitlement (`services/ai/ai-model-resolver.ts:40-60`, which uses `hasFeature`).
- `services/ai/ai-call-guards.ts:22-33`: per-call timeout and retries.
- `services/ai/ai-output-limit.ts`: `AI_MAX_OUTPUT_TOKENS` and `hitOutputCeiling`.
- `services/ai/ai-error-classifiers.ts:179`: `classifyAiCallFailure`.
- `services/ai/custom-endpoint-failure.ts`: `markCustomEndpointUnreachable`.
- Usage pattern: `services/ai-categorization/categorization-service.ts:101-230`, which calls `generateText`, reads usage tokens and classifies failures.
- Features are an enum, `AI_FEATURE` (`packages/shared/src/types/enums.ts:407-415`). Adding a feature also touches `services/ai/models-config/recommendations.ts`, `packages/frontend/src/common/const/ai-features.ts` and the settings model selector.
- Per-feature model configuration lives in `services/user-settings/ai-feature-settings`.
- Statement parsing has a cost-estimation precedent: `services/import-export/statement-parser/cost-estimation.service.ts`.
- e2e AI mocking: `@tests/mocks/gemini/mock-api` (`createGeminiMock`, via `global.mswMockServer.use`) and `tests/helpers/ai-test-env.ts` (`useSelfHostWithoutServerAiKeys`).

**Payee infrastructure available for reuse:**

- `services/payees/normalize-name.ts:14` (`normalizePayeeName`).
- `services/payees/fuzzy-matcher.ts`: a Fuse.js index over payee names and aliases with `ignoreLocation`, threshold 0.4.
- `services/payees/payee-namespace.ts` (alias resolution).
- The payee fuzzy backfill runs on `TRANSACTIONS_SYNCED` with a 4 s debounce (`services/payees/event-listeners.ts:7`), so it generally finishes before the subscription listener's 5 s debounce.

### 1.3 Planned budgets ("auto-add synced transactions")

- **P1. Projection hard-requires an active link to a real transaction.** `controllers/future-budgets/future-budgets.ts:88-98` (`realBankRecurringTransactionsInclude`: `required: true`, `through.where.status = active`, `isPlanned: false`) is used at 235-240. The comment there states the intent: _"Manually-created reminders have no link and are excluded by `required: true`."_ Combined with R1 and R5, a manual recurring payment has no `SubscriptionTransactions` rows even after being paid via "Mark paid" or auto-record, so it **never appears in any plan**.
- **P2. Variable-amount subscriptions are dropped**: `future-budgets.ts:262` (`!subscription.expectedAmount` returns `[]`).
- **P3. Auto-add ignores subscription links entirely.** `services/future-budgets/auto-add-synced-transaction.ts:22-52` creates a context-free `FutureBudgetEntries` row (`frequency: null`, no transaction or subscription reference) for every real transaction. It is called from `create-transaction.ts:748-768`, _after_ the subscription match at 640. The model has no column to hold the link (`models/future-budget-entries.model.ts:12-20`). So a recurring payment's transaction shows up as an unrelated one-off "manual" entry. When the subscription _is_ projected, its expected occurrence is still counted as well, which double-counts it.
- **P4. Create-time only.** Turning the toggle on (`controllers/future-budgets/future-budgets.ts:186`) doesn't backfill. Transactions linked _later_ (manual link, mark-paid LINK, a future backfill) are never reconciled. Editing or deleting a transaction leaves a stale entry.
- Migration status: `migrations/20260826000000-create-future-budget-planner.ts` and `20260827000000-add-auto-add-synced-transactions-to-future-budget-plans.ts` are **not on `origin/dev`**, according to `git diff --name-only origin/dev...HEAD`. Per CLAUDE.md rule 11, amend them rather than adding a new migration. The subscription migrations (`20260201000000-create-subscriptions.ts`) are on dev, so subscription schema changes need a new migration.

---

## 2. Design

### 2.1 Scoring matcher (transaction ↔ recurring payment)

New folder `services/subscriptions/matching/`. All functions take object params.

```
matching/
  merchant-key.ts            buildMerchantKey({ raw }) -> { key, tokens }; tokenSimilarity({ a, b })
  subscription-profile.ts    loadSubscriptionProfiles({ userId, subscriptionIds? }) -> SubscriptionProfile[]
  expected-dates.ts          expectedDatesAround({ subscription, periods, around, windowDays }) -> string[]
  score-transaction.ts       scoreTransaction({ profile, transaction, fx }) -> MatchScore   (pure, plus an injected fx fn)
  decide-matches.ts          decideMatches({ scored, existingLinks, dismissed }) -> { autoLinks, suggestions }
  apply-decisions.ts         applyMatchDecisions({ userId, decisions, matchContext })   (writes links and suggestions, marks periods, syncs plans)
  candidate-transactions.ts  findCandidateTransactions({ userId, profile, window, limit })  (SQL prefilter)
  run-for-transaction.ts     matchTransaction({ transaction, userId })   (replaces matchTransactionToSubscriptions internals)
  backfill-subscription.ts   backfillSubscriptionMatches({ userId, subscriptionId })
  types.ts                   MatchReason, MatchScore, SubscriptionProfile
```

#### Merchant key (`merchant-key.ts`)

1. `normalizePayeeName({ raw })` (reused).
2. Drop noise tokens. Card and terminal words: `pos, purchase, card, visa, mastercard, mc, debit, credit, payment, pmt, recurring, rec, txn, ref, online, www, com, net, org, inc, ltd, llc, gmbh, sa, bv`. Also drop any token containing 4 or more digits, any alphanumeric token with 3 or more digits, and single characters.
3. `key` is the first three remaining tokens joined by a space. `tokens` is the full remaining set.
4. `tokenSimilarity`: `max(jaccard(tokens), containment)`, where containment = |A∩B| / min(|A|,|B|). The fallback is a Fuse score (`ignoreLocation`, threshold 0.4) converted to 1 − score. The Fuse fallback covers typos and concatenations ("netflixcom").

#### Subscription profile (`subscription-profile.ts`)

Loaded once per run, per user. Fields:

- `nameTokens`: `buildMerchantKey(subscription.name)`.
- `payeeIds`: `subscription.payeeId` plus the payees of active linked transactions.
- `aliasTokens`: names and aliases of those payees.
- `keywords`: all `note contains_any` rule values plus `learnedTokens` (merchant keys covering at least 30% of active linked transactions, top 5).
- `amount`: `{ expected, currency }`, from `expectedAmount` or the median of the last 6 linked amounts (`learned = true`). Also `mad` (median absolute deviation) when learned.
- `accounts`: `subscription.accountId` plus the accounts of the linked transactions.
- `categoryId`.
- `frequency`, `anchor` (`dueDate ?? startDate`), `anchorDay`.
- Open periods (`upcoming` / `overdue`) and paid periods, with their `dueDate` and `transactionId`.
- `rules`: the explicit matching rules, kept for the gating semantics below.

#### Hard gates (never scored past)

- `transaction.transactionType !== subscription.transactionType`.
- Two-leg transfers (as today, `create-transaction.ts:638`).
- The tx has an **active** link to any subscription.
- The pair is dismissed (`SubscriptionMatchSuggestions.status = 'dismissed'`) or the tx was unlinked from **this** subscription (`SubscriptionTransactions.status = 'unlinked'`).
  - Change: the global check at `matching-engine.ts:31-34` narrows to this rule.
- **The user set a fixed-amount rule** (`amount between`), and the amount falls outside it. It stays a gate, as the user explicitly asked.
- **The user set an explicit `accountId` rule**, and the account differs.
- A legacy `transactionType` rule fails.

#### Signals and weights (each signal is in [0, 1]; total = Σ w·s)

| Signal          | w    | Value                                                                                                                                                                                                                                                                                                                                              |
| --------------- | ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `merchant`      | 0.40 | 1.0 when `tx.payeeId ∈ profile.payeeIds`. Otherwise the max `tokenSimilarity` of the tx merchant key (`note`, plus the payee name when one is set) against `nameTokens ∪ aliasTokens ∪ learnedTokens`, mapped as ≥0.8 → 1.0 and 0.5–0.8 → linear 0.5–1.0, else 0.                                                                                  |
| `keyword`       | 0.10 | 1.0 when any explicit `note contains_any` value is a substring of the note (legacy rule semantics), else 0.                                                                                                                                                                                                                                        |
| `date`          | 0.25 | `d` = days to the nearest expected date (open or paid period `dueDate`, or the date projected from the anchor with `calculate-next-due-date.ts` going back and forward). Window `W` by frequency: weekly 2, biweekly 4, monthly 6, quarterly 10, semi_annual 15, annual 20 days. Score `max(0, 1 − d/W)`. 0.5 when the subscription has no anchor. |
| `amount` (soft) | 0.15 | `r = \|a − e\| / e` after converting to the profile currency with `calculateRefAmount` (memoised per (date, pair)). Score is 1 when r ≤ 0.02, linear to 0 at r = 0.5, and 0 beyond. 0.5 when there is no expected amount. When the amount is learned and the subscription varies (MAD/median > 0.15), r is divided by 2 (lenient).                 |
| `account`       | 0.05 | 1 when `tx.accountId ∈ profile.accounts`, 0.5 when the profile has no accounts, else 0.                                                                                                                                                                                                                                                            |
| `category`      | 0.05 | 1 when equal, 0.5 when either side is null, else 0.                                                                                                                                                                                                                                                                                                |

Legacy rule path: when the subscription has rules and **all** of them pass, `score = max(score, 0.95)` with reason `rule_match`. Existing rule-based subscriptions therefore auto-link exactly as today, which keeps `matching-disambiguation.e2e.ts` and `subscriptions.e2e.ts:778-918` green.

#### Tiers

- **auto-link**: `score ≥ 0.80` **and** identity evidence (`merchant ≥ 0.6` or `rule_match` or `keyword = 1`), and none of the caps below apply.
- **suggested**: `score ≥ 0.50` **and** at least one of: `merchant ≥ 0.3`, `keyword = 1`, or (`amount ≥ 0.9` **and** `date ≥ 0.7`).
- **Caps** (the result is at most `suggested`):
  - `subscription.accountId` is set but the tx is on another account. The reason is `different_account`. This replaces today's silent gate; see R3.
  - The nearest period already has a linked or paid transaction, for frequencies other than weekly. The reason is `period_already_covered`.
  - The top two subscriptions for a tx score within 0.05 of each other. The reason is `ambiguous_with_other_subscription`. Exception: when both are rule-path, keep today's amount-closeness tie-break (`matching-engine.ts:128-175`).
  - A planned (`isPlanned`) tx with no `rule_match`.

Worked examples, assuming a monthly subscription:

- Payee match, on the due date, same account, amount 3× off: 0.40 + 0.25 + 0 + 0.05 + 0.05 = **0.75**, so suggested ("amount differs").
- The same with the amount within 10%: about **0.87**, so auto-linked.

#### Reasons (returned to clients)

`MatchReason = { code, weight, value, detail? }` with these codes:

- `payee_match`, `merchant_similar`, `learned_merchant`, `keyword_match`, `rule_match`
- `near_due_date` (detail `{ dueDate, days }`), `far_from_due_date`
- `amount_close` (detail `{ deviationPct }`), `amount_differs`
- `same_account`, `different_account`, `same_category`
- `period_already_covered`, `ambiguous_with_other_subscription`

Clients localise the codes. The shared type lives in `packages/shared/src/types/subscriptions-matching.ts`.

#### Writes on a decision (`apply-decisions.ts`)

**Auto-link:**

- `SubscriptionTransactions` row with `matchSource: rule` and new nullable columns `matchScore` and `matchReasons`. The UI shows "Auto-matched · 87%" when `matchScore != null`. No enum change is needed.
- Stamp payee and tags (`stampSubscriptionPayeeAndTags`).
- Stamp the category **only on the rule path** (today's policy, `matching-engine.ts:97-109`).
- **Mark the nearest open period paid** in LINK mode (`transactionAutoCreated = false`) when the tx date is within `W` of its `dueDate` and the period has no `transactionId`. This calls a new internal `markPeriodPaidByLink`, extracted from `mark-period-paid.ts:88-141`, which also runs `ensureNextPeriodExists`.
- Delete pending suggestion rows for this tx across all subscriptions.
- Call `syncPlanEntriesForTransactions` (§2.4).

**Suggested:**

- Upsert into `SubscriptionMatchSuggestions` (`status: pending`) for the top three subscriptions at or above the threshold.

#### Fixing R5 in `mark-period-paid.ts`

- Both LINK and CREATE modes also call `linkTransactionsToSubscription` (re-activate or create the link, `matchSource: manual`). CREATE mode runs through `createTransaction`, whose engine may already have linked the row; the call is idempotent.
- `revert-period.ts` deletes the link only when it deletes the auto-created tx (cascade). In LINK mode the link stays.

#### Where it runs

1. **On transaction create**: `create-transaction.ts:638-649` keeps calling `matchTransactionToSubscriptions`, now a thin wrapper over `matching/run-for-transaction.ts`. Profiles are cached per user per request.
2. **On sync**: `event-listeners.ts` keeps its debounce and re-evaluates unlinked rows only. This second pass benefits from the payee fuzzy backfill that has run by then (4 s versus 5 s debounce).
3. **On transaction update**: when `note`, `payeeId`, `amount`, `time`, `accountId` or `categoryId` changes on an unlinked row, re-run `matchTransaction`. Hook it in the update-transaction service, after commit.
4. **Backfill**: `backfillSubscriptionMatches({ userId, subscriptionId })`.
   - **Window**: 400 days back and 7 days forward.
   - **Triggers**: `create-subscription.ts`, after the subscription and its first period exist. `update-subscription.ts`, when name, payeeId, matchingRules, expectedAmount, currency, accountId, categoryId, frequency or dueDate changes. `resolve-candidate.ts`, after linking samples (this also learns from the samples). `toggle-active.ts` (when activated). Also `PUT /subscriptions/:id` when rules change.
   - **Execution**: synchronously, after the main transaction commits, in its own `withTransaction`. This keeps e2e tests deterministic. A hard cap of 2,000 prefiltered candidates bounds the latency; if that ever becomes a problem, move it to a BullMQ queue following `services/ai-categorization/categorization-queue.ts`.
   - **SQL prefilter** (`candidate-transactions.ts`): user's transactions (`access: { accountOwner: userId }`), same `transactionType`, in the window, not actively linked, not dismissed for this subscription, not two-leg transfers. Rows must also match at least one of:
     - `payeeId IN profile.payeeIds`
     - `note ILIKE ANY(%token%)` for name, alias, keyword and learned tokens of 3 or more characters
     - `amount BETWEEN expected×0.5 AND expected×1.5` **and** `time` within ±W of any expected date
   - **Order**: `time DESC`, `LIMIT 2000`.
   - **Effect**: auto-links become links and marked periods (only open periods; historic periods don't exist). Suggestions become pending rows.
5. `suggest-historical-matches.ts` is rewritten to delegate: same prefilter and scorer, read-only (no writes on GET).

### 2.2 Linking UX/API

#### Data model (new migration `migrations/20261010000000-subscription-smart-matching.ts`)

- **New table `SubscriptionMatchSuggestions`**:
  - `subscriptionId` (UUID, FK, ON DELETE CASCADE) and `transactionId` (UUID, FK, ON DELETE CASCADE), together the **PK**.
  - `userId` (INT, FK).
  - `score` (REAL).
  - `reasons` (JSONB).
  - `status` (ENUM `pending`, `dismissed`).
  - `source` (ENUM `engine`, `discovery`).
  - `createdAt` and `updatedAt`.
  - Indexes: `(userId, status)` and `(transactionId)`.
- **`SubscriptionTransactions`**: add `matchScore REAL NULL` and `matchReasons JSONB NULL`.
- **Model**: `models/subscription-match-suggestions.model.ts`, registered where the other subscription models are registered.

#### Endpoints

Routes are added to `routes/subscriptions.route.ts`. Controllers live in `controllers/subscriptions/` and use `createController` with zod schemas.

**1. `GET /subscriptions/:id/suggestions?limit=50`** (`get-suggestions.ts`)

- Runs the prefilter and scorer live, and unions persisted `pending` rows (for example from discovery).
- Removes dismissed and actively linked rows, keeps `score ≥ 0.5`, and sorts by score descending, then time descending.
- Response `data`:
  ```ts
  {
    suggestions: Array<{
      transaction: SerializedTransaction; // decimals via serializer
      score: number; // 0..1, 3dp
      confidence: 'high' | 'medium'; // high: score >= 0.8
      reasons: MatchReason[];
      nearestDueDate: string | null; // YYYY-MM-DD
      daysFromDue: number | null;
      amountDeviationPct: number | null;
    }>;
    dismissedCount: number;
  }
  ```
- Errors: 404 for an unknown subscription or another user's; 400 for a bad id.
- `GET /subscriptions/:id/suggest-matches` stays as a **compatibility alias** returning `suggestions.map(s => s.transaction)`, for shipped iOS builds. Clients migrate to `/suggestions`.

**2. `GET /subscriptions/:id/linkable-transactions?search=&from=&to=&accountIds=&sort=date|relevance&limit=30&offset=0`** (`search-linkable-transactions.ts`)

- Searches **all** of the user's real transactions of the subscription's `transactionType`. There is **no amount, account or date gating** beyond the user-supplied filters.
- `search` (at least 2 characters) matches `note ILIKE` OR the payee name `ILIKE` (join `Payees`). When it parses as a number, it also matches the amount within ±0.01 (`Money.fromDecimal`).
- Each item is annotated with the scorer output:
  ```ts
  {
    items: Array<{
      transaction;
      score: number;
      reasons: MatchReason[];
      linkedSubscription: { id: string; name: string } | null;
      isDismissed: boolean;
    }>;
    hasMore: boolean;
  }
  ```
- Default sort is `date` descending. `relevance` sorts by score.
- Errors: 404 for an unknown subscription; 400 for invalid dates, `from > to`, or `limit > 100`.

**3. Accept** reuses `POST /subscriptions/:id/transactions` (`link-transactions.ts`). Changes in the service:

- Delete `SubscriptionMatchSuggestions` rows for these pairs, which also clears a dismissal (an explicit link overrides a past dismissal).
- Delete pending rows for these transactions on other subscriptions.
- Mark the nearest open period paid as in §2.1.
- Call `syncPlanEntriesForTransactions`.
- The existing 409 for a tx linked to _another_ subscription stays. The picker shows such rows as "Linked to X" and disables them.

**4. Dismiss**: `POST /subscriptions/:id/suggestions/dismiss` with body `{ transactionIds: string[] }` (1–100) (`dismiss-suggestions.ts`).

- Upserts `status: dismissed` and returns `{ dismissed: n }`.
- 404 when any id isn't the user's transaction (`findTransactions` with `access: { creator: userId }`, like `link-transactions.ts:26-36`).
- Unlinking (`unlink-transactions.ts`) keeps today's `unlinked` status, which acts as the rejection memory for previously linked rows.

**5. Counts**: `GET /subscriptions` list items and `GET /subscriptions/:id` gain `pendingSuggestionsCount`, a count of `pending` rows that are not dismissed.

**6. MCP**: add an optional `get_subscription_suggestions` tool via the `add-mcp-tool` skill. This is out of the critical path.

#### Web UI (`packages/frontend`; read `.claude/skills/frontend-rules/SKILL.md` first)

- `api/subscriptions.ts`: add `loadSubscriptionSuggestions`, `searchLinkableTransactions` and `dismissSubscriptionSuggestions`, with the types from `@bt/shared`.
- New `pages/planned/subscriptions/components/link-transactions-dialog.vue`, which replaces the inline suggest dialog in `subscription-details.vue:1014-1066`. It is a `ResponsiveDialog` with two tabs:
  - **Suggested**: a ranked list. Each row shows a confidence pill, reason chips (`match-reason-chips.vue`, for example "Same payee", "2 days from due date", "+16% vs expected") and a per-row "Not this one" (dismiss). Multi-select, then "Link selected".
  - **Search all**: a search input (debounced 300 ms), a date-range picker, an account multi-select and an infinite list. Rows linked elsewhere are disabled with "Linked to {name}". Each row shows its score as a subtle hint.
  - Layout uses container queries per CLAUDE.md rule 13.
- `linked-transactions-section.vue`: a banner "N suggested transactions" when `pendingSuggestionsCount > 0`, opening the dialog on the Suggested tab. Linked rows with `matchScore` show "Auto-matched".
- `subscription-list-item.vue`: a small dot or badge when `pendingSuggestionsCount > 0`.
- `subscription-mark-paid-dialog.vue`: a third option, "Link an existing transaction". It opens the same dialog in single-select mode and calls `markSubscriptionPeriodPaid` with `transactionId`.
- i18n keys go to `en` and `uk` via the `i18n-editor` subagent (`planned.subscriptions.suggestions.*`, `...reasons.*`).

#### iOS UI (`ios/`)

- `MoneyMatterKit/Sources/MoneyMatterKit/Planning/RecurringEndpoints.swift`: add `recurringSuggestions(id:)`, `recurringLinkableTransactions(id:query:)` and `dismissRecurringSuggestions(id:transactionIds:)`.
- `RecurringModels.swift`: add `RecurringSuggestion`, `RecurringMatchReason` (with a code enum plus `.unknown` for forward compatibility), `RecurringLinkableItem` and `pendingSuggestionsCount`.
- `Features/Planning/Recurring/RecurringPaymentSheets.swift`: rebuild `RecurringLinkTransactionsSheet` with a segmented control (Suggested / Search all).
  - Suggested: `List` with `selection`, reason chips, a confidence capsule, and a trailing swipe action "Not this one" (dismiss).
  - Search all: `.searchable`, a toolbar filter menu (date range presets plus custom, and accounts), and paging on scroll. Rows linked elsewhere are disabled with a caption.
- `RecurringPaymentDetailScreen.swift` (`transactionsSection`, around line 443): a "N suggested" row that opens the sheet. The auto-matched caption shows `matchScore`.
- `RecurringPaymentsSegmentView.swift`: a badge on rows with pending suggestions.
- Mark-paid sheet (`RecurringMarkPaidSheet`): add "Link existing transaction", which opens the sheet in single-select mode.
- Tests: decoding tests in `MoneyMatterKitTests/Planning/`, following the `PlannedBudgetsTests.swift` style.

### 2.3 Smarter discovery

#### Heuristics

The work happens in new folder `services/subscriptions/discovery/`. `detect-candidates.ts` becomes the orchestrator.

1. **Input**: expenses **and income**. Lookback is extended to **25 months** for annual detection. The note is no longer required when `payeeId` is set. Transfers, planned rows and actively linked rows stay excluded. The linked-tx query is scoped to the user.
2. **Merchant clustering** (`cluster-merchants.ts`): the cluster key is `payee:<payeeId>` when set, else `buildMerchantKey(note).key`. Clusters are then merged when their token sets have a `tokenSimilarity` of 0.75 or more, or when they share a payee alias. Clusters are split by `transactionType` and `currencyCode` but **not by account**; the accounts are recorded, and the most frequent one becomes `accountId`. Duplicate charges within 3 days collapse into one occurrence (the larger amount is kept).
3. **Cadence detection** (`detect-cadence.ts`): for each frequency with nominal period P (7, 14, 30.44, 91.31, 182.62, 365.25 days) and tolerance `τ = max(2, 0.15·P)`:
   - Anchor on the first occurrence, then map each occurrence to the nearest slot `k·P`, allowing missed slots.
   - `fit` is the fraction of occurrences within τ of their slot.
   - `coverage` is the number of hit slots divided by the number of slots between the first and last occurrence.
   - Monthly and longer frequencies also compute the circular day-of-month spread; a spread of 5 days or less adds 0.1.
   - The frequency with the best `0.6·fit + 0.4·coverage` wins. A cluster is irregular-but-periodic when `fit ≥ 0.7` even if coverage is lower (missed months).
4. **Amount profile** (`amount-profile.ts`): median and MAD. Variability `v = MAD/median` classifies the amount as fixed (≤ 3%), stable (≤ 15%) or variable (> 15%).
   - Variable clusters qualify when `fit ≥ 0.8`, which covers utilities.
   - `splitByAmountBuckets` is kept only for the case of two or more stable levels on the same cadence (for example two Apple plans).
   - `expectedAmount` is the median, or the latest amount when there is a clear step change (the last 2 occurrences are within 3% of each other and more than 10% off the previous median).
5. **Minimum occurrences**: 3 for frequencies up to quarterly; 2 for semi-annual and annual.
6. **Confidence**: `0.35·fit + 0.2·coverage + 0.15·min(1, n/6) + 0.15·(1 − min(1, v/0.5)) + 0.15·recency`, where recency is 1 when the last occurrence is within 1.5·P of now, else it decays to 0 at 3·P.
   - Keep a candidate when confidence ≥ 0.55.
   - Clusters scoring 0.35 to 0.55 are "ambiguous". They go to AI review when AI is configured; otherwise they are dropped.
7. **Existing-subscription routing** (`route-to-existing.ts`): score each cluster's transactions against every active subscription profile (§2.1). When 50% or more score ≥ 0.5 for subscription S, **do not create a candidate**. Instead, upsert `SubscriptionMatchSuggestions` rows (`source: 'discovery'`) for S. This is the "what linkages need to be made" output, and it surfaces as `pendingSuggestionsCount` and as a "Suggested links for existing payments" section in the discover dialog.
8. **Dedupe** by the new `merchantKey` column, plus `transactionType` and `currencyCode`, rather than `suggestedName`. A dismissed candidate resurfaces only when at least 3 new occurrences have arrived after `resolvedAt`.

#### Optional AI review (`discovery/ai-review.ts`)

- **Feature**: `AI_FEATURE.recurringDetection = 'recurring_detection'` in `packages/shared/src/types/enums.ts`. Register it in `services/ai/models-config/recommendations.ts` (a cheap or fast tier) and in `packages/frontend/src/common/const/ai-features.ts`, so the settings model selector lists it.
- **Gate**: `const client = await createAIClient({ userId, feature: AI_FEATURE.recurringDetection })`. When this returns `null`, skip the pass (`aiStatus: 'skipped'`). The resolver already enforces the cost policy: user keys or endpoints, with server keys only under the `operator_ai` entitlement. No new billing logic is needed.
- **Input**: at most 40 clusters per run, one call. Send ambiguous clusters first, then accepted clusters whose name looks raw (any all-caps or digit-heavy token).
  - Fields per cluster: `{ id, merchantKey, descriptions: up to 3 raw notes truncated to 60 chars with digit runs ≥ 4 masked as '#', occurrences: up to 24 { date, amount, currency }, type }`.
  - Account ids and names are not sent.
- **Prompt**: the system prompt asks for strict JSON: `[{ id, isRecurring, name, frequency: weekly|biweekly|monthly|quarterly|semi_annual|annual|irregular, expectedAmount, amountVaries, confidence: 0..1, reason }]`.
- **Call**: `generateText` with `aiCallGuards({ provider })`, `maxOutputTokens: AI_MAX_OUTPUT_TOKENS` and a request timeout of 45 s (`AbortSignal.any` with the guard). Parse with zod; malformed items are ignored. Log input and output tokens as `categorization-service.ts:141-142` does.
- **Merge**:
  - AI says `isRecurring` with confidence ≥ 0.6: final confidence is `0.5·heuristic + 0.5·ai`. Use the AI's `name` as `suggestedName` and its frequency when the heuristics were ambiguous. Set `detectionSource = 'ai'` and store `aiReason`.
  - AI says not recurring with confidence ≥ 0.7: drop the cluster.
  - Otherwise, keep the heuristic result.
- **Failures**: `classifyAiCallFailure`. Endpoint down calls `markCustomEndpointUnreachable`. The run falls back to heuristic results with `aiStatus: 'failed'`, and detection never fails because of AI.
- **Cost controls**:
  - One call per detection run, on top of the existing 1-hour cooldown (`detect-candidates.ts:24, 65`).
  - Each cluster gets `aiFingerprint = sha256(merchantKey + sorted tx ids)`; clusters whose fingerprint matches an already-reviewed candidate are not re-sent.
  - The 40-cluster cap bounds input to roughly 10k tokens.
- **Response**: `GET /subscriptions/detect-candidates` adds `aiStatus: 'applied' | 'skipped' | 'failed'`. Candidates add `detectionSource`, `aiReason`, `amountVariability`, `transactionType` and `nextExpectedDate`.

**Candidate schema changes** (new migration `migrations/20261010000001-extend-subscription-candidates.ts`): add `merchantKey STRING(200)`, `transactionType`, `amountVariability REAL`, `detectionSource ENUM('heuristic','ai') DEFAULT 'heuristic'`, `aiReason TEXT`, `aiFingerprint STRING(64)` and `nextExpectedDate DATEONLY`. Backfill `merchantKey` from `suggestedName`.

**Accepting a candidate** with `subscriptionId` (`resolve-candidate.ts`) now also triggers `backfillSubscriptionMatches`. Quick-add from a candidate (web `quick-add-subscription-dialog.vue`, iOS `RecurringQuickAddSheet`) pre-fills `payeeId` when the cluster key is a payee. No rules are auto-created, because the scorer no longer needs them.

### 2.4 Planned-budgets fix

1. **Project every active recurring payment** (fixes P1 and P2). In `controllers/future-budgets/future-budgets.ts:230-241`:
   - Delete `realBankRecurringTransactionsInclude` and its `required: true` include. Check `future-budgets.unit.ts` for references.
   - Load `Subscriptions.findAll({ where: { userId, isActive: true } })`.
   - Skip a subscription only when its `endDate < plan.startDate` or when no amount can be determined.
   - The amount is `override.amount ?? expectedAmount ?? median(last 3 active linked amounts)`. Compute it with one grouped query over `SubscriptionTransactions` and `Transactions`.
   - Respect `maxOccurrences` (installments) by not projecting beyond the remaining count.
   - Replace the comment at 235-236.
2. **Reconcile actual vs. planned** (fixes P3).
   - Amend unmerged migration `20260827000000-add-auto-add-synced-transactions-to-future-budget-plans.ts` (rule 11; it is not on `origin/dev`). Add these to `FutureBudgetEntries`:
     - `transactionId UUID NULL` (FK `Transactions`, ON DELETE CASCADE).
     - `subscriptionId UUID NULL` (FK `Subscriptions`, ON DELETE SET NULL).
     - A partial unique index `(planId, transactionId) WHERE transactionId IS NOT NULL`.
   - Update `models/future-budget-entries.model.ts`.
   - The user must undo and redo that migration locally. Note this in the PR.
   - In `getPlanDetails`, for each subscription S, take the auto-added entries with `subscriptionId = S`. Remove the projected occurrence of S nearest each entry's date, within W (§2.1 windows), and emit the entry as `source: 'recurring_actual'` with `subscriptionId` and `name`. Projected occurrences that aren't removed stay as `source: 'recurring'`. Entries without a subscription stay `source: 'manual'`. Totals therefore count each payment once.
3. **A single idempotent sync service** (fixes P3 and P4). It lives in new `services/future-budgets/sync-plan-entries.ts` and replaces `auto-add-synced-transaction.ts`; delete the old file and update its e2e:
   ```ts
   syncPlanEntriesForTransactions({ userId, transactionIds }): Promise<void>
   ```

   - For each real (non-planned, non-two-leg-transfer) tx, find the active plans where `autoAddSyncedTransactions` is on and the date range covers `tx.time`.
   - Upsert the entry on `(planId, transactionId)` with the current amount, date, category, note, type and active `subscriptionId` (or null).
   - Delete entries for plans that no longer cover the tx.
   - Callers:
     - `create-transaction.ts:748-768`: the existing `autoAddSyncedTransaction` call becomes `syncPlanEntriesForTransactions`.
     - Every link-state change in §2.1 and §2.2: matching auto-link, the link endpoint, the unlink endpoints, mark-paid LINK and CREATE, and `resolve-candidate.ts`.
     - The update-transaction service, after commit, when amount, time, category, note or type changes.
   - Delete is handled by the FK cascade.
4. **Backfill on toggle.** In `updatePlan` (`future-budgets.ts:~186`), when `autoAddSyncedTransactions` flips false to true, call `backfillPlanEntries({ userId, planId })`. It selects the user's real transactions with `time` in `[startDate, endDate]` and syncs them, capped at 5,000. When it flips true to false, leave the entries in place (they are now user data). The web copy at `packages/frontend/src/pages/planned/future-budgets/details.vue:348-352` changes to "Automatically add real transactions in this window, including ones matched to recurring payments", via i18n.
5. **Web and iOS plan views**: render `recurring_actual` with a "Paid" state next to projected recurring rows (web `details.vue`; iOS `MoneyMatterKit/Planning/PlannedBudgets.swift` occurrence `source` decoding plus its view).

---

## 3. Test plan

Follow the CLAUDE.md test-first workflow:

- Write each **bug reproduction first**. It must fail on the current code.
- Tests are **HTTP-only**, through `src/tests/helpers`. Use the `e2e-test-creator` skill conventions.
- Run tests through the `test-runner` subagent with `npm run test:e2e -- --testPathPattern=...`, and never in parallel.

### 3.1 Bug reproductions (should fail before the fix)

**`services/subscriptions/smart-matching.e2e.ts`**

1. _Auto-links a transaction to a manually created recurring payment with no rules._
   - Setup: `helpers.createPayee` 'Netflix'. `createSubscription` with `{ name: 'Netflix', payeeId, expectedAmount: 15.49, expectedCurrencyCode, frequency: monthly, dueDate: today }`. `createTransaction` with that `payeeId`, amount 17.99, time today.
   - Expect: `getSubscriptionById(...).linkedTransactionsCount === 1`, and the link has a non-null `matchScore`. Fails today (R1).
2. _Suggestions are returned for a subscription without matching rules._
   - Setup: tx note `NETFLIX.COM 8822 AMSTERDAM`, subscription name 'Netflix'.
   - Expect: `getSuggestedMatches` (legacy route) contains the tx. Fails today: `[]` (R7).
3. _An amount mismatch doesn't hide a same-merchant transaction._
   - Setup: subscription 'Spotify', expectedAmount 10, no rules. Tx 'Spotify P1234' for 13.
   - Expect: it appears in suggestions. Fails today.
4. _A transaction on another account is still suggested after mark-paid scoped the subscription to an account._
   - Setup: `markSubscriptionPeriodPaid` with `accountId: A`, `createTransaction: true`. Then a matching-name tx on account B.
   - Expect: it appears in suggestions. Fails today (R3).
5. _Mark-paid with `createTransaction` links the booked transaction._
   - Expect: `linkedTransactionsCount === 1`. Fails today (R5).
6. _Creating a subscription backfills existing history._
   - Setup: 3 monthly 'GYMCO 4411' transactions at −60, −30 and 0 days. Then create subscription 'Gymco' with a monthly `dueDate` aligned to them.
   - Expect: the recent ones are linked, or suggested when below the threshold, and the open period is paid. Fails today (R6).

**`services/future-budgets/auto-add-recurring.e2e.ts`**

1. _Projects a manually created recurring payment._
   - Setup: plan for today −5 to +40 days. Manual subscription, expectedAmount 50, monthly, dueDate in the window.
   - Expect: `getFutureBudgetPlan` occurrences include `source: 'recurring'` with that `subscriptionId`. Fails today (P1).
2. _Auto-add records a mark-paid transaction as the recurring actual, not as a duplicate manual entry._
   - Setup: auto-add on, then `markSubscriptionPeriodPaid({ createTransaction: true })`.
   - Expect: exactly one occurrence for that payment, with `source: 'recurring_actual'`. Summary expense equals 50, not 100. Fails today (P3).
3. _Turning auto-add on backfills in-window transactions._ Fails today (P4).
4. _Deleting a linked transaction removes its plan entry, and unlinking turns `recurring_actual` back into `manual`._

### 3.2 New-feature tests

**`services/subscriptions/suggestions-api.e2e.ts`**

- `GET /suggestions`:
  - happy path: ranking order is payee-match plus near-date above note-similar plus far-date, and the reason codes are present;
  - empty state: no transactions returns `{ suggestions: [], dismissedCount: 0 }`;
  - errors: 404 for another user's subscription, 400 for an invalid id.
- `GET /linkable-transactions`:
  - happy path: search by note and by payee name finds rows regardless of amount or account. Date and `accountIds` filters, paging and `hasMore` work. The `linkedSubscription` annotation is present.
  - empty state;
  - errors: 400 for `from > to`, 400 for `limit > 100`, 404.
- `POST /suggestions/dismiss`:
  - a dismissed row disappears from suggestions, and a subscription update (which triggers backfill) doesn't auto-link it;
  - linking via `POST /:id/transactions` clears the dismissal;
  - errors: 404 for a foreign transaction id, 400 for an empty array.
- Tiering:
  - an ambiguous tx (two subscriptions within 0.05) is suggested for both and linked to neither;
  - a `different_account` cap is suggested but not auto-linked;
  - an explicit amount rule still blocks a payee-matched tx outside the range (gate preserved);
  - the period-already-covered cap.
- `pendingSuggestionsCount` on list and detail.

**Discovery: extend `services/subscriptions/detect-candidates.e2e.ts`**

- Merchant strings with varying suffixes cluster into one candidate.
- The same merchant on two accounts yields one candidate.
- A utility bill varying ±25% monthly is detected.
- One missed month is still detected as monthly.
- An annual charge with 2 occurrences 365 ± 5 days apart is detected.
- An income cluster is detected with `transactionType: income`.
- A cluster matching an existing manual subscription creates **suggestions, not a candidate**.
- Empty state: no transactions.

**`services/subscriptions/detect-candidates-ai.e2e.ts`**

- Setup: `useSelfHostWithoutServerAiKeys()`. Configure a user Gemini key (as the categorization e2e tests do). Add a JSON-capable helper to `tests/mocks/gemini/mock-api.ts`, `createGeminiJsonMock({ json })`.
- Cases:
  - AI names and accepts an ambiguous cluster: `detectionSource: 'ai'`, the AI name, `aiStatus: 'applied'`;
  - AI rejects a cluster: it is dropped;
  - provider 500: heuristics are returned with `aiStatus: 'failed'`;
  - no AI configured: `aiStatus: 'skipped'` and no outbound request (the msw handler is never hit);
  - an unchanged fingerprint is not re-sent on the next run after the cooldown.

**Unit tests** (pure functions; run via the npm unit script):

- `matching/merchant-key.unit.ts`
- `matching/score-transaction.unit.ts`: weights, gates, caps and the worked examples in §2.1.
- `matching/expected-dates.unit.ts`
- `discovery/detect-cadence.unit.ts`
- `discovery/amount-profile.unit.ts`

**Regression**: `matching-disambiguation.e2e.ts`, `subscriptions.e2e.ts`, `subscription-mark-paid.e2e.ts`, `subscription-period-actions.e2e.ts`, `subscription-auto-record.e2e.ts`, `future-budgets/*.e2e.ts` and `ai-categorization/*.e2e.ts` must stay green.

- Expected intentional diffs: mark-paid now creates links; auto-link may mark periods paid.
- Update the assertions in those tests only where they encode the old buggy behaviour, and call those changes out in the PR.

---

## 4. Work split (parallel agents, disjoint file ownership)

**Foundation (Chunk A, first commit, merged before B, C and D start; about 1 hour):**

- `packages/shared/src/types/subscriptions-matching.ts`: `MatchReason`, the reason-code union, the suggestion and linkable DTOs, plus the candidate field additions. Export it from the shared index.
- `AI_FEATURE.recurringDetection` in `packages/shared/src/types/enums.ts`.
- Migrations `20261010000000-subscription-smart-matching.ts` and `20261010000001-extend-subscription-candidates.ts`; model `subscription-match-suggestions.model.ts`; new columns on `subscription-transactions.model.ts` and `subscription-candidates.model.ts`.
- The amended migration `20260827000000-...` and `future-budget-entries.model.ts` columns.
- `services/subscriptions/matching/merchant-key.ts` and its unit test.
- A **stub** `services/future-budgets/sync-plan-entries.ts` exporting `syncPlanEntriesForTransactions({ userId, transactionIds })` (a no-op).
- Route stubs in `routes/subscriptions.route.ts`.

| Chunk                                                | Owner                          | Files owned (exclusive)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Depends on                                                                                                                                                                                                                                                                                 |
| ---------------------------------------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **A. Matching engine plus linking API** (backend)    | agent 1                        | `services/subscriptions/matching/**`; `matching-engine.ts` (wrapper); `suggest-historical-matches.ts`; `link-transactions.ts`; `unlink-transactions.ts`; `mark-period-paid.ts`; `revert-period.ts`; `create-subscription.ts`, `update-subscription.ts`, `toggle-active.ts`, `resolve-candidate.ts` (backfill trigger lines only); `event-listeners.ts`; `get-subscriptions.ts` (`pendingSuggestionsCount`, `matchScore`); new `controllers/subscriptions/{get-suggestions,search-linkable-transactions,dismiss-suggestions}.ts`; `routes/subscriptions.route.ts`; the update-transaction service hook (the re-match call only); `tests/helpers/subscriptions.ts` (new helpers `getSubscriptionSuggestions`, `searchLinkableTransactions`, `dismissSubscriptionSuggestions`); `smart-matching.e2e.ts`; `suggestions-api.e2e.ts`; scorer unit tests                                        | Foundation                                                                                                                                                                                                                                                                                 |
| **B. Discovery heuristics plus AI review** (backend) | agent 2                        | `detect-candidates.ts`; `detect-candidates-utils.ts` (+unit); new `services/subscriptions/discovery/**`; `serialize-candidate.ts`; `controllers/subscriptions/detect-candidates.ts` (`aiStatus`); `services/ai/models-config/recommendations.ts`; `packages/frontend/src/common/const/ai-features.ts`; `tests/mocks/gemini/mock-api.ts` (additive); `detect-candidates.e2e.ts`; `detect-candidates-ai.e2e.ts`                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Foundation. It _imports_ A's `score-transaction.ts` and `subscription-profile.ts` for existing-subscription routing; until A lands, B stubs the routing step behind an interface `routeClustersToExisting({ userId, clusters })` located in `discovery/route-to-existing.ts` (owned by B). |
| **C. Planned-budgets fix** (backend)                 | agent 3                        | `controllers/future-budgets/future-budgets.ts` (+unit); `services/future-budgets/**` (implements `sync-plan-entries.ts`, `backfill-plan-entries.ts`, removes `auto-add-synced-transaction.ts`); `create-transaction.ts` lines 748-768 only; the update-transaction service hook (the plan-sync call only; coordinate the one-line hunk with A); `tests/helpers/future-budgets.ts`; `future-budgets/auto-add-recurring.e2e.ts`; the existing `auto-add-synced-transaction.e2e.ts` (updated)                                                                                                                                                                                                                                                                                                                                                                                               | Foundation (columns plus the stub signature)                                                                                                                                                                                                                                               |
| **D. Web plus iOS UI**                               | agent 4 (or 4a web and 4b iOS) | Web: `packages/frontend/src/api/subscriptions.ts`, `api/future-budgets.ts`; `pages/planned/subscriptions/subscription-details.vue`; new `components/link-transactions-dialog.vue` and `match-reason-chips.vue`; `linked-transactions-section.vue`; `subscription-list-item.vue`; `subscription-mark-paid-dialog.vue`; `discover-candidates-dialog.vue` and `candidate-card.vue` (AI badge, `aiReason`, "suggested links for existing payments" section); `pages/planned/future-budgets/details.vue`; i18n via the `i18n-editor` subagent (en and uk). iOS: `MoneyMatterKit/.../Planning/RecurringEndpoints.swift`, `RecurringModels.swift`, `PlannedBudgets.swift`; `MoneyMatter/Features/Planning/Recurring/RecurringPaymentSheets.swift`, `RecurringPaymentDetailScreen.swift`, `RecurringPaymentsSegmentView.swift`; the planned-budget detail view; `MoneyMatterKitTests/Planning/*` | Foundation shared types; codes against the contracts in §2.2 and §2.3 with msw or fixtures until A, B and C land                                                                                                                                                                           |

Integration order:

1. Foundation.
2. A, B, C and D in parallel.
3. Run the full e2e suite once, sequentially, through `test-runner`.
4. Run `linter` on backend and frontend, and run the iOS build and tests.

Conflict hot spots to coordinate:

- `create-transaction.ts`: A touches nothing there (the wrapper name is unchanged); C edits only 748-768.
- The update-transaction service: A and C each add one call after commit, so land A first and C rebases.
- `routes/subscriptions.route.ts`: owned by A; B touches only its controller.
