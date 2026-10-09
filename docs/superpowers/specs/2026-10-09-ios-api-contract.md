# iOS API Contract (`/api/v1`)

Reference for the native iOS client. Derived from the backend controllers, serializers, and `packages/shared/src/types` on 2026-10-09. When this document and the code disagree, the code wins.

## Conventions

- **Success:** 200 `{status:'success', response:<data>}`. Handlers with no data return `{status:'success'}` with no `response` key. `POST /user/currencies/change-base` returns 202.
- **Missing resource:** `GET /accounts/:id`, `GET /transactions/:id`, and `GET /user/currencies/base` return 200 with `response: null`, not 404.
- **Error:** `{status:'error', response:{message, code, details?}}`.
- **Validation error:** 422, `{message, validationErrors: ZodIssue[], code:'VALIDATION_ERROR'}` under `response`.
- **Status codes the client must handle globally:**

  | Status | Code / meaning                                                                    |
  | ------ | --------------------------------------------------------------------------------- |
  | 401    | `UNAUTHENTICATED`                                                                 |
  | 402    | `PLAN_REQUIRED`: a lapsed trial blocks most writes                                |
  | 403    | `FORBIDDEN`                                                                       |
  | 404    | `NOT_FOUND`                                                                       |
  | 409    | `CONFLICT`                                                                        |
  | 423    | `BASE_CURRENCY_CHANGE_IN_PROGRESS`: mutating routes during a base-currency change |
  | 429    | Too many requests                                                                 |
  | 500    | `UNEXPECTED`                                                                      |
  | 503    | `SERVICE_UNAVAILABLE`                                                             |

- **better-auth errors:** routes under `/auth/*` use better-auth's own `{code, message}` body with no envelope.
- **Money:** JSON numbers in decimals (`15.5`), never strings and never cents. Decode as `Decimal`.
- **IDs:** UUID strings. `userId` and `User.id` are integers.
- **Timestamps:** ISO-8601 with milliseconds and `Z`. Date-only fields are `YYYY-MM-DD`.
- **Request dates:**
  - `/transactions` `from`/`to` and body `time`: ISO datetime in UTC `Z`. Offsets are rejected.
  - `/stats/*` `from`/`to`: `YYYY-MM-DD`.
- **Query lists:** comma-separated (`a,b,c`).
  - Transactions-list ID params are strict: one invalid UUID returns 422.
  - `/stats/*` silently drops invalid IDs.
- **Booleans:** `true`/`false`/`1`/`0`. On `GET /account-group?includeArchived` and `GET /categories?includeAccessible`, the server uses `z.coerce.boolean()`, so the string `"false"` becomes true. Omit those params instead of sending `false`.
- **Headers:**
  - `Accept-Language` sets the locale for messages and for the default categories seeded on sign-up.
  - `Content-Type: application/json`.

## Auth

better-auth is mounted at `/auth/*`.

