# Over-the-air iPhone updates

`release.sh` builds MoneyMatter and uploads it to your MoneyMatter server. The
next time the app opens on your iPhone, it shows **Update available** with the
release notes. **Install Now** hands the build to iOS, which downloads it from
your server and installs it over the current app, keeping its data and sign-in.
After the first install there is no cable, App Store or TestFlight involved.

The build is signed for development, so it installs only on iPhones registered
in your Apple developer account.

## How it works

1. `release.sh` stamps a build number (UTC `yyDDDHHMM`, for example
   `263231351`), archives the app in Release and exports a development-signed
   IPA to `ios/build/ota/export/MoneyMatter.ipa`.
2. `publish-app-update.sh` uploads the IPA to
   `POST /api/v1/app-updates/upload` with the upload token. The server checks
   that the file is an iPhone app with that build number, newer than the
   current build and with the same bundle ID. It keeps the current and the
   previous build and deletes older ones.
3. The app asks `GET /api/v1/app-updates/latest` when it opens, and when you
   tap **Settings → Check for Updates**. If the server has a newer build, the
   app shows **Update available**.
4. **Install Now** opens a link the server signed for that one build. It
   expires after 10 minutes. iOS fetches the install manifest (`/ota/m/…`) and
   the IPA (`/ota/d/…`) on its own, without the app's session or Cloudflare
   token, so `/ota/` must be reachable without signing in.

## One-time setup

### 1. Server

Add to the server's `.env`:

```bash
APP_UPDATE_UPLOAD_TOKEN=<output of: openssl rand -hex 32>
ADMIN_USERS=<your MoneyMatter username>
APP_UPDATES_DIR=/app/packages/backend/data/app-updates
```

Builds are stored in `APP_UPDATES_DIR`. Keep it on a volume, or recreating
the container deletes them. In `docker-compose.yml`, mount one next to the
attachments volume:

```yaml
services:
  backend:
    volumes:
      - 'attachments_data:/app/packages/backend/data/attachments'
      - 'app_updates_data:/app/packages/backend/data/app-updates'

volumes:
  app_updates_data:
```

Apply the change with `docker compose up -d`.

| Variable                  | Purpose                                                                                                                             |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `ADMIN_USERS`             | Comma-separated usernames. The app's update check (`/latest`) answers only these, so the owner's username must be listed            |
| `APP_UPDATE_UPLOAD_TOKEN` | Secret the publish script sends to upload and roll back builds, at least 32 characters. Unset or shorter, both endpoints answer 404 |
| `APP_UPDATES_DIR`         | Where builds are stored. Defaults to `data/app-updates` under the backend's working directory                                       |
| `APP_UPDATES_PUBLIC_URL`  | https origin iOS downloads updates from. Defaults to `AUTH_ORIGIN`                                                                  |
| `APP_UPDATES_SIGNING_KEY` | Key that signs install links, at least 32 characters. Defaults to a key derived from `BETTER_AUTH_SECRET`                           |

Two more requirements:

- The public URL must be https, with a certificate iOS trusts (a Cloudflare
  Tunnel provides one). Over plain http the app learns about the update but
  gets no install link.
- Every proxy between the internet and the backend must pass `/ota/` through
  to the backend, like `/api/`, and accept request bodies larger than the IPA
  on `/api/v1/app-updates/upload`. The
  [reverse proxy recipes](../../self-hosting/docs/reverse-proxies.md) set
  `client_max_body_size 15m`, which is too small for most IPAs. Cloudflare
  caps request bodies at 100 MB on Free and Pro plans; the server accepts up to
  1 GiB.

### 2. Cloudflare Access

