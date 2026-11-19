# Cloudflare Access Gate Implementation Plan

> **For agentic workers:** Implement task by task. Steps use checkbox (`- [ ]`) syntax. Implementers write code and tests. Only the `test-runner` agent runs tests, and only the `linter` agent runs lint/typecheck (project rules).

**Goal:** Let the web app, backend and iOS app work behind a Cloudflare Access gate on `budget.pkrishna.dev`: browser via Cloudflare login, iPhone via a service token.

**Architecture:**

- Cloudflare does all gating.
- The backend exposes the service token to the admin (from `.env`) for a QR code.
- The web app shows that QR and recovers from an expired Cloudflare session.
- The iOS app stores the token in the shared Keychain, sends it on every request to the server, and recognizes Cloudflare rejections.

**Tech Stack:** Express + Sequelize + Jest/supertest e2e · Vue 3 + TanStack Query + Vitest · SwiftUI (iOS 26) + Swift Testing + VisionKit.

**Spec:** `docs/superpowers/specs/2026-11-19-cloudflare-access-gate-design.md`

## Global Constraints

- **No git commits or pushes** (CLAUDE.md). Commit steps are omitted.
- Object-style params for every TS function. kebab-case file names.
- Backend layering: route, then controller (`createController`), then service. E2E tests sit next to the service and call endpoints only, through `@tests/helpers`.
- **Header names, exactly:** `CF-Access-Client-Id`, `CF-Access-Client-Secret`.
- **Env names, exactly:** `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`. Both must be non-blank after trimming, or the feature is "not configured".
- **QR payload, exactly:** `{"v":1,"server":"<https origin, no trailing slash>","cfClientId":"…","cfClientSecret":"…"}`.
- **Dormant when unconfigured:** no env means the endpoint returns `null` and there's no card. No credentials on the phone means no headers.
- **Never** send Cloudflare credentials to an origin other than the configured server (scheme + host + port). Never log them. No deep link / URL scheme carries them.
- A Cloudflare rejection must **not** sign the user out (must not call `onUnauthenticated` / `expireSession`).
- **Web copy:** `en` + `uk` together, via the `i18n-editor` agent. Read `.claude/skills/frontend-rules/SKILL.md` before frontend work. Use container queries, not viewport breakpoints.
- **iOS copy:** SwiftUI literals / `String(localized:)` (`ios/MoneyMatter/Resources/Localizable.xcstrings`).
- Comments describe current code, not history.

## Review Focus

1. **iPhone with a token, but the server isn't behind Access** (self-host, or before the gate is on): requests must still succeed. Headers are harmless. → Task 4 test "sends Cloudflare headers and still decodes a normal response".
2. **Wrong or revoked token at app launch:** the user stays signed in, sees the Cloudflare message, and can fix the token from the launch screen. → Task 5 test "a Cloudflare rejection during restore keeps the session and sets launchError".
3. **QR scanned from a phishing site** (another host, or http): it must be refused or clearly confirmed. → Task 4 payload tests for `http` and malformed input. Task 6 shows the host before saving.
4. **The browser is offline, or the backend is genuinely down:** the web app must not reload-loop. → Task 3 tests "does not reload when offline", "does not reload when the probe is not a redirect", "does not reload twice within 60 s".
5. **Non-admin or signed-out caller asking for the token:** 401, no secret. → Task 1 e2e error cases.

---

### Task 1: Backend endpoint – admin-only device setup

**Files:**

- Create: `packages/backend/src/services/cloudflare-access/get-device-setup.service.ts`
- Modify: `packages/backend/src/controllers/admin.controller.ts`, `packages/backend/src/routes/admin.route.ts`
- Modify: `packages/shared/src/types/…` (where other API response types live): add `CloudflareAccessDeviceSetup`
- Create test: `packages/backend/src/services/cloudflare-access/get-device-setup.e2e.ts`
- Create helper: `packages/backend/src/tests/helpers/cloudflare-access.ts`, re-exported from `tests/helpers/index.ts`
- Modify docs: `self-hosting/docs/environment-reference.md` (two rows for the env vars)

**Interfaces:**

- Produces:
  - `interface CloudflareAccessDeviceSetup { serverUrl: string; clientId: string; clientSecret: string }` from `@bt/shared/types`.
  - `getCloudflareAccessDeviceSetup(): CloudflareAccessDeviceSetup | null`. It reads `process.env` at call time. `serverUrl` = `(AUTH_ORIGIN || 'https://localhost:8100')` without trailing slashes.
