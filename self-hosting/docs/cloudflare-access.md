# Cloudflare Access

Cloudflare Access puts a login gate in front of the whole app. A request has
to pass the gate before it reaches the app, so the app's own sign-in is the
second layer, not the only one.

Two kinds of client get through:

- **You, in a browser.** Cloudflare's login page comes first. After you pass
  it, the app's own sign-in page appears as usual.
- **The iPhone app.** It can't sign in through a browser page, so it sends a
  service token with every request. Cloudflare checks the token and passes the
  request on.

This guide assumes your domain is on Cloudflare and the app is reached through
a Cloudflare Tunnel, so the server has no open inbound ports and all traffic
goes through Cloudflare. Examples use `budget.example.com` and `<team>` for your
Zero Trust team name; replace them with your own.

## Prerequisites

- The app is reachable at its domain through a Cloudflare Tunnel.
- A Cloudflare Zero Trust team, with access to the Zero Trust dashboard.
- Your app username, the one you sign in with. It goes into `ADMIN_USERS`.
- Shell access to the server, running the stack with Docker Compose.

## Rollout order

Do these in order, so the phone is never locked out:

1. Update to a release with Cloudflare Access support. Nothing changes until
   the variables below are set.
2. Create a service token, put it in `.env`, and restart.
3. Set up the iPhone app with the QR card.
4. Create the Access applications.
5. Check the gate with `curl`.

## 1. Create a service token

In the Zero Trust dashboard, go to **Access → Service auth → Service Tokens**
and choose **Create Service Token**. Name it after the phone, for example
`budget-tracker-iphone`, and set the duration to 1 year.

Cloudflare shows the **Client ID** and **Client Secret** once, at creation.
Copy both before you leave the page.

## 2. Configure the server

Add these to `.env`:

```bash
CF_ACCESS_CLIENT_ID=<client id from step 1>
CF_ACCESS_CLIENT_SECRET=<client secret from step 1>
ADMIN_USERS=<your username>
```

`ADMIN_USERS` is a comma-separated list. Only admins see the iPhone access card,
so your username must be in it. The Cloudflare variables are optional: leave
them empty and the app behaves as it did before.

Apply the change:

```bash
docker compose up -d
```

The full variable list is in the [environment reference](environment-reference.md).

## 3. Set up the iPhone

1. In the web app, go to **Settings → Security → Login methods** and open
   **iPhone access**. The card appears only for an admin, and only when both
   Cloudflare variables are set. The QR code and server URL assume a
   single-origin, https deployment, where `AUTH_ORIGIN` also serves `/api`.
2. Click **Show code** to reveal the QR code and the values. They stay hidden until
   you click, so nobody nearby can read them off the screen.
3. On the iPhone, open the server screen and expand the **Cloudflare Access**
   section. Either tap **Scan QR Code**, or paste the Client ID and Client
   Secret using the copy buttons on the card.
4. Once you are signed in, the same settings are under **Settings → Security →
   Cloudflare Access**.

## 4. Create the Access applications

Create each application under **Access → Applications → Add an application**,
choosing **Self-hosted**. Create the bypass applications first.

### a. Bypass application for the iOS app association file

- Domain: `budget.example.com`
- Path: `/.well-known/apple-app-site-association`
- Policy: Action **Bypass**, Include **Everyone**

iOS fetches this file on its own, without any token, to link the app to your
domain. The more specific path wins over the main application below.

### b. Bypass application for over-the-air iPhone updates

Needed only if you publish iPhone builds with `ios/scripts/release.sh` (see
[over-the-air iPhone updates](../../ios/scripts/README.md)).

- Name: `OTA bypass`
- Domain: `budget.example.com`
- Path: `/ota/`
- Policy: Action **Bypass**, Include **Everyone**

When you tap **Install Now** in the app, iOS's installer downloads the install
manifest and the app from `/ota/` on its own. It can't send the app's session
or the service token, so behind the gate it would get Cloudflare's login page
and the install would fail. The server answers `/ota/` only for links it
signed: each names one stored build and expires 10 minutes after the app asks
for it. Anything else gets a bare 403.

Uploading and rolling back builds go through `/api/v1/app-updates/`, which
stays behind the main application. The publish script sends a service token:
set `MM_CF_ACCESS_CLIENT_ID` and `MM_CF_ACCESS_CLIENT_SECRET` on the Mac you
release from. Use the token from step 1, or create a separate one and add it
to the **iPhone** policy below as a second Include.

### c. Main application

- Domain: `budget.example.com`, all paths
- Session duration: 1 week
- Policies:
  - **Owner**: Action **Allow**, Include → Emails → your email address.
    This is how you sign in through Cloudflare's login page in a browser.
  - **iPhone**: Action **Service Auth**, Include → Service Token → the token
    from step 1.

The iPhone policy's Action must be **Service Auth**. Under an **Allow** policy
Cloudflare ignores the service token and redirects the request to the login
page.

## 5. Verify the gate

Without a token, the request should be sent to Cloudflare:

```bash
curl -sI https://budget.example.com/api/v1/auth/signups-open
```

Expect a redirect whose `location` points at `<team>.cloudflareaccess.com`, not a
response from the app.

With the service token, the request should reach the app:

```bash
curl -sI \
  -H "CF-Access-Client-Id: <client id>" \
  -H "CF-Access-Client-Secret: <client secret>" \
  https://budget.example.com/api/v1/auth/signups-open
```

Expect `HTTP/2 200` from the app.

If you created the OTA bypass, a request under `/ota/` should reach the app
without a token:

```bash
curl -sI https://budget.example.com/ota/m/invalid.plist
```

Expect `HTTP/2 403` from the app, since the link isn't signed. A redirect to
Cloudflare means the bypass isn't in place.

In a browser, open `https://budget.example.com`. You should see Cloudflare's
login page before the app's sign-in page.

## Check after go-live

The iPhone's Google/GitHub sign-in sheet and the bank-consent callback are
first exercised against the gate when it goes live. If sign-in shows a
Cloudflare login inside the sheet, either temporarily add a Bypass for
`/api/v1/auth/native/oauth/*` and `/api/v1/auth/callback/*`, or sign in on the
phone with email/password or a passkey.

## What stops working

Once the gate is on, these callers can't pass Cloudflare, so they stop working:

- **MCP connectors** (Claude, ChatGPT). They can't send a service token or sign
  in through Cloudflare's login page.
- **The GitHub release webhook.** GitHub can't pass the gate either.
- **The public landing and legal pages.** They sit behind the same gate as the
  app.

## Troubleshooting

### The iPhone shows "Cloudflare blocked the connection"

The token is being rejected. Check, in order:

1. The iPhone policy's Action is **Service Auth**, not **Allow**.
2. The token in the app matches the one in `.env`. Run the second `curl` check
   above with the same values. A redirect means the token or the policy is
   wrong.
3. The token hasn't expired or been rotated.

To fix the token on the phone, use the **Update Cloudflare token** button on
the sign-in screen, or go to **Settings → Security → Cloudflare Access**. Paste
the values again or scan a fresh QR code.

### The curl check still redirects to Cloudflare

The policy is probably **Allow** instead of **Service Auth**. Change the
iPhone policy's Action; the token is ignored under an Allow policy.

### The iPhone access card doesn't appear

- Your username isn't in `ADMIN_USERS`, or the list is misspelled.
- One of the two Cloudflare variables is empty.
- The stack wasn't restarted after editing `.env`. Run `docker compose up -d`.

---

Setup guide: [setup-guide.md](setup-guide.md) · Environment variables:
[environment-reference.md](environment-reference.md)
