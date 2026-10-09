# iOS Foundation and Core Design

## Purpose

MoneyMatter for iOS is a native SwiftUI client for the budget-tracker backend. It is for personal use and follows Apple's Human Interface Guidelines on iOS 26 with Liquid Glass.

This spec is sub-project B of the iOS port. It delivers:

- the app shell;
- authentication with email/password, Google, GitHub, and passkeys;
- onboarding;
- the Home, Accounts, and Transactions tabs;
- the Transaction Review card stack and review page;
- minimal Settings.

It also covers the backend changes a native client needs. Sub-projects C, D, and E port the remaining web features; see [Roadmap](#roadmap). Nothing stays web-only.

API shapes are documented in [2026-10-09-ios-api-contract.md](2026-10-09-ios-api-contract.md). The review feature's behaviour is defined in [2026-10-09-transaction-review-design.md](2026-10-09-transaction-review-design.md).

## Scope

In scope for B:

- Xcode project at `ios/`, with a local Swift package for the non-UI code.
- **Backend:** bearer-token sessions, native OAuth endpoints, passkey origin config, and the `apple-app-site-association` file.
- **Server and session:** a server URL screen, sign in, sign up, sign out, and session restore.
- **Onboarding:** base-currency selection when the user has no base currency.
- **Tab bar:** Home, Accounts, Transactions. Planning arrives in C and Insights in D.
- **Home:** review card, balance trend, spending by category, latest transactions, upcoming payments.
- **Accounts:** grouped list, detail, create, edit, archive, delete.
- **Transactions:** list with search and filters, detail, and a core editor (create, edit, delete for expense, income, and transfer).
- **Review:** card stack (swipe plus buttons) and a review page with three segments.
- **Settings:** profile summary, server, sign out.

Moved to C: splits, refund linking, attachments, location, templates, and planned transactions in the editor. Passkey registration and session management move to E. B supports passkey sign-in only; passkeys are registered on the web until E.

## Project layout

```
ios/
  MoneyMatter.xcodeproj          hand-authored, file-system-synchronized groups, shared scheme
  MoneyMatter/                   app target: SwiftUI views, platform services
    App/                         entry point, root view, dependency container
    Features/Auth|Onboarding|Home|Accounts|Transactions|Review|Settings/
    Platform/                    Keychain, ASWebAuthenticationSession, passkeys
    Resources/                   Assets.xcassets, Localizable.xcstrings, Info.plist, entitlements
  MoneyMatterTests/              app-level unit tests (Swift Testing)
  MoneyMatterKit/                local Swift package, no UI
    Sources/MoneyMatterKit/      models, API client, endpoints, formatting, ReviewSession, PKCE
    Tests/MoneyMatterKitTests/   runnable with `swift test` on macOS
```

- **Project file:** `MoneyMatter.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup` (object version 77), so new files inside `MoneyMatter/` and `MoneyMatterTests/` join their targets without editing the project file. A shared scheme `MoneyMatter` builds the app and runs both test targets.
- **Identity and signing:**
  - Bundle ID `com.pranavkrishna.budgettracker`, display name **MoneyMatter**.
  - `DEVELOPMENT_TEAM` is left empty. The user sets it in Xcode.
  - Simulator builds from the command line pass `CODE_SIGNING_ALLOWED=NO`.
- **Language and deployment:** Swift 6 language mode with complete strict concurrency. Deployment target iOS 26.0.
- **Concurrency:** the app target uses main-actor default isolation (Swift 6.2 approachable concurrency). `MoneyMatterKit` types are `Sendable` and nonisolated.
- **Dependencies:** no third-party code. The app uses Foundation, SwiftUI, Swift Charts, Security, and AuthenticationServices.
- **Strings:** English only. Every user-facing string goes through the String Catalog.

## Backend changes

### Bearer sessions

`packages/backend/src/config/auth.ts` adds `bearer({ requireSignature: true })`.

- The bearer token is the signed better-auth session token. Sign-in responses return it in the `set-auth-token` header.
- `authenticateSession` already reads it, because the bearer plugin injects the session cookie into the headers that `getSession` sees.
- The token slides with the existing 7-day session and daily refresh. There is no refresh token: a 401 means sign in again.
- Web cookie clients are unaffected.

### Native OAuth

Three routes go in `routes/better-auth-extensions.route.ts`, which is mounted at `/api/v1/auth` before better-auth. Each follows route, controller, service.

| Route                                                                        | Behaviour                                                                                                                                                                                                                                                                                                                    |
| ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /auth/native/oauth/start?provider=google\|github&code_challenge=<S256>` | Validates the provider is configured. Stores the challenge in a short-lived signed HttpOnly cookie. Calls `auth.api.signInSocial` with `callbackURL` and `errorCallbackURL` set to `${BETTER_AUTH_URL}/api/v1/auth/native/oauth/complete` and `disableRedirect: true`. Forwards the state cookie, then 302s to the provider. |
| `GET /auth/native/oauth/complete`                                            | On `?error`, 302s to `<scheme>://auth-callback?error=<code>`. Otherwise requires a session younger than 2 minutes and the challenge cookie. Stores `{sessionToken, challenge}` in Redis under a random one-time code with a 60-second TTL, then 302s to `<scheme>://auth-callback?code=<code>`.                              |
| `POST /auth/native/oauth/exchange` `{code, codeVerifier}`                    | Atomically gets and deletes the code. Checks `base64url(SHA256(codeVerifier)) == challenge` and returns `{token}` (the signed bearer token). An unknown or expired code, or a wrong verifier, returns a 401 with an i18n message.                                                                                            |

- `<scheme>` comes from the env var `NATIVE_APP_URL_SCHEME`, default `moneymatter`, and never from the request.
- The Google and GitHub redirect URIs do not change.

### Passkeys

The passkey plugin's `origin` becomes the de-duplicated list `[AUTH_ORIGIN, https://${AUTH_RP_ID}]`. An iOS assertion's `clientDataJSON` origin is `https://<rpID>`, so it then passes. Web behaviour is unchanged.

### Associated Domains file

`packages/frontend/public/.well-known/apple-app-site-association` contains:

```json
{ "webcredentials": { "apps": ["TEAMID.com.pranavkrishna.budgettracker"] } }
```

`TEAMID` is a placeholder the user replaces with their Apple Team ID.

`packages/frontend/nginx.conf` gains an exact `location` for the file with `default_type application/json`, modelled on the existing `api-catalog` location.

### Backend tests

E2E tests in `services/auth/` go through HTTP only:

- Bearer:
  - Email sign-in returns `set-auth-token`.
  - `GET /user` with `Authorization: Bearer` succeeds.
  - A tampered token returns 401.
  - After sign-out, the token returns 401.
- Exchange:
  - Happy path.
  - Unknown code.
  - Expired code.
  - Wrong verifier.
  - A reused code fails the second time.
- `start` with an unconfigured provider returns a validation error.

The happy path seeds a code through the `complete` endpoint, using a session created by email sign-in.

## App architecture

### MoneyMatterKit

- **`APIClient`** (Sendable) holds the base URL, a token provider, and a `URLSession`.
  - The session's `httpCookieStorage` is nil and `httpShouldSetCookies` is false, so no cookie is ever replayed and better-auth's origin check never triggers.
  - Adds `Authorization: Bearer <token>` and `Accept-Language`. `/auth/*` POSTs also send `Origin: <server origin>`.
  - Decodes the `{status, response}` envelope, ISO-8601 dates with fractional seconds, and `Decimal` amounts.
  - Maps failures to `APIError`:

    | Case                           | Source                   |
    | ------------------------------ | ------------------------ |
    | `unauthenticated`              | 401                      |
    | `planRequired`                 | 402                      |
    | `baseCurrencyChangeInProgress` | 423                      |
    | `validation(message, issues)`  | 422                      |
    | `notFound`                     | 404                      |
    | `server(code, message)`        | any other error envelope |
    | `network(URLError)`            | transport failure        |
    | `decoding`                     | unexpected body          |

- **Models:**
  - `User`, `UserCurrency`, `Currency`, `Account`, `AccountGroup`, `Transaction`, `Category` (with a tree builder from the flat list), `Tag`, `PayeeLookup`, `BalancePoint`, `CategorySpending`, `UpcomingPayment`, `SubscriptionListItem`, `ReviewSummary`.
  - Enums mirror the backend values. An unknown raw value decodes to an `unknown` case and never fails decoding.
- **`Endpoints`:** one typed function per call in the API contract that B uses. Query lists are comma-joined. Booleans affected by `z.coerce` are omitted rather than sent as `false`.
- **`ReviewSession`:** a pure state machine, a port of the web `use-review-session.ts` semantics.
  - Optimistic advance; writes serialized in order.
  - Undo stack; rollback on failure.
  - Rows deferred in a session do not reappear in it.
  - Pages are fetched from offset 0 and skip rows already seen. Restarting waits for pending writes.
  - Network calls are injected.
- **`PKCE`:** verifier and S256 challenge generation.
- **`MoneyFormat`:** `Decimal` currency formatting with the currency's minor digits, and VoiceOver-friendly spoken amounts.

### App target

- **`SessionStore`** (`@Observable`) is the single source of auth state, with states `.needsServer`, `.signedOut`, `.needsOnboarding(User)`, and `.signedIn(User, baseCurrency)`.
  - On launch it restores the server URL from `UserDefaults` and the token from the Keychain, then calls `GET /auth/get-session` and `GET /user/currencies/base`.
  - Any `unauthenticated` error from any request signs the user out and returns to sign-in.
- **Keychain:** `kSecClassGenericPassword`, service `com.pranavkrishna.budgettracker`, account `<server host>`, accessible after first unlock (this device only). Changing the server signs out.
- **Dependency injection:**
  - `AppDependencies` holds the `APIClient` and the stores, and is injected with `.environment`.
  - Features talk to the API through protocols, so view models are testable with stubs.
- **Navigation:**
  - A `TabView` using the `Tab` API, with `.tabBarMinimizeBehavior(.onScrollDown)`.
  - Each tab owns a `NavigationStack` with a typed route enum.
  - Sheets handle creation and editing. The review stack is a `fullScreenCover`.
- **Shared data:** an `@Observable` `ReferenceDataStore` caches accounts, categories, tags, payees lookup, and user currencies for the session. It refreshes on pull-to-refresh and after any write that changes them.

## Screens

### Authentication

1. **Server.**
   - Shown when no server is saved.
   - A URL field (prefilled `https://budget.pkrishna.dev`), validated by calling `GET /auth/signups-open`.
   - `http://` is accepted only for `localhost` and `.local` hosts. App Transport Security allows local networking only.
2. **Sign in.**
   - Email and password fields.
   - **Sign in with Passkey**, shown only when the server host is listed in the app's Associated Domains (`budget.pkrishna.dev`).
   - **Continue with Google** and **Continue with GitHub**.
   - A link to sign up, and a link to change the server.
3. **Sign up.**
   - Name, email, and password.
   - When the server requires email verification (the response token is null), shows "Check your email to verify your account, then sign in."
   - Hidden when `signupsOpen` is false.

**Sign-in methods:**

- **OAuth:** generate a PKCE pair, then open `ASWebAuthenticationSession` with the `start` URL, the callback scheme `moneymatter`, and `prefersEphemeralWebBrowserSession = true`. On callback, exchange the code for the token.
- **Passkey:**
  1. With a fresh ephemeral `URLSession` that keeps the challenge cookie, `GET /auth/passkey/generate-authenticate-options`.
  2. Run `ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)` assertion.
  3. POST `/auth/passkey/verify-authentication` with base64url SimpleWebAuthn JSON and the `Origin` header.
  4. Read `set-auth-token`.

**Entitlements:** `com.apple.developer.associated-domains` = `webcredentials:budget.pkrishna.dev`. Debug builds append `?mode=developer`.

### Onboarding

A searchable currency list from `GET /models/currencies`. The device locale's currency is pinned first, then USD, EUR, GBP. **Continue** calls `POST /user/currencies/base`.

### Home

- **Header:** a large title "Home" with the user's avatar (initials) as the trailing toolbar button, which opens Settings in a sheet.
- **Content:** a single scrolling column of cards, with a month period selector (previous and next chevrons, today's month by default) above the charts.
  - **Review card.** Shown only when `unreviewedCount > 0`.
    - A glass card with a shield symbol, "{count} transactions to review", the subtitle "Check recent bank transactions for anything you don't recognize", and a **Review** button that opens the stack.
    - A "{count} marked as fraud" link opens the review page on Fraud.
    - If the summary fails to load, a compact "Couldn't load review status" row with **Retry** replaces the card.
  - **Balance trend.** A Swift Charts area and line of `totalBalance` over the period, with the current total in large type and the change versus the previous period.
  - **Spending by category.** A donut (`SectorMark`) with the period's total expenses in the centre and the top five categories listed with amounts and colours.
  - **Latest transactions.** The five most recent non-future transactions as standard rows, with **See All** switching to the Transactions tab.
  - **Upcoming payments.** Subscriptions that are overdue or due within three days, overdue first. Hidden when empty.
- **Loading and errors:**
  - Pull-to-refresh reloads every card.
  - Each card has its own redacted placeholder while loading and an inline retry on failure.

### Accounts

- **Header:** a large title, the net worth summary (sum of `refCurrentBalance` over active accounts not excluded from stats, in the base currency), and a **+** toolbar button.
- **Sections:** one per root account group (nested groups flattened under their root), then **Other accounts**, then a collapsed **Archived** section.
- **Rows:** logo or initials badge, name, a category subtitle, and the balance in the account currency.
- **Account detail:**
  - A balance header, then that account's transactions, sharing the transaction list component with `accountIds` set.
  - Toolbar: **Edit**, plus a menu with Archive/Unarchive and Delete. Delete needs confirmation and shows the transaction count from `GET /accounts/:id/transaction-count`.
- **Create sheet:**
  - Name.
  - Currency, from the user's currencies.
  - Category: general, cash, current account, credit card, saving, investment, crypto, etc. Loan and vehicle are excluded.
  - Initial balance, and credit limit for credit cards.
- **Edit sheet:**
  - Name, category, and credit limit.
  - Exclude from stats.
  - Current balance, for system accounts only.

### Transactions

- **List:**
  - Rows are grouped in day sections with the day's net total.
  - Infinite scroll, 50 rows per page.
  - `.searchable` maps to `noteSearch`.
  - Toolbar: a filter button (type, accounts, categories, date range; active filters shown as a count badge), a **Review** button with the unreviewed count badge that opens the review page, and **+**.
- **Row:**
  - Category colour circle with the category's SF Symbol, falling back to its initial.
  - Title: payee name, else note, else category name.
  - Subtitle: account · time.
  - Amount: income green, expense primary, transfer secondary.
  - A red "Fraud" capsule when `reviewStatus == fraud`.
  - Swipe actions: **Delete** (destructive, confirmed) and **Edit**.
- **Detail:**
  - A large amount header, then account, category, date and time, payee, tags, note, and review status.
  - Review actions matching the current status.
  - **Edit** and **Delete** toolbar items.
- **Editor sheet:**
  - A segmented control: Expense, Income, Transfer.
  - A large amount field with the account currency.
  - Account picker. For transfers, also a destination account and a destination amount, shown only when the currencies differ.
  - A searchable hierarchical category picker (not shown for transfers).
  - Date and time.
  - Payee picker (search `GET /payees?q`).
  - Tags (multi-select).
  - Note.
- **Editor rules:**
  - Disabled fields follow the contract: no category on transfers, and manual rows only on system accounts. Bank-connected accounts are not selectable as the source of a new non-planned transaction.
  - **Save** sends `POST` or `PUT`. The response array (one or two legs) updates the list.
  - Edit mode shows **Delete Transaction**.

### Review

- **Stack:** a `fullScreenCover` holding a `ReviewSession`.
  - **Toolbar:** **Close**, the progress "{n} of {total}", and **Undo**.
  - **Card:** payee or note, amount, account, date and time, and category.
- **Swipe gestures:**
  - Right: **Looks good**, with a green tint growing with drag distance.
  - Left: **Check later**, with an amber tint.
  - Release past one third of the card width commits the action. Otherwise the card springs back.
  - Fraud is never a swipe, so it can't be triggered by accident.
- **Buttons:** **Fraud** (red tint), **Check later**, and **Looks good** (prominent), in a `GlassEffectContainer` below the card.
- **Feedback:** `.sensoryFeedback` on commit. With Reduce Motion, the card fades instead of flying off.
- **Accessibility:** VoiceOver exposes the three actions as custom actions on the card.
- **End state:** "All caught up", plus "{count} saved for later" when any were deferred, and **Done**.
- **Errors:** failed writes put the card back and show an alert. A failed page load shows an inline retry instead of "All caught up".
- **Page:** a segmented picker (Unreviewed, Reviewed, Fraud) with counts, and a **Start Review** button.
  - Rows use the shared transaction row.
  - Swipe and context-menu actions follow the web table: Unreviewed has Looks good and Fraud; Reviewed has Mark as fraud and Move to unreviewed; Fraud has Not fraud and Move to unreviewed.

### Settings

Settings opens from the Home avatar, as a sheet holding a `Form`:

- **Profile:** name and email.
- **Server:** the host, plus **Change Server**, which signs out.
- **Sign Out:** destructive, confirmed. Calls `POST /auth/sign-out`, then clears the Keychain.

The full settings port is in E.

## Design system

- **Colours and materials:**
  - System semantic colours throughout.
  - Income uses `.green`, expense uses `.primary` with a leading minus, transfer uses `.secondary`. Fraud uses `.red`.
  - Liquid Glass is used only on interactive or floating elements: the tab bar and toolbars (automatic), the review card, the review action buttons, and the Home review card. List and content backgrounds stay standard.
- **Type and symbols:** SF Symbols for every icon, Dynamic Type for every text style, and `.monospacedDigit()` on amounts.
- **Dark mode:** follows the system.
- **Empty states:** `ContentUnavailableView` with a symbol, a title, a description, and an action where one applies.
- **Accessibility:**
  - Minimum 44-point targets.
  - Amounts have spoken labels ("minus 84 dollars and 21 cents").
  - Charts provide `accessibilityChartDescriptor` summaries.

## Error handling

- **402 (plan required):** an alert explaining that the server's plan doesn't allow the action.
- **423 (base-currency change in progress):** an alert telling the user to wait for the base-currency change to finish.
- **Network failures:** inline retry views on screens, and alerts on mutations.
- **Validation errors:** the server's message is shown under the form.
- **Session expiry:** routes to sign-in with the email field prefilled.

## Testing

- **MoneyMatterKit (`swift test`, Swift Testing):**
  - Decoding fixtures for every model, including transfer arrays, unknown enum values, and null responses.
  - `APIClient` envelope and error mapping through a `URLProtocol` stub, plus the bearer and `Origin` headers.
  - The category tree builder.
  - `ReviewSession`: advance, defer, undo, failure rollback, paging de-duplication, waiting for pending writes, and the saved-for-later tally.
  - PKCE against the RFC 7636 test vector.
  - Money formatting.
- **App target:**
  - Unit tests for `SessionStore` state transitions and for the editor's validation rules, using stubbed protocols.
  - `xcodebuild build test` on the iPhone 17 Pro simulator must pass.
- **Backend:** the e2e tests in [Backend tests](#backend-tests), run through the `test-runner` subagent.
- **Manual pass** in the simulator against a local backend over `http://localhost`, with screenshots of each screen in light and dark mode:
  - sign up and sign in;
  - onboarding;
  - Home with data;
  - creating an account and an expense, an income, and a transfer;
  - editing and deleting;
  - the review stack with swipe, buttons, and undo;
  - the review page segments.
- **Not covered by the manual pass:**
  - OAuth needs provider credentials.
  - Passkeys need the signed app on a device against `budget.pkrishna.dev` with the real Team ID.
  - Both flows are unit-tested and listed for the user to check on device.

## Acceptance criteria

1. The app builds for the iOS 26 simulator with no warnings in new code, and all Kit and app tests pass.
2. A user can point the app at a server, sign up or sign in with email and password, pick a base currency, and land on Home.
3. Google and GitHub sign-in complete through `ASWebAuthenticationSession` and the exchange endpoint, and the backend e2e tests cover exchange success and every failure case.
4. Passkey sign-in is offered only for `budget.pkrishna.dev` and follows the documented ceremony.
5. Home shows the review card when there are unreviewed transactions, and the balance trend, spending, latest transactions, and upcoming payments for the selected month.
6. Accounts can be listed by group, viewed, created, edited, archived, and deleted.
7. Transactions can be searched, filtered, viewed, created (expense, income, transfer), edited, and deleted. Fraud rows show a chip.
8. The review stack supports swipe right and left, the three buttons, undo, and the end state. The review page lists and moves rows between the three segments.
9. The token lives only in the Keychain, and signing out revokes it on the server.
10. Web sign-in, cookie sessions, and existing e2e suites are unaffected.

## Roadmap

| Sub-project                      | Contents                                                                                                                                                                                                                                                                                          |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **C. Planning and organization** | Planning tab: budgets, planned budgets, recurring payments. Settings sections for categories, tags, payees, currencies, account groups, transaction groups, and automations. The advanced transaction editor: splits, refund linking, attachments, location, templates, and planned transactions. |
| **D. Insights and assets**       | Insights tab: every analytics view on Swift Charts, including the pivot report. Loans, investments and portfolios, venture, and vehicles. Dashboard widget customization and the remaining widgets.                                                                                               |
| **E. Integrations and settings** | Bank connections and sync, notifications, sharing and households, security (passkey registration, sessions, password, backup and restore, danger zone), AI features and keys, imports and export, optimizations, admin, billing, and the MCP/AI integrations page.                                |
