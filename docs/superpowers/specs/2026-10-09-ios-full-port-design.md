# iOS Full Port Design (Sub-projects C, D, E)

## Purpose

This spec finishes the native iOS port. Every remaining web feature reaches MoneyMatter for iOS, so nothing stays web-only. It builds on sub-project B ([2026-10-09-ios-foundation-design.md](2026-10-09-ios-foundation-design.md)) and keeps B's architecture, design system, testing rules, and Liquid Glass usage.

Each iOS screen must reproduce the behaviour of its web counterpart. The web page and its `src/api/*.ts` module are the reference for behaviour, fields, and endpoints, and backend controllers are the reference for payloads. Apple's Human Interface Guidelines decide the presentation. Desktop patterns become their native equivalents:

- dense tables become lists with drill-down;
- dialogs become sheets;
- drag-to-resize grids become reorder lists;
- column-mapping wizards become stepped forms.

## Information architecture

| Place                                     | Contents                                                                                                                   |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| **Home** (tab)                            | Existing cards, the notification bell (toolbar), and dashboard customization (D1).                                         |
| **Accounts** (tab)                        | Existing list, an **Assets** section (Loans, Investments, Venture, Vehicles), and the **Bank Connections** entry point.    |
| **Transactions** (tab)                    | Existing list, multi-select bulk actions, and a toolbar **More** menu with Review, Groups, Optimizations, and Automations. |
| **Planning** (tab, new)                   | Budgets, Planned Budgets, and Recurring Payments in a segmented root.                                                      |
| **Insights** (tab, new)                   | The analytics sections as a list that drills into each report.                                                             |
| **Settings** (sheet from the Home avatar) | Settings hub, below.                                                                                                       |

The Settings hub is a `NavigationStack` with these sections and rows:

- **Profile**
- **Organization:** Categories, Tags, Payees, Currencies, Account Groups.
- **Sharing:** Shared with Me, Household.
- **Data:** Import, Export, Backup & Restore.
- **AI:** Features, API Keys, Endpoints, Integrations (MCP).
- **App:** Appearance, Language, General.
- **Security:** Login Methods & Passkeys, Sessions, Password, Danger Zone.
- **Plan & Billing.**
- **Admin** (only when `user.isAdmin`).
- **Server**, **Sign Out**, **Version**.

## Work areas

Each area is owned by one build agent and lives in its own folders.

- **App code:** `ios/MoneyMatter/Features/<Area>/`.
- **Kit code:** endpoints and models in `ios/MoneyMatterKit/Sources/MoneyMatterKit/<Area>/`, with tests in `ios/MoneyMatterKit/Tests/MoneyMatterKitTests/<Area>/`.

### C1 Planning

Web reference: `pages/budgets`, `pages/planned` (subscriptions, future budgets), and `api/budgets.ts`, `future-budgets.ts`, `subscriptions.ts`, `subscription-candidates.ts`.

- **Budgets:** cards with utilization; create (category or manual type); detail with stats, utilization bar, category and timeline charts, and the transaction list; add or remove transactions; edit, archive, and delete.
- **Planned budgets:** list, create, and detail with salary projections, recurring projections, and plan-only entries, as in the future-budget-planner spec.
- **Recurring payments:**
  - list with sort, summary, and period selector;
  - detail with basics, schedule, automation, matching rules, linked transactions, and mark-paid;
  - create and quick-add;
  - discover candidates.

### C2 Organization

Web reference: settings `categories`, `tags`, `payees`, `currencies`, `accounts-groups`, `pages/transaction-groups`, `pages/automations`, and the matching `api/*.ts`.

- **Categories:** hierarchical create, edit, move, and delete-with-reassign.
- **Tags:** create, edit, and delete, plus tag reminders.
- **Payees:** list with sort and search, detail with transactions, edit (default category, categorization mode, default tags), aliases and ignored names, and payee settings.
- **Currencies:** add and remove, set or change base currency (job status polling), and edit exchange rates.
- **Account groups:** create, edit, nest, and move accounts.
- **Transaction groups:** list, create, edit, and add or remove transactions.
- **Automations:** list and an editor with the conditions builder and actions builder.

### C3 Transactions advanced

Web reference: `components/dialogs/manage-transaction/*`, `pages/records`, and `api/transactions.ts`, `refunds.ts`, `attachments.ts`, `transaction-templates.ts`.

The editor gains:

- **Splits** (up to 10).
- **Refund linking**, both "mark as refund" and refunded-by.
- **Transaction linking** for transfers: link existing and unlink.
- **Attachments:**
  - Sources: PhotosPicker, camera, and document picker.
  - Upload, list, preview with QuickLook, and delete.
- **Location** with a MapKit picker.
- **Templates:** apply, save as template, and manage.
- **Planned transactions:** the toggle, plus the planned and upcoming section in the list.
- **Original amount and currency.**

The list gains multi-select with bulk delete, bulk set category, and add to group.

### D1 Insights and dashboard

Web reference: `pages/analytics/*`, `components/widgets/*`, and `api/stats.ts`.

- **Insights tab.** Built on Swift Charts, sharing a granularity and filter control:
  - trends comparison;
  - cash flow;
  - net worth history;
  - net worth drivers;
  - investment contributions;
  - pivot report (scrollable grid);
  - investment calculator (on-device math).
