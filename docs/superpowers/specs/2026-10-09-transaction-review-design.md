# Transaction Review Design

## Purpose

Transaction Review lets a user confirm recent bank-synced and imported transactions one at a time, so they spot charges they do not recognize. Each transaction can be marked **Looks good**, **Check later**, or **Fraud**. A dedicated page lists reviewed, unreviewed, and fraud transactions.

Review status is a label. It never changes balances, statistics, budgets, or bank matching. A fraud charge stays in every total until the bank refunds it.

This is sub-project A of the native iOS effort. It ships on the server and web first and defines the API the iOS app consumes later. See [Roadmap](#roadmap).

## Scope

- A review status on every transaction, set automatically on creation.
- A one-time backfill of the last 30 days.
- Three API endpoints: summary counts, tab listing, and bulk status update.
- Web: a dashboard card, a review card stack, a review page with three tabs, a sidebar item with a count badge, and a fraud chip on transaction rows.

The first version does not send notifications, restrict status changes to particular transactions, add a review filter to `GET /transactions`, or add review status to data export. Transactions on accounts shared with the user never enter the user's queue.

## Review status

`Transactions.reviewStatus` takes one of four values. They come from the shared enum `TRANSACTION_REVIEW_STATUS` in `packages/shared`:

| Value          | Meaning                                                                  |
| -------------- | ------------------------------------------------------------------------ |
| `not_required` | Never entered review: manual, planned, or older than the backfill window |
| `unreviewed`   | Waiting for review, including rows deferred with Check later             |
| `reviewed`     | User confirmed it                                                        |
| `fraud`        | User flagged it as not theirs                                            |

`not_required` keeps the Reviewed tab limited to transactions the user actually reviewed.

### Initial status on create

`createTransaction` in `transactions.model.ts` is the single creation path. A non-planned row whose `time` falls within the last 30 days is set to `unreviewed` if either of these holds:

- it was synced, meaning `accountType !== ACCOUNT_TYPES.system`;
- it was imported, meaning `externalData.importDetails` is present.

The 30-day window matches the backfill, so connecting a bank or importing years of history only queues recent activity.

Every other row gets `not_required`. That includes manual entries, MCP-created rows, subscription auto-records, transfer legs the user creates, and planned rows.

A planned row that a bank sync later merges into keeps `not_required`, because the user created the plan.

Editing a transaction's amount, category, or other fields never changes its review status.

### Actions

| Action        | Resulting `reviewStatus` | `reviewDeferredAt` |
| ------------- | ------------------------ | ------------------ |
| `reviewed`    | `reviewed`               | `null`             |
| `fraud`       | `fraud`                  | `null`             |
| `check_later` | `unreviewed`             | now                |
| `unreviewed`  | `unreviewed`             | `null`             |

Any transaction the user owns accepts any action. The `unreviewed` action covers undo and moving rows back from the Reviewed or Fraud tabs.

### Queue order

The Unreviewed tab and the card stack sort the same way:

1. Rows that were never deferred (`reviewDeferredAt IS NULL`), oldest transaction `time` first.
2. Deferred rows, earliest `reviewDeferredAt` first.

A deferred row therefore waits behind every fresh row. The Reviewed and Fraud tabs sort by `time`, newest first.

## Data model

One new migration, `20261009000000-add-review-status-to-transactions.ts`, runs inside a manual `queryInterface.sequelize.transaction()` with `up` and `down`. It:

1. Adds `Transactions.reviewStatus` as `VARCHAR(20)` NOT NULL with default `'not_required'`. It is VARCHAR plus a TypeScript-side enum, following the project convention of no DB enums.
2. Adds `Transactions.reviewDeferredAt` as a nullable `TIMESTAMPTZ`.
3. Adds a partial index on `("userId", "reviewDeferredAt", "time") WHERE "reviewStatus" = 'unreviewed'`.
4. Backfills: sets `reviewStatus = 'unreviewed'` where `"isPlanned" = false` and `"time" >= now() - interval '30 days'`, and either `"accountType" <> 'system'` or `"externalData" ? 'importDetails'`.
5. Re-runs `createRealTransactionsViewSql`. The `real_transactions` view is `SELECT *`, and Postgres fixes a view's column list when the view is created.

`down` drops the view, both columns, and the index, then recreates the view.

The model declares both columns, with `defaultValue: 'not_required'` on `reviewStatus`, because backup restore rejects an archive that omits a NOT NULL column unless the model supplies a default. `TransactionModel` in the shared types gains both fields, and the transaction serializer outputs them.

## APIs

The routes live in `routes/transactions.route.ts` and must be registered above `/:id`. Each one follows route, then controller via `createController`, then service. The services are in `services/transactions/review/`.

### `GET /api/v1/transactions/review/summary`

Returns `{ unreviewedCount: number, fraudCount: number }` for the current user's own transactions.

### `GET /api/v1/transactions/review`

| Query    | Rule                                           |
| -------- | ---------------------------------------------- |
| `status` | Required: `unreviewed`, `reviewed`, or `fraud` |
| `limit`  | Optional, default 50, max 100                  |
| `offset` | Optional, default 0                            |

Returns an array of transactions from the same serializer as `GET /transactions`, in the order given in [Queue order](#queue-order).

### `PUT /api/v1/transactions/review`

| Body             | Rule                                                       |
| ---------------- | ---------------------------------------------------------- |
| `transactionIds` | Required, 1 to 100 unique record IDs                       |
| `action`         | Required: `reviewed`, `check_later`, `fraud`, `unreviewed` |

The service is wrapped in `withTransaction` and applies the [Actions](#actions) table to every ID atomically. It returns `{ updatedCount }`.

## Navigation and UI

### Dashboard card

`pages/dashboard/components/review-transactions-card.vue` renders directly below `RecoveryMethodBanner` on the dashboard. It renders only when `unreviewedCount > 0`, and never in the no-accounts onboarding state.

The card shows:

- a shield icon;
- **"{count} transactions to review"**, pluralized through i18n;
- the subtitle "Check recent bank transactions for anything you don't recognize";
- a **Review** button that opens the review stack;
- when `fraudCount > 0`, a link **"{count} marked as fraud"** that opens the review page on the Fraud tab.

The layout uses container queries.

### Review stack

The stack is a `ResponsiveDialog`, so it shows as a drawer on mobile and a centered dialog on desktop.

- **Header:** progress **"{n} of {total}"**, an **Undo** button, and close.
- **Card:** payee name (or note when there is no payee), amount in the income or expense color, account name, date and time, and category.
- **Buttons:** **Fraud** (`soft-destructive`), **Check later** (`outline`), **Looks good** (`default`).
- **Desktop keys:** `→` or `Enter` for Looks good, `←` for Check later, `F` for Fraud, `⌘Z`/`Ctrl+Z` for Undo. Keys are ignored while focus is inside a text input.

Session behaviour is a pure state module, `use-review-session.ts`:

- The stack loads the unreviewed queue 50 at a time and requests the next page before the user reaches the end.
- An action advances to the next card immediately and sends `PUT /transactions/review` in the background. On failure the card returns to the front and an error toast appears.
- Undo pops the session's action stack and sends the inverse action. A row that was deferred before the session started returns as plain `unreviewed`.
- Rows deferred during the session do not reappear in it. The finished state shows "All caught up", plus "{count} saved for later" when any were deferred.

### Review page

The page lives at `/transactions/review`, under the route constant `ROUTES_NAMES.transactionsReview`. The sidebar's Transactions group gains a **Review** item that shows `unreviewedCount` as a badge when it is greater than 0.

- **Header:** the title and a **Start review** button, which is disabled when nothing is unreviewed.
- **Tabs:** **Unreviewed ({count})**, **Reviewed**, and **Fraud ({count})**. The selected tab is kept in the URL query so the dashboard can link straight to Fraud.
- **Rows:** the existing `TransactionRecord`, with infinite scroll. Clicking a row opens the existing transaction details modal.
- **Row actions:**

  | Tab        | Actions                                         |
  | ---------- | ----------------------------------------------- |
  | Unreviewed | Looks good, Fraud                               |
  | Reviewed   | Mark as fraud, Move to unreviewed               |
  | Fraud      | Not fraud (sets `reviewed`), Move to unreviewed |

- **States:** each tab has an empty state (icon, title, description) and skeleton rows while loading.

### Fraud chip

A new `components/transactions-list/indicators/fraud-indicator.vue` renders inside `TransactionRecord` when `reviewStatus === 'fraud'`. It uses destructive tokens and follows the frontend rules for text and fill colours. It appears wherever `TransactionRecord` is used.

### Data flow

- **API functions:** in `src/api/`.
- **Query keys:** in `VUE_QUERY_CACHE_KEYS`. The summary and tab queries are invalidated whenever transaction data changes, which covers syncs and imports.
- **Mutations:** card and row actions update optimistically and invalidate the summary, the review tabs, and transaction lists.
- **Toasts:** row actions show success and error toasts. Card actions show only error toasts; the card advancing is the confirmation, and a toast on every swipe would be noise.
- **i18n:** new strings are added to `en` and translated into `uk` through the `i18n-editor` subagent.

## Error handling and permissions

All endpoints use `authenticateSession`. A user can only read or change review status on transactions where `userId` is their own.

| Case                                                  | Result                                 |
| ----------------------------------------------------- | -------------------------------------- |
| Missing or invalid `status`                           | Validation error                       |
| `transactionIds` empty, over 100, or duplicated       | Validation error                       |
| Unknown `action`                                      | Validation error                       |
| Any ID that does not exist or belongs to another user | `NotFoundError`, and no row is updated |

Error messages use i18n keys, following the backend conventions.

## Testing

Backend e2e tests live in `services/transactions/review/review.e2e.ts` and call only HTTP endpoints through test helpers:

- **Empty state:** a manual transaction is `not_required`. The queue is empty and both counts are 0.
- **Entering the queue:**
  - A transaction synced through the Monobank mock helper is `unreviewed` and counted.
  - So is one created through the CSV import helper.
  - A planned transaction is not.
- **Ordering:**
  - The oldest transaction comes first.
  - `check_later` moves a row behind fresh rows.
  - Several deferred rows keep their deferral order.
- **Transitions:**
  - Each action moves the row to the correct tab and updates both counts.
  - `reviewDeferredAt` follows the Actions table.
  - `GET /transactions/:id` returns `reviewStatus`.
- **Errors:** every case in the error table above. A batch that includes another user's ID leaves all rows unchanged.

Run the tests with `npm run test:e2e -- --testPathPattern='transactions/review'` through the `test-runner` subagent.

Frontend unit tests cover `use-review-session.ts`: advance, defer, undo, failure rollback, and the saved-for-later tally.

The migration's backfill has no automated test, because e2e databases start empty. It is verified by running the migration against the Docker dev database and comparing the number of `unreviewed` rows with a manual count query.

Final verification:

- the `linter` subagent runs oxlint, tsc, and vue-tsc;
- e2e and unit tests;
- a manual pass in Brave on the dev server covering the dashboard card, the keyboard flow, undo, the three tabs, and the fraud chip in the normal transaction list.

## Acceptance criteria

1. Bank sync and file import create `unreviewed` transactions. Manual, planned, and MCP-created transactions are `not_required`.
2. The migration marks the last 30 days of synced and imported transactions `unreviewed` and leaves older rows `not_required`.
3. The dashboard shows "{count} transactions to review" only when the count is above 0.
4. Looks good, Check later, and Fraud persist. A Check later row returns at the back of the queue in the next session.
5. Undo reverts the last action in the session, repeatedly.
6. The review page tabs show the correct rows and counts. Rows can move between tabs.
7. Fraud transactions show a chip in every transaction list and still count in balances and statistics.
8. The sidebar shows a Review item with an unreviewed count badge.
9. All new e2e tests, unit tests, lint, and type checks pass.

## Roadmap

Transaction Review is sub-project A. The native iOS app follows as separate sub-projects. Each gets its own spec, plan, and implementation:

| Sub-project                          | Contents                                                                                                                                                                                                                                                                                                                                                        |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **B. iOS foundation and core**       | Xcode project at top-level `ios/` with SwiftUI on iOS 26+. better-auth `bearer()` plugin for native sessions. Configurable server URL. Email/password, Google/GitHub through `ASWebAuthenticationSession`, and passkeys. Tab shell, dashboard, accounts, transactions list and create/edit. The iOS review stack (swipe gestures plus buttons) and review page. |
| **C. iOS planning and organization** | Budgets, planned budgets, recurring payments, categories, tags, payees, currencies, account and transaction groups, automations.                                                                                                                                                                                                                                |
| **D. iOS analytics and assets**      | Analytics on Swift Charts, loans, investments, venture, vehicles.                                                                                                                                                                                                                                                                                               |
| **E. iOS integrations and settings** | Bank connections and sync, notifications, sharing and households, security settings, AI features, imports and export, optimizations.                                                                                                                                                                                                                            |

Decisions already made for the iOS app:

- personal use only;
- configurable server URL;
- iOS 26 minimum;
- the review stack uses cards with swipe gestures and visible buttons.

Still open, to settle in sub-project B: which web-only features (admin, import wizards, AI key management, billing, pivot report) stay off iOS.