If the app sits behind Cloudflare Access, add the **OTA bypass** application
from the
[Cloudflare Access guide](../../self-hosting/docs/cloudflare-access.md#b-bypass-application-for-over-the-air-iphone-updates).
The upload and rollback endpoints stay behind the gate. The publish script
passes it with a service token, set up in the next step.

### 3. Your Mac

- Xcode is signed in to an Apple ID on team `VY5CNF8734`. For another team,
  set `DEVELOPMENT_TEAM`.
- Create `ios/scripts/.ota.env`. It is gitignored; never commit it.

  ```bash
  MM_SERVER=https://budget.example.com
  MM_UPLOAD_TOKEN=<APP_UPDATE_UPLOAD_TOKEN from the server>
  # Only behind Cloudflare Access: a service token the main application's
  # Service Auth policy accepts.
  MM_CF_ACCESS_CLIENT_ID=<client id>
  MM_CF_ACCESS_CLIENT_SECRET=<client secret>
  ```

  The same variables can come from the environment instead. The environment
  wins over the file.

### 4. The iPhone

1. Register the iPhone in your Apple developer account, so the development
   profile includes it. Either connect it by cable and build to it once from
   Xcode (automatic signing registers it), or add its UDID under
   developer.apple.com → Certificates, IDs & Profiles → Devices. Developer
   Mode must be on, as for `ios/deploy-iphone.sh`.
2. Install the first build by cable. The updater ships inside the app, so the
   first update-capable build can't arrive over the air. Use a build from
   `release.sh`: a build from Xcode or `ios/deploy-iphone.sh` carries build
   number 1, which the server treats as an unstamped development build and
   never offers updates to.

   ```bash
   ios/scripts/release.sh --notes "• Over-the-air updates"
   xcrun devicectl list devices   # note the iPhone's identifier
   xcrun devicectl device install app --device <identifier> ios/build/ota/export/MoneyMatter.ipa
   ```

   This replaces a build installed with `ios/deploy-iphone.sh` and keeps its
   data.

## Each release

```bash
ios/scripts/release.sh --notes "• Faster sync
• New widget sizes"
```

The script archives, exports and uploads, then prints the server's reply. Put
one `• ` line per item in the notes. On the iPhone, open MoneyMatter and
**Update available** appears. To check straight away, tap **Settings → Check
for Updates**. Tap **Install Now** and confirm iOS's prompt; the Home Screen
icon shows the download.

- The version shown in the app is `MARKETING_VERSION` from the Xcode project.
  Change it there for a new visible version. Whether a build is newer depends
  on the build number alone.
- `--no-publish` stops after the IPA. Publish it later with
  `ios/scripts/publish-app-update.sh --file ios/build/ota/export/MoneyMatter.ipa`.
- `BUILD_NUMBER=<n>` overrides the stamp. It must be higher than the last
  published build.

### Rolling back

```bash
ios/scripts/publish-app-update.sh --rollback
```

The previous build becomes current again, so iPhones still on an older build
aren't offered the bad one. An iPhone that already installed it needs a new,
higher build: fix the problem and run `release.sh` again.

## Troubleshooting

| Symptom                                  | Cause                                                                                                                         |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Upload answers HTTP 401                  | `MM_UPLOAD_TOKEN` doesn't match the server's `APP_UPDATE_UPLOAD_TOKEN`                                                        |
| Upload answers HTTP 404                  | `APP_UPDATE_UPLOAD_TOKEN` isn't set on the server, or the stack wasn't restarted after setting it                             |
| Upload answers HTTP 409                  | The build isn't newer than the current one, or its bundle ID differs. The reply says which                                    |
| Upload answers HTTP 413                  | The IPA is over a request-size limit: Cloudflare's 100 MB, or a proxy's `client_max_body_size`                                |
| "The server redirected (HTTP 302)"       | Cloudflare Access sent the upload to its login page: `MM_CF_ACCESS_*` is missing, or the token isn't in a Service Auth policy |
| The app never shows **Update available** | The iPhone runs build 1 from Xcode or `deploy-iphone.sh`: install a `release.sh` build by cable once                          |
| iOS says the app can't be installed      | The iPhone isn't in the development profile (register it and release again), or `/ota/` isn't reachable without signing in    |

To check `/ota/`, run `curl -sI https://budget.example.com/ota/m/invalid.plist`.
Expect `403` from the app. A redirect to Cloudflare means the bypass is
missing; a `200` with the web app's HTML means a proxy isn't passing `/ota/` to
the backend.