- **Home customization:**
  - Reorder, show, and hide widgets.
  - Persisted to `dashboard.widgets` in user settings through `PATCH /user/settings`.
  - Adds the remaining widgets: category spending tracker, cash flow, net worth, credit utilization, planned overview.

### D2 Assets

Web reference: `pages/loans`, `pages/investments`, `pages/portfolios`, `pages/venture`, `pages/accounts/vehicle-details.vue`, and `api/loans.ts`, `investments.ts`, `portfolios.ts`, `holdings.ts`, `securities.ts`, `investment-transactions*.ts`, `venture/*`, `vehicles.ts`.

- **Loans:** list with aggregate, detail with balance journey chart, payoff projection, cost, and events timeline; record payment; create, edit, and archive.
- **Investments:**
  - Portfolios list and portfolio detail: holdings, balance, and cash.
  - Buys and sells.
  - Add symbol (security search), cash transactions, transfers, exchange currency.
  - Edit and delete.
  - Import transactions from a file.
- **Venture:** deals, metrics, platforms, deal detail with events timeline.
- **Vehicles:** vehicle accounts with depreciation chart, details, and value overrides.

### E1 Connections, notifications, and sharing

Web reference: `pages/accounts/integrations`, `components/bank-*`, `pages/bank-callback.vue`, `pages/shared-with-me`, settings `household`, and `api/bank-data-providers.ts`, `notifications.ts`, `share.ts`.

- **Bank connections:**
  - Providers: Monobank, Enable Banking, LunchFlow, Walutomat, SimpleFIN.
  - Connect each provider with its credential form. Enable Banking runs its consent flow in `ASWebAuthenticationSession`, matching the HTTPS callback `https://<server>/bank-callback`.
  - Connection details: rename, reconnect, disconnect, connect accounts.
  - Sync status, manual sync, and relink warnings, with a sync indicator on Accounts.
- **Notifications:** list with unread badge on the Home bell; read, read all, and dismiss; tap actions such as invitations.
- **Sharing:** share an account or budget with permission; invitations, accept and decline; Shared with Me; household members and invites; `?invitation_token=` links.

### E2 Settings, security, and AI

Web reference: settings `security`, `appearance`, `language`, `general`, `ai`, `ai-integrations`, `plan-billing`, `admin`, and `api/auth.ts`, `ai-settings.ts`, `mcp.ts`, `billing.ts`, `backup.ts`, `user-settings.ts`.

- **Security:**
  - Login methods: link and unlink Google or GitHub, and **register passkeys natively** with `ASAuthorizationPlatformPublicKeyCredentialProvider` registration through `/auth/passkey/generate-register-options` and `verify-registration`.
  - Sessions list and revoke, and set or change password.
  - Backup and restore, with job polling.
  - Danger zone: wipe data and delete account, each with confirmation.
- **App preferences:** appearance (currency display, hide zero balances, theme), language, and general.
- **AI:** feature model selection, API keys, custom endpoints, and categorization instructions.
- **Integrations:** MCP connected apps list and revoke.
- **Plan & billing:** plan status, with checkout and portal opened in `SFSafariViewController`.
- **Admin:** security price upload from a file.

### E3 Data and optimizations

Web reference: `pages/import-export/*`, settings `data-management`, `pages/optimizations/*`, and `api/import-*.ts`, `data-export.ts`, `ai-categorization.ts`.

- **Import:**
  - Sources: CSV, YNAB, OFX, MS Money, BudgetBakers Wallet, and the AI statement parser (text source).
  - Each is a stepped flow: file from the document picker, then mapping, then duplicate review, then execute with progress.
  - Import history, with batch delete.
- **Export:** configure, then download and share through `ShareLink`.
- **Optimizations:** transfer suggestions (scan and confirm) and AI categorization (run, progress, history). Progress uses polling, or SSE through `URLSession.bytes`.

## Shared rules

- **API access:** features use `@Environment(AppServices.self)` and `services.client`, plus their own endpoint factories added as `Endpoints` extensions in their Kit folder. Shared files (`AppServices`, `LiveAPI`, `FeatureServicing`) are not modified.
- **Placeholders:** every entry point in the Information architecture is pre-wired by a scaffold step as a placeholder view in the owning area's folder, and each area replaces only its own placeholders. Navigation inside a tab uses that tab's `NavigationPath`.
- **Models:** decode leniently, as B does. Unknown enum values map to `.unknown`, and money is `Decimal`.
- **Screen states:** each screen has loading (redacted), empty (`ContentUnavailableView`), and error (inline retry) states.
- **Mutations:** each mutation updates the UI, shows the shared error alert on failure, and refreshes dependent data.
- **Confirmations:** destructive actions use `.confirmationDialog`.
- **Strings:** all go through the String Catalog. Accessibility labels go on icon-only buttons and charts.

## Testing

- **Kit:** each area adds decoding tests for its models and request-encoding tests for its writes, run with `swift test`.
- **App:** the app target builds with zero errors and no warnings in new code; app unit tests pass.
- **Simulator:** a screenshot pass of every new tab and settings section against the local backend, light and dark.
- **Backend:** only changed if a feature needs it, with e2e tests per CLAUDE.md.

## Acceptance criteria

1. Every web route and dialog listed in the web feature inventory has a working iOS counterpart reachable from the Information architecture.
2. Planning and Insights tabs exist, and Accounts, Transactions, Home, and Settings expose every entry point listed.
3. All Kit and app tests pass, and the project builds clean.
4. The simulator pass shows each new screen rendering real data or a correct empty state.
