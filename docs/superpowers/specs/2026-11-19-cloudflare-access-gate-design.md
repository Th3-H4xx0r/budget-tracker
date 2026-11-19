# Cloudflare Access gate – design

Date: 2026-11-19 · Status: draft, awaiting owner approval · Branch: `feat/ios-redesign`

## Intent

Put an outer gate in front of `budget.pkrishna.dev` (website **and** API) using Cloudflare Access (Zero Trust). Nothing reaches the app – not even its login page – until the request has passed Cloudflare:

- **a person in a browser** passes Cloudflare's own login page;
- **the iOS app** passes by sending a Cloudflare **service token** (`CF-Access-Client-Id` / `CF-Access-Client-Secret` headers) on every request.

The app's own authentication (better-auth: email/password, Google/GitHub, passkeys) stays exactly as it is, behind the gate. This is an extra layer, not a replacement.

**Why:** extra security for both the app and the website – the only thing the public internet can reach is Cloudflare's login page.

## Goals

1. Every path on `budget.pkrishna.dev` sits behind Access, except `/.well-known/apple-app-site-association` (Apple's CDN fetches it anonymously for passkeys; it only contains the app ID).
2. Web uses Cloudflare's login page. The SPA needs no gate code beyond recovering cleanly when the Cloudflare session expires.
3. The iOS app sends the service token on **every** request to the server: app, widget, background refresh, passkey ceremonies, uploads/downloads, and the Google/GitHub sign-in sheet.
4. The token gets onto the phone by **pasting** it (server screen and Settings) **or scanning a QR code** shown in web Settings.
5. The iOS app tells a Cloudflare rejection apart from an app-level logout and says so plainly.
6. A setup guide covers the Cloudflare dashboard steps and rollout order.

## Non-goals

- Changing better-auth or any existing login method.
- Backend verification of Cloudflare's signed `Cf-Access-Jwt-Assertion` header (approach B – rejected, see Approaches).
- Automating Cloudflare configuration (API/Terraform). It is set up by hand from the guide.
- Token rotation UI, multiple tokens, per-device tokens.
- Keeping MCP (`/mcp`, `/authorize`, `/token`, `/register`, `/.well-known/oauth-*`), the GitHub release webhook, or the landing/privacy/terms pages publicly reachable. The owner chose to gate all of them; they stop working for outside callers, by design.

## Anti-goals (would be a failure even if it "works")

- **Lock-out:** the owner must always have a way back in. The browser path (Cloudflare login) always works, and from there the web QR re-provisions the phone.
- **Token leakage:** the token is sent only to the configured server host, never logged, shown only to the admin, never placed in a URL or deep link.
- **Breaking servers without Access:** the feature is dormant unless configured. No token on the phone → no headers. No env vars on the server → no QR card. Self-hosters see no change.

## Constraints and facts

- `budget.pkrishna.dev` uses Cloudflare DNS and is reached **through a Cloudflare Tunnel** (owner-confirmed): the origin has no open inbound ports, so requests cannot skip Cloudflare.
- Single origin: nginx serves the SPA, landing page, `/api`, `/mcp` and `/.well-known` on one host. One Access application covers web and API.
- **Single user** (owner-confirmed): only the owner signs in.
- Admins are defined by the `ADMIN_USERS` env list (`packages/backend/src/middlewares/admin-only.ts`). The owner's username must be in it for the QR card to appear.
- iOS 26+, SwiftUI. All API requests are built in `APIClient.makeRequest` (`ios/MoneyMatterKit/Sources/MoneyMatterKit/API/APIClient.swift`). The bearer token lives in the Keychain under a shared access group (`KeychainTokenStore.swift`) so the widget can read it. The server origin is in App Group defaults (`ServerStore.swift`) and entered on `Features/Auth/ServerView.swift`.
- Requests that bypass `makeRequest` or need checking: the passkey ceremony session (`SettingsSecurity.swift`), the upload sessions (`SettingsUpload.swift`, `TransactionAttachmentTransfer.swift`, `DataUpload.swift`), the widget (`MoneyMatterWidget/MonthlyBudgetProvider.swift`), the background task (`Platform/MonthlyBudgetAlerts.swift`).
- Google/GitHub sign-in on iOS opens an ephemeral `ASWebAuthenticationSession` at `/api/v1/auth/native/oauth/start` (`Platform/WebAuthenticator.swift`). The provider redirects back through `/api/v1/auth/callback/*` on our host. A browser sheet cannot carry custom headers on later requests.
- Bank consent uses `ASWebAuthenticationSession` with an https callback to `/bank-callback` (`Features/Connections/BankConsentSession.swift`). The bank pages are third-party.
- Cloudflare lesson (from jarvis-copilot): the token only works under a policy whose **Action is "Service Auth"**. An "Allow" policy ignores service tokens and redirects to the login page.
- The frontend has no QR library. The iOS app already declares camera usage (attachments).

## Approaches

|       | Approach                                                                                                                                                                | Trade-off                                                                                                                                                                             | Outcome                 |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| **A** | **Cloudflare does the gating; app code only cooperates with it** (token on every iOS request, paste/scan, QR card, clear errors, expired-session recovery, setup guide) | Least code. If Access were ever switched off or misconfigured, the app would be open again, protected only by better-auth (as it is today).                                           | **Picked by the owner** |
| B     | A + the backend rejects any request without a valid Cloudflare JWT                                                                                                      | Fails safe if the gate is misconfigured. Costs a JWKS-backed middleware plus a dev/test bypass switch, and the tunnel already makes the origin unreachable except through Cloudflare. | Rejected                |
| C     | Client certificate (mTLS) on the phone instead of a service token                                                                                                       | Stronger on paper, but awkward to install, and the sign-in sheet and widget can't present client certificates.                                                                        | Ruled out               |

## Design

### 1. Cloudflare (manual; documented in the setup guide)

- **Access application "MoneyMatter"** (self-hosted), domain `budget.pkrishna.dev`, all paths.
  - Policy **"Owner"**: Action _Allow_, Include → Emails → the owner's email. Login method: One-time PIN to email _(my call; the owner can add Google/GitHub as identity providers instead)_.
  - Policy **"iPhone"**: Action _Service Auth_, Include → Service Token → `moneymatter-ios`.
  - Session duration: 1 week _(my call)_.
- **Access application "AASA bypass"**, path `budget.pkrishna.dev/.well-known/apple-app-site-association`, policy Action _Bypass_, Include _Everyone_. The more specific path wins over the main application.
- **Service token** `moneymatter-ios`, duration 1 year _(my call)_. Cloudflare shows the secret once, at creation. It goes straight into the server `.env`.

### 2. Backend

- New optional env vars: `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`. Documented in `self-hosting/docs/environment-reference.md`.
- New endpoint, admin-only (`authenticateSession` + `adminOnly`), following route → controller → service. It returns `{ serverUrl, clientId, clientSecret }` (where `serverUrl` is `AUTH_ORIGIN`) when both env vars are set, and `null` when they aren't. Response carries `Cache-Control: no-store`.
- E2E tests (required by CLAUDE.md): happy path (admin, env set), empty state (env unset → `null`), and error cases (non-admin → 401, signed out → 401).

### 3. Web

- **"iPhone access" card in Settings → Security.** It is rendered only for an admin and only when the endpoint returns non-null.
  - It explains what it's for.
  - The QR code and values stay hidden until the owner clicks "Show" _(my call: avoids shoulder-surfing)_.
  - When shown, it displays the QR code, plus Client ID and Secret with copy buttons for the paste route via Universal Clipboard _(my call: Cloudflare won't show the secret again after creation)_.
- **QR payload** (JSON): `{"v":1,"server":"https://budget.pkrishna.dev","cfClientId":"…","cfClientSecret":"…"}`.
- **QR rendering:** a small, dependency-free SVG QR library (e.g. `uqr`) _(my call)_.
- **Expired Cloudflare session.** Once the Cloudflare session expires, API calls get redirected to `<team>.cloudflareaccess.com`. In the browser that surfaces as a CORS/network failure on `fetch`, which the SPA would otherwise show as random errors.
  - The API fetch wrapper (`packages/frontend/src/api/_api.ts`) and the better-auth client should detect this case and do **one** full-page reload. The browser then lands on Cloudflare's login page, then back in the app.
  - Guard against reload loops (e.g. a sessionStorage timestamp).
  - Don't reload when the device is simply offline.
  - The exact detection is left to the builder, verified against the live gate.
- Add `crossorigin="use-credentials"` to the `<link rel="manifest">` so the PWA manifest loads behind Access.
- New i18n keys go in `en` and `uk` together, via the `i18n-editor` subagent.

### 4. iOS

- **Storage.** Cloudflare credentials `{clientId, clientSecret}` go in the Keychain under the same shared access group as the bearer token (so the widget can read them). They are keyed by server host, accessible after first unlock, and this device only (matching the bearer token). They are cleared when the server is changed or disconnected.
- **Header injection.** `APIClient.makeRequest` adds both headers when credentials exist **and** the request's scheme, host and port match the configured server. They are never sent to other origins.
- **Requests outside `makeRequest`.** Every request path to the server must carry the headers: the passkey ceremony session, upload/download sessions, the widget provider, the background task, and any image loaded from the server. Audit with a search for `URLSession(`, `AsyncImage`, and `ASWebAuthenticationSession`.
- **Google/GitHub sign-in sheet.** Set `ASWebAuthenticationSession.additionalHeaderFields` (iOS 17.4+) with the two headers. Cloudflare should accept the token on that first request and set its `CF_Authorization` cookie inside the sheet's ephemeral browser session. That cookie would cover the provider's redirect back to `/api/v1/auth/callback/*`.
  - This is unproven. The owner chose **not** to test it ahead of time: it is built as described and checked when the gate goes live (rollout step 4).
  - If it fails then, **stop and bring options to the owner**: bypass the OAuth paths in Cloudflare, accept the Cloudflare login inside the sheet, or similar.
- **Bank consent sheet.** When the gate goes live, confirm that the https callback to `/bank-callback` is intercepted before it loads. If it does load our host, **stop and bring options to the owner**. Sending the token to the bank's page isn't an option, because that page is on another origin _(my call)_.
- **Recognizing a Cloudflare rejection.** The API session doesn't follow redirects to `*.cloudflareaccess.com`. Two cases map to a distinct error:
  - such a redirect;
  - a 401/403 that comes from Cloudflare rather than the app's JSON envelope.

  The error says "Cloudflare blocked this request" and leads to the token editor: Settings when signed in, otherwise the launch or sign-in screen (see UI). It must **not** trigger `onUnauthenticated`, so the user isn't signed out. The exact response signals are confirmed against the live gate.

- **UI**
  - **`ServerView`:** a collapsed "Cloudflare Access" section under the server address. It has a Client ID field, a Secret field (secure entry), and a "Scan QR code" button. Connecting uses whatever is filled in.
  - **Settings:** a "Cloudflare Access" row showing whether the token is set. From there the owner can replace it (paste or scan) or remove it.
  - **Launch and sign-in recovery** _(owner's choice: fix in place)_. Cloudflare can reject the request while the app restores a session at launch, for example after a token expires or is rotated. In that case `LaunchView` says Cloudflare blocked the connection and offers "Update Cloudflare token" (paste or scan). Saving retries the restore and keeps the app session. `SignInView` offers the same entry, so a signed-out user can fix the token without going through Change Server.
  - **Scanner:** VisionKit `DataScannerViewController`. It accepts only the JSON payload above, with an `https` server. It shows the server host for confirmation before saving. Scanning from `ServerView` also fills in the server address.
  - **No URL scheme or deep link carries this payload** _(my call: no website or app can push a server and token into the app)_.
- **Tests:** unit tests for header injection (only to the server origin), mapping a Cloudflare rejection, and parsing the QR payload (rejecting `http`, a malformed payload, or a missing field).

### 5. Docs

`self-hosting/docs/cloudflare-access.md` is the setup guide. It assumes the tunnel and covers:

- the two Access applications and their policies;
- creating the service token;
- the `.env` vars and `ADMIN_USERS`;
- setting up the phone;
- the rollout order (below);
- what stops working: MCP, webhooks, the public landing page.

### 6. Rollout order (so the phone is never locked out)

1. Ship backend, web and iOS changes. The feature stays dormant: no env vars means no QR, and no token means no headers.
2. Create the service token, put it in `.env`, add the owner's username to `ADMIN_USERS`, and restart. Scan the QR on the phone.
3. Create the AASA bypass application, then the main application.
4. Run the verification checklist below. This is the first time the iPhone's Google/GitHub sign-in sheet and the bank consent sheet meet the gate.

## Success criteria

- The endpoint's e2e tests and the iOS unit tests pass.
- Live checklist against the gate:
  - A browser reaches Cloudflare's login, then the app's login, then the app.
  - The iPhone app loads data.
  - The widget refreshes.
  - Passkey sign-in works on iPhone and web.
  - Google sign-in works on iPhone.
  - On the web, an expired Cloudflare session recovers via reload.
  - A wrong or removed token on iPhone shows the Cloudflare error, not a sign-out.
  - `curl https://budget.pkrishna.dev/api/v1/auth/signups-open` without a token gets Cloudflare, not the app.

## Left to the builder

- Endpoint path and naming, component structure, i18n key names, and how the e2e test sets the env vars.
- Exact Cloudflare rejection signals and expired-session detection (confirmed against the live gate).
- iOS string localization, following the app's existing approach.

## Related

- The passkey registration fix (`AUTH_RP_ID` falling back to `localhost`) shipped separately on this branch. Passkeys must be working before this gate's checklist can pass.