| Call                                                           | Notes                                                                                                                                                              |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /auth/sign-in/email` `{email,password}`                  | Starts a session.                                                                                                                                                  |
| `POST /auth/sign-up/email` `{email,password,name,callbackURL}` | `callbackURL` must be a trusted origin. Creates the app user and seeds default categories and tags. Requires email verification only when `RESEND_API_KEY` is set. |
| `GET /auth/get-session`                                        | Session check.                                                                                                                                                     |
| `POST /auth/sign-out`                                          | Ends the session.                                                                                                                                                  |
| `GET /auth/signups-open`                                       | `{signupsOpen:boolean}`, no auth.                                                                                                                                  |

- **Origin check:** better-auth rejects mutating `/auth/*` requests that carry a `Cookie` header but no matching `Origin` or `Referer`. The error is 403 `MISSING_OR_NULL_ORIGIN`, or `INVALID_ORIGIN` for a wrong value.
- **Session:** lasts 7 days and refreshes daily.
- **Native client auth (bearer tokens, OAuth, passkeys):** defined in the sub-project B spec.

## User and onboarding

| Endpoint                     | Params                                                                                                 | Response                                                                                                                                                                                                                                       |
| ---------------------------- | ------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /user`                  | none                                                                                                   | `{id:int, username, firstName, lastName, middleName, avatar, totalBalance, defaultCategoryId, authUserId, role, createdAt, plan, trialEndsAt, email, isAdmin, entitlements:{features[], readOnly, seats, plan, trialEndsAt, subscriptions[]}}` |
| `PUT /user/update`           | any of `username` (`[a-z0-9-]`, 1–64), `firstName`, `lastName`, `middleName`, `avatar`, `totalBalance` | user row                                                                                                                                                                                                                                       |
| `GET /user/settings`         | none                                                                                                   | settings, with defaults merged in (see below)                                                                                                                                                                                                  |
| `PATCH /user/settings`       | partial settings; arrays replace wholesale                                                             | merged settings                                                                                                                                                                                                                                |
| `GET /models/currencies`     | none (no auth)                                                                                         | `[{code, currency, digits, number, isDisabled}]`                                                                                                                                                                                               |
| `GET /user/currencies`       | none                                                                                                   | `UserCurrency[]`                                                                                                                                                                                                                               |
| `GET /user/currencies/base`  | none                                                                                                   | `UserCurrency` or `null`                                                                                                                                                                                                                       |
| `POST /user/currencies/base` | `{currencyCode}`                                                                                       | `UserCurrency`; 422 if a base currency already exists                                                                                                                                                                                          |
| `POST /user/currencies`      | `{currencies:[{currencyCode, exchangeRate?, liveRateUpdate?}]}`                                        | `{currencies, alreadyExistingCodes}`                                                                                                                                                                                                           |

`UserCurrency` = `{id, userId, currencyCode, exchangeRate|null, liveRateUpdate, isDefaultCurrency, currency:{code,currency,digits,number,isDisabled}}`.

Settings keys:

- `locale`
- `dashboard.widgets: [{widgetId, colSpan, rowSpan, config?}]`
- `includeCreditLimitInStats`
- `hideZeroBalances`
- `currencyDisplay`
- `accounts.defaultAccountId`

If `dashboard.widgets` is empty, the default layout is `balance-trend`, `latest-records`, `subscriptions-overview`, `spending-categories`.

**Onboarding:** `GET /user/currencies/base` returning `null` means the user still needs onboarding. Show base-currency selection, then `POST /user/currencies/base`. The backend does not block other routes when there is no base currency, so the client must.

## Accounts

| Endpoint                              | Notes                                                                                                                                                                                                            |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /accounts`                       | Owned and shared accounts, active and archived.                                                                                                                                                                  |
| `GET /accounts/:id`                   | Returns `null` if missing.                                                                                                                                                                                       |
| `POST /accounts`                      | Required: `currencyCode`, `name`. Optional: `accountCategory` (default `general`), `initialBalance`, `creditLimit`, `logoDomain` / `logoInitials` (mutually exclusive), `logoColor`.                             |
| `PUT /accounts/:id`                   | Optional: `name`, `accountCategory`, `creditLimit`, `status:'active'\|'archived'`, `excludeFromStats`, `currentBalance` (system accounts only), logo fields.                                                     |
| `DELETE /accounts/:id`                | Hard delete.                                                                                                                                                                                                     |
| `GET /accounts/:id/transaction-count` | `{transactionCount}`.                                                                                                                                                                                            |
| `GET /account-group`                  | Flat list of all groups; child groups also appear nested. Each group: `{id, name, parentGroupId, accounts:Account[], childGroups:[…]}`. Roots have `parentGroupId == null`. Shared accounts are never in groups. |

**Account fields:**

- `id`, `name`
- Balances: `initialBalance`, `refInitialBalance`, `currentBalance`, `refCurrentBalance`, `creditLimit`, `refCreditLimit`. The `ref*` fields are in the base currency.
- `type`: `system|monobank|enable-banking|lunchflow|walutomat|simplefin`
- `accountCategory`: `general|cash|current-account|credit-card|saving|bonus|insurance|investment|loan|overdraft|crypto|vehicle`
- `currencyCode`, `status`, `excludeFromStats`
- Bank link: `bankDataProviderConnectionId|null`, `bankProviderType|null`, `needsRelink?`
- Logo: `logoDomain`, `logoInitials`, `logoColor`
- Sharing: `share?:{isOwner, owner, permission, accessSource}`

## Transactions

### `GET /transactions`

All params are optional.

| Param                                                                                                | Notes                                                                         |
| ---------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `limit`                                                                                              | Default 20, no maximum.                                                       |
| `offset`                                                                                             | Default 0.                                                                    |
| `order`                                                                                              | `ASC\|DESC`.                                                                  |
| `sortBy`                                                                                             | `time\|refAmount\|accountName\|categoryName\|payeeName\|categorizationSource` |
| `from`, `to`                                                                                         | ISO UTC.                                                                      |
| `transactionType`                                                                                    | `income\|expense`                                                             |
| `accountIds`, `excludeAccountIds`, `categoryIds`, `budgetIds`, `excludedBudgetIds`, `excludedTagIds` | Comma-separated UUIDs.                                                        |
| `tagIds`, `payeeIds`                                                                                 | Also accept the literal `blank`.                                              |
| `transferNatures`                                                                                    | Include-list; overrides `transferFilter`.                                     |
| `transferFilter`, `refundFilter`                                                                     | `all\|exclude\|only`                                                          |
| `excludeTransfer`, `excludeRefunds`, `excludeBalanceAdjustments`                                     | Booleans.                                                                     |
| `isPlanned`                                                                                          | Omitted: real and own planned rows. `true`: planned only. `false`: real only. |
| `hasAttachment`                                                                                      | Boolean.                                                                      |
| `amountGte`, `amountLte`                                                                             | Amount range.                                                                 |
| `noteSearch`                                                                                         | Comma-separated terms, ORed, case-insensitive substring.                      |
| `includeSplits`, `includeTags`, `includeGroups`, `includeHasAttachments`                             | Add optional fields to each row.                                              |

### Other read endpoints

- `GET /transactions/:id?includeSplits`: `Transaction & {canEdit}`, or `null`.
- `GET /transactions/by-ids?ids=a,b`
- `GET /transactions/transfer/:transferId`: both legs.

### Transaction fields

- Amounts: `id`, `amount`, `refAmount`, `commissionRate`, `refCommissionRate`, `cashbackAmount`, `originalAmount|null`, `originalCurrencyCode|null`
- Details: `note|null`, `externalUrl|null`, `externalReference|null`, `location:{latitude,longitude}|null`, `time`, `userId:int`
- `transactionType`
- `paymentType`: `bankTransfer|voucher|webPayment|cash|mobilePayment|creditCard|debitCard`
- Account and category: `accountId`, `categoryId|null`, `currencyCode`, `accountType`, `refCurrencyCode`
- `transferNature`: `not_transfer|transfer_between_user_accounts|transfer_out_wallet|transfer_to_portfolio|transfer_to_venture|transfer_to_loan`
- Linking: `transferId|null`, `originalId|null`, `refundLinked`
- Planned and review: `isPlanned`, `plannedMerge|null`, `reviewStatus`, `reviewDeferredAt|null`
- Payee and categorization: `payeeId|null`, `payeeLocked`, `categorizationMeta|null`
- Timestamps: `createdAt`, `updatedAt`
- Only with the matching include flag: `splits[{id, categoryId, amount, refAmount, note, category?}]`, `tags[{id,name,color,icon}]`, `transactionGroups[{id,name,transactionCount}]`, `hasAttachments`

### `POST /transactions`

Returns an **array**: `[tx]`, or `[baseLeg, oppositeLeg]` for a transfer.

**Required:**

- `amount`: number ≥ 0. Always positive; direction comes from `transactionType`.
- `transactionType`
- `paymentType`
- `accountId`
- `transferNature`: always required. Send `not_transfer` for a normal transaction.
- `categoryId`: required when `not_transfer`; omit for transfers.

**Optional:**

- `time`: ISO UTC, ≥ 2000-01-01. Defaults to now.
- `note`: ≤ 1000 characters.
- `externalUrl`, `externalReference`, `location`
- `commissionRate`
- `splits`: up to 10, `[{categoryId, amount, note}]`.
- `tagIds`: up to 20. Send `[]` to skip the payee's default tags.
- `payeeId`, `payeeLocked`
- `isPlanned`, `applyAutomations`
- `originalAmount` + `originalCurrencyCode`: sent together.
- `refundForTxId` / `refundForSplitId`

**Rules:**

- **Manual create:** non-planned rows can only be created on `type:'system'` accounts. Bank-connected accounts return 422 unless `isPlanned`.
- **Transfer between your accounts:** `transferNature:'transfer_between_user_accounts'`, `accountId` (source), `destinationAccountId`, and `destinationAmount` (in the destination currency; equals `amount` for a same-currency transfer). No `categoryId`.
  - The server stamps `transfer_to_loan` when the destination is a loan account.
  - Both legs share `transferId`. The opposite leg has the flipped `transactionType`.
  - Send the source leg as `expense`.
- **Out-of-wallet transfer:** `transferNature:'transfer_out_wallet'` with no destination fields.

### Write endpoints

- **`PUT /transactions/:id`:** same fields as create, all optional.
  - `null` clears `note`, `externalUrl`, `externalReference`, `location`, `splits`, `tagIds`, and `payeeId`.
  - `categoryId` cannot be null.
  - Returns an array.
- **`DELETE /transactions/:id`:** deleting either leg of a transfer deletes both. Returns `{status:'success'}`.

## Taxonomy

### Categories

| Endpoint                 | Notes                                                                                                                                                                                           |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /categories`        | Flat `[{id, name, color:'#rrggbb', icon\|null, key\|null, parentId\|null, type:'custom'\|'internal', userId}]`. Build the tree client-side. Decode leniently, because extra columns may appear. |
| `POST /categories`       | `{name, icon?, color? (required at root), parentId?}`                                                                                                                                           |
| `PUT /categories/:id`    | Update a category.                                                                                                                                                                              |
| `DELETE /categories/:id` | `{replaceWithCategoryId?}`. Returns 409 when the category has transactions and no replacement is given.                                                                                         |

### Tags

| Endpoint           | Notes                                                                |
| ------------------ | -------------------------------------------------------------------- |
| `GET /tags`        | `[{id, name, color, icon\|null, description\|null, remindersCount}]` |
| `POST /tags`       | `{name, color, icon?, description?}`                                 |
| `PUT /tags/:id`    | Update a tag.                                                        |
| `DELETE /tags/:id` | Delete a tag.                                                        |

### Payees

| Endpoint             | Notes                                                                                                                   |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `GET /payees`        | `q` (search; forces limit 20), `limit` 1..200 (default 50), `offset`, `sortBy`, `sortDir`. Returns payees with `stats`. |
| `GET /payees/lookup` | `[{id, name, logoDomain, logoInitials, logoColor}]`. Unpaginated; use it to resolve `payeeId` to a name.                |
| `POST /payees`       | Create a payee.                                                                                                         |
| `PATCH /payees/:id`  | Update a payee.                                                                                                         |
| `DELETE /payees/:id` | Delete a payee.                                                                                                         |

## Dashboard data

### Widget sources

| Widget                 | Calls                                                                                                                                                                                                                              |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| balance trend          | `GET /stats/combined-balance-history?from&to` (`YYYY-MM-DD`). Returns `[{date, accountsBalance, portfoliosBalance, venturesBalance, vehiclesBalance, loansBalance, totalBalance}]` in base currency; loans are negative.           |
| spending categories    | `GET /stats/spendings-by-categories?from&to&type=expense&excludePlanned`. Returns `{[categoryId]:{name, color, amount}}` with positive amounts. Also `GET /stats/expenses-amount-for-period?from&to`, which returns a bare number. |
| latest records         | `GET /transactions?limit=40&includeSplits=true&includeTags=true&to=<now>&transferNatures=<all except transfer_out_wallet>`. The client drops rows dated in the future.                                                             |
| subscriptions overview | `GET /subscriptions/summary`, `GET /subscriptions/upcoming?limit=5`, `GET /subscriptions?isActive=true`                                                                                                                            |
| cash flow              | `GET /stats/cash-flow?from&to&granularity=monthly\|biweekly\|weekly`. Returns `{periods:[{periodStart, periodEnd, income, expenses, netFlow}], totals:{income, expenses, netFlow, savingsRate}}`.                                  |

### Subscription endpoints

- **`GET /subscriptions/summary`** returns `{estimatedMonthlyCost, projectedYearlyCost, expectedMonthlyIncome, activeCount:{expense,income}, currencyCode, averageMonthlyIncome, percentOfIncome|null, lookbackMonths}`.
  - It returns 422 `CURRENCY_NOT_CONNECTED` with `details.currencyCodes` when a subscription uses a currency the user hasn't connected.
- **`GET /subscriptions/upcoming`** returns `[{subscriptionId, subscriptionName, logo*, expectedAmount, expectedCurrencyCode, transactionType, nextPaymentDate, frequency, categoryName, categoryColor}]`.
- **`GET /subscriptions?isActive=true`** returns items that include `currentPeriod:{id, dueDate, status:'upcoming'|'overdue'}|null`, `nextDueDate`, `account`, and `category`.
  - The widget shows items that are overdue, or upcoming within 3 days.

## Transaction review

The scope is the caller's own transactions only.

- **`GET /transactions/review/summary`** returns `{unreviewedCount, fraudCount}`.
- **`GET /transactions/review?status=unreviewed|reviewed|fraud&limit(1..100, default 50)&offset`** returns `Transaction[]` including splits, tags, and `hasAttachments`.
  - Unreviewed: never-deferred rows first, oldest first, then deferred rows by deferral time.
  - Reviewed and fraud: newest first.
- **`PUT /transactions/review`** takes `{transactionIds: uuid[] (1..100, unique), action:'reviewed'|'check_later'|'fraud'|'unreviewed'}` and returns `{updatedCount}`.
  - It is all-or-nothing: returns 404 if any ID is missing or not the caller's.

## Notifications and bank sync

- **`GET /notifications/unread-count`** returns `{count}`.
- **`GET /notifications?status&type&limit&offset`** returns `{data:[{id, type, title, message, payload, status, priority, createdAt, readAt, expiresAt}], meta:{total}}`. Note the double wrapping under `response`.
- **`GET /bank-data-providers/sync/check`** triggers a sync if more than 4 hours have passed.
  - Returns `{syncTriggered:false, message}` or `{syncTriggered:true, totalAccounts, queuedAccounts}`.
  - Returns 402 without the `bank_providers` feature.
- **`POST /bank-data-providers/sync/trigger`** returns `{totalAccounts, queuedAccounts}`.
- **`GET /bank-data-providers/sync/status`** returns:
  - `lastSyncAt` (epoch ms) | null
  - `accounts:[{accountId, accountName, providerType, status:'idle'|'queued'|'syncing'|'completed'|'failed', error}]`
  - `connectionsNeedingReauth[]`
  - `connectionStatuses[]`
  - `summary:{total, syncing, queued, completed, failed, idle}`
- **`GET /sse/events`** is a server-sent event stream for sync and job updates.