- Endpoint: `GET /api/v1/admin/cloudflare-access`, guarded by `authenticateSession, adminOnly`. It responds `{ status: 'success', response: CloudflareAccessDeviceSetup | null }` with the header `Cache-Control: no-store`.
- Test helper: `getCloudflareAccessDeviceSetup<R>({ raw }: { raw?: R })`, which calls `makeRequest({ method: 'get', url: '/admin/cloudflare-access', raw })`.

- [ ] **Step 1: Write e2e tests.** Copy the env save/restore pattern from `services/admin/user-plan.e2e.ts` for `ADMIN_USERS`, `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET`.
  - `returns the server URL and token to an admin when configured`:
    - Set `ADMIN_USERS='test1'`, `CF_ACCESS_CLIENT_ID='abc.access'`, `CF_ACCESS_CLIENT_SECRET='s3cret'`.
    - Expect `raw` toEqual `{ serverUrl: <AUTH_ORIGIN or default, trailing slash stripped>, clientId: 'abc.access', clientSecret: 's3cret' }`.
    - Expect the non-raw response header `cache-control` toContain `no-store`.
  - `returns null when the token is not configured`: delete both CF vars, then expect `raw` toBeNull.
  - `returns null when only one value is set or a value is blank`: id set with secret `'   '`, then expect null.
  - `rejects a non-admin with 401`: `ADMIN_USERS='someone-else'`, then expect status 401.
  - `rejects a signed-out request with 401`: use `withoutSession` from `tests/helpers/share.ts`.
- [ ] **Step 2: Run** with test-runner: `npm run test:e2e -- --testPathPattern='cloudflare-access/get-device-setup.e2e'`. Expected: FAIL (route missing).
- [ ] **Step 3: Implement** the service, controller `adminGetCloudflareAccessDeviceSetup` (sets the header on `res`, returns `{ data }`), route line, shared type, helper and docs rows.
- [ ] **Step 4: Run** the same command. Expected: PASS.

### Task 2: Web – "iPhone access" card with QR (depends on Task 1)

**Files:**

- Create: `packages/frontend/src/api/cloudflare-access.ts`
- Create: `packages/frontend/src/pages/settings/subpages/security/components/iphone-access-section.vue`
- Create: `packages/frontend/src/js/helpers/cloudflare-access-qr-payload.ts`, with a unit test next to it (follow the frontend's existing unit-test naming/runner)
- Modify: `packages/frontend/src/common/const/vue-query.ts` (key `cloudflareAccessDeviceSetup: ['admin', 'cloudflare-access']`)
- Modify: `packages/frontend/src/pages/settings/subpages/security/components/login-methods.vue` (render the section at the end)
- Modify: `packages/frontend/package.json` (add `uqr`)
- i18n via the `i18n-editor` agent: `settings.security.iphoneAccess.*`

**Interfaces:**

- Consumes: `GET /admin/cloudflare-access` and `CloudflareAccessDeviceSetup` from Task 1.
- Produces:
  - `getCloudflareAccessDeviceSetup(): Promise<CloudflareAccessDeviceSetup | null>`
  - `buildCloudflareAccessQrPayload({ serverUrl, clientId, clientSecret }: CloudflareAccessDeviceSetup): string`

- [ ] **Step 1: Unit test** `buildCloudflareAccessQrPayload`:
  - `JSON.parse(result)` equals `{ v: 1, server: 'https://budget.example.com', cfClientId: 'abc.access', cfClientSecret: 's3cret' }`.
  - A trailing slash in `serverUrl` is stripped.
- [ ] **Step 2: Run** with test-runner (frontend unit script). Expected: FAIL.
- [ ] **Step 3: Implement** the helper, API module, cache key and section:
  - `useQuery` is `enabled` only when `useIsAdmin().isAdmin`.
  - The section renders only when the data is non-null.
  - Collapsed by default: a title, one line of explanation, and a "Show" button.
  - When shown: the QR as `uqr` `renderSVG(payload)`, the Client ID and Secret with copy buttons (`useClipboard`), and "Hide".
  - **Keys:** `title` "iPhone access", `description` "Scan this in the MoneyMatter iPhone app to let it through Cloudflare Access.", `show` "Show code", `hide` "Hide", `clientId` "Client ID", `clientSecret` "Client secret", `copy` "Copy", `copied` "Copied", `warning` "Anyone with this code can reach your server's sign-in page. Don't share it."
- [ ] **Step 4: Run** the unit test (PASS) and the linter (frontend lint + vue-tsc).

### Task 3: Web – recover from an expired Cloudflare session; manifest credentials

**Files:**

- Create: `packages/frontend/src/js/helpers/cloudflare-session-recovery.ts`, plus a unit test
- Modify: `packages/frontend/src/api/_api.ts` (the `TypeError`/`NetworkError` branch around :262)
- Modify: `packages/frontend/src/lib/auth-client.ts` (`fetchOptions.customFetchImpl`, or a hook that sees network failures)
- Modify: `packages/frontend/index.html:11`: add `crossorigin="use-credentials"`

**Interfaces:**

- Produces:
  - `recoverFromExpiredCloudflareSession({ fetchImpl = fetch, storage = sessionStorage, reload = () => window.location.reload(), now = Date.now(), isOnline = navigator.onLine }?): Promise<boolean>` returns whether it reloaded.
  - Algorithm:
    - Return false if offline.
    - Return false if `storage['cf-access-reload-at']` is within 60 000 ms of `now`.
    - Probe `fetchImpl('/site.webmanifest', { redirect: 'manual', credentials: 'include', cache: 'no-store' })`.
    - Only if `response.type === 'opaqueredirect'`: store `now`, call `reload()`, return true.
    - Any probe error: return false.

- [ ] **Step 1: Unit tests**, all with injected fakes:
  - `reloads when the probe is redirected`
  - `does not reload when the probe is not a redirect`
  - `does not reload when offline`
  - `does not reload twice within 60 s`
  - `returns false when the probe itself throws`
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the helper. Call it (fire-and-forget) where `_api.ts` turns a fetch `TypeError` into `NetworkError`, and on network failures of the better-auth client. Make the manifest change.
- [ ] **Step 4: Run** the tests (PASS) and the linter.

### Task 4: iOS Kit – credentials, payload, header injection, Cloudflare rejection

**Files (all under `ios/MoneyMatterKit/`):**

- Create: `Sources/MoneyMatterKit/CloudflareAccess/CloudflareAccessCredentials.swift`
- Create: `Sources/MoneyMatterKit/CloudflareAccess/CloudflareAccessSetupPayload.swift`
- Modify: `Sources/MoneyMatterKit/API/APIClient.swift`, `API/APIError.swift`
- Modify: the ad-hoc sessions in `SettingsSections/SettingsSecurity.swift`, `SettingsUpload.swift`, `TransactionAttachmentTransfer.swift`, `DataUpload.swift` (wherever they live in the Kit)
- Modify: `Tests/MoneyMatterKitTests/Support/URLProtocolStub.swift` (`stubbed(...)` gains `cloudflareAccess:`, defaulted)
- Create tests: `Tests/MoneyMatterKitTests/CloudflareAccessTests.swift`

**Interfaces (Produces):**

```swift
public struct CloudflareAccessCredentials: Sendable, Equatable, Codable {
  public let clientId: String; public let clientSecret: String
  public init?(clientId: String, clientSecret: String)   // trims; nil if either is blank
  public var headers: [String: String]                    // the two CF-Access-* headers
}
public protocol CloudflareAccessProviding: Sendable { func cloudflareAccessCredentials() -> CloudflareAccessCredentials? }
public struct CloudflareAccessSetupPayload: Sendable, Equatable {
  public let server: ServerEndpoint; public let credentials: CloudflareAccessCredentials
  public static func parse(_ text: String) throws(CloudflareAccessSetupPayloadError) -> CloudflareAccessSetupPayload
}
public enum CloudflareAccessSetupPayloadError: Error, Equatable { case malformed, unsupportedVersion, insecureServer, missingCredentials }
// APIClient
public init(..., cloudflareAccess: (any CloudflareAccessProviding)? = nil)  // kept by withEphemeralCookieJar() and withoutToken()
public func cloudflareAccessHeaders(for url: URL) -> [String: String]       // [:] unless url matches server origin and credentials exist
static func cloudflareRejection(_ response: HTTPURLResponse) -> APIError?    // .cloudflareBlocked or nil
// APIError: new case
case cloudflareBlocked   // isUnauthenticated == false; message "Cloudflare blocked this request. Update the Cloudflare token."
```

- **`makeRequest`** merges `cloudflareAccessHeaders(for: request.url)`.
- **Redirects:** every session the client uses refuses redirects to hosts ending in `cloudflareaccess.com`. Use one shared `URLSessionTaskDelegate`, attached by `makeURLSession` and by a single helper that replaces the three ad-hoc `URLSession(configuration:)` calls.
- **Rejection:** `cloudflareRejection` returns `.cloudflareBlocked` in two cases:
  - status 300–399 with a `Location` host ending in `cloudflareaccess.com`;
  - status 401 or 403 whose `Content-Type` isn't JSON and that has a `cf-ray` header.

  It runs before `mapError` in `response(for:)` **and** in the four extension paths.

- **Payload parsing:**
  - `v` must be `1`.
  - `server` must parse via `ServerEndpoint(validating:)` and be `https`.
  - Both credentials must be non-blank.

- [ ] **Step 1: Swift Testing tests** in `CloudflareAccessTests.swift`:
  - `credentials trim and reject blanks`
  - `sends Cloudflare headers and still decodes a normal response` (the stub asserts both header values)
  - `sends no Cloudflare headers without credentials`
  - `withEphemeralCookieJar keeps Cloudflare credentials`
  - `maps a redirect to cloudflareaccess.com to cloudflareBlocked without calling onUnauthenticated`: 302 with `Location: https://team.cloudflareaccess.com/cdn-cgi/access/login/x`. Assert the error equals `.cloudflareBlocked` and the callback count is 0.
  - `maps an HTML 403 with cf-ray to cloudflareBlocked`
  - `keeps an app JSON 401 as unauthenticated`
  - `cloudflareAccessHeaders is empty for another origin`
  - `parses a valid setup payload`
  - `rejects an http server` (`.insecureServer`)
  - `rejects malformed JSON` (`.malformed`)
  - `rejects a missing secret` (`.missingCredentials`)
  - `rejects an unsupported version` (`.unsupportedVersion`)
- [ ] **Step 2: Run** with test-runner: `swift test` in `ios/MoneyMatterKit` (or the scheme's test action). Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS, with the existing Kit tests still green.

### Task 5: iOS – Keychain storage and wiring (depends on Task 4)

**Files:**

- Create: `ios/MoneyMatterKit/Sources/MoneyMatterKit/CloudflareAccess/KeychainCloudflareAccessStore.swift` (in the Kit so app, widget and background task share it)
- Modify:
  - `ios/MoneyMatter/Services/ServerConnection.swift` (pass `cloudflareAccess:`)
  - `ios/MoneyMatterWidget/MonthlyBudgetProvider.swift`
  - `ios/MoneyMatter/Platform/MonthlyBudgetAlerts.swift`
  - `ios/MoneyMatter/Platform/WebAuthenticator.swift` (`additionalHeaderFields`)
  - `ios/MoneyMatter/App/SessionStore.swift`
  - `ios/MoneyMatterTests/SessionStoreStubs.swift`
- Test: `ios/MoneyMatterTests/SessionStoreTests.swift`

**Interfaces:**

```swift
public protocol CloudflareAccessStoring: AnyObject, Sendable {
  func credentials(for server: ServerEndpoint) -> CloudflareAccessCredentials?
  func save(_ credentials: CloudflareAccessCredentials, for server: ServerEndpoint) throws
  func delete(for server: ServerEndpoint)
  func provider(for server: ServerEndpoint) -> any CloudflareAccessProviding   // reads live, so updates apply without rebuilding clients
}
public final class KeychainCloudflareAccessStore: CloudflareAccessStoring
// service "\(SharedContainer.keychainService).cloudflare-access", accessGroup SharedContainer.keychainAccessGroup,
// account server.hostAndPort, value JSON-encoded credentials, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
// same errSecMissingEntitlement fallback as KeychainTokenStore.
protocol WebAuthenticating { func authenticate(url: URL, callbackScheme: String, additionalHeaders: [String: String]) async throws -> URL }
// SessionStore
func connect(toServer address: String, cloudflareAccess: CloudflareAccessCredentials?) async throws  // saves (or deletes) for the validated endpoint BEFORE probing; deletes again if the probe fails
func updateCloudflareAccess(_ credentials: CloudflareAccessCredentials?) async throws                 // saves or deletes for the current endpoint, then retryLaunch() if launchError == .cloudflareBlocked
var cloudflareAccessCredentials: CloudflareAccessCredentials? { get }                                  // for the current endpoint
// changeServer() also deletes the credentials of the server being left.
```

- `SessionStore.signIn(with:)` passes `api.cloudflareAccessHeaders(for: startURL)` to the web authenticator.

- [ ] **Step 1: Tests** in `SessionStoreTests` with an in-memory `CloudflareAccessStoring` stub:
  - `connect saves Cloudflare credentials before probing`
  - `connect removes credentials when the probe fails`
  - `a Cloudflare rejection during restore keeps the session and sets launchError`: the restore throws `.cloudflareBlocked`. The state stays `.launching`, the token is not deleted, and `launchError == .cloudflareBlocked`.
  - `updating the Cloudflare token retries the launch`
  - `changing server deletes the old server's credentials`
  - `OAuth sign-in passes Cloudflare headers to the web authenticator`
- [ ] **Step 2: Run** with test-runner via the MoneyMatter scheme test action (simulator). Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.

### Task 6: iOS – UI: server screen, Settings, scanner, launch and sign-in recovery (depends on Task 5)

**Files:**

- Create:
  - `ios/MoneyMatter/Features/CloudflareAccess/CloudflareAccessEditor.swift`: the fields, a Scan button, Save and Remove. Reused everywhere.
  - `ios/MoneyMatter/Features/CloudflareAccess/CloudflareAccessScanner.swift`: `UIViewControllerRepresentable` over `DataScannerViewController` (QR only). It parses with `CloudflareAccessSetupPayload.parse`, and shows the host for confirmation before handing back the payload.
  - `ios/MoneyMatter/Features/SettingsSections/CloudflareAccessScreen.swift`
- Modify:
  - `ios/MoneyMatter/Features/Auth/ServerView.swift`: a collapsed "Cloudflare Access" `DisclosureGroup` with Client ID, Client Secret (`SecureField`) and "Scan QR Code". A scan also fills the address. Connect passes the credentials.
  - `ios/MoneyMatter/Features/Settings/SettingsView.swift`: add a `securitySection` row "Cloudflare Access" (`systemImage: "lock.shield"`).
  - `ios/MoneyMatter/App/LaunchView.swift`: when `launchError == .cloudflareBlocked`, show the title "Cloudflare Blocked the Connection", the error message, and the buttons "Update Cloudflare Token" (editor sheet), "Try Again" and "Sign Out".
  - `ios/MoneyMatter/Features/Auth/SignInView.swift`: a "Cloudflare Access" entry (e.g. next to the server chip) that opens the editor sheet.
  - `ServerView.message(for:)`: handle `.cloudflareBlocked`.
  - `project.pbxproj` (both configs): `INFOPLIST_KEY_NSCameraUsageDescription = "MoneyMatter uses the camera to photograph receipts and to scan the Cloudflare Access code from your server's settings.";`

- [ ] **Step 1: Implement.** These are views, so behavior is covered by Task 4 and 5 tests.
- [ ] **Step 2: Build and run** the full app test action with test-runner. Expected: build succeeds and all tests PASS.

### Task 7: Setup guide

**Files:** create `self-hosting/docs/cloudflare-access.md`, and link it from the self-hosting docs index (or README) if one lists guides.

- [ ] **Step 1: Write the guide** from the spec, sections 1 and 6:
  - prerequisites (tunnel, Zero Trust team);
  - the AASA bypass app, then the main app with its two policies (Allow by email, Service Auth by token), session 1 week;
  - the service token (1 year; the secret is shown once);
  - `.env` (`CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`, `ADMIN_USERS`) and a restart;
  - phone setup (scan in Settings → Security → Login methods → iPhone access);
  - the rollout order;
  - what stops working (MCP connector, GitHub release webhook, public landing/legal pages);
  - troubleshooting:
    - "Allow" instead of "Service Auth";
    - "Cloudflare Blocked the Connection" on the phone;
    - `curl` check.
- [ ] **Step 2: Format** check via the linter (`oxfmt --check`).

### Final: whole-branch review

- [ ] `code-change-reviewer` over the branch diff, plus `ecc:swift-reviewer` over the iOS diff. Fix confirmed issues.
- [ ] One combined e2e run (Task 1 file + auth suites), frontend unit tests, Kit + app tests, and the linter on backend and frontend.
