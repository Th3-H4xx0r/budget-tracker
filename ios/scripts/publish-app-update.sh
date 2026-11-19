#!/bin/bash
# Upload an iPhone build to the MoneyMatter server, which then offers it to the app as
# "Update available". ios/scripts/release.sh calls this after exporting the IPA.
#   ios/scripts/publish-app-update.sh --file MoneyMatter.ipa --build 263231351 --notes "• line one"
#   ios/scripts/publish-app-update.sh --rollback      # the previous build becomes current again
# Settings come from the environment or ios/scripts/.ota.env (gitignored); see usage below.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.ota.env"

usage() {
  cat <<'EOF'
Usage: ios/scripts/publish-app-update.sh --file <ipa> [--build <n>] [--notes <text>] [--commit <sha>]
       ios/scripts/publish-app-update.sh --rollback

  --file <ipa>     Development-signed IPA to publish
  --build <n>      Its build number (default: CFBundleVersion read from the IPA)
  --notes <text>   What's new, one "• " line per item
  --commit <sha>   Commit it was built from (default: git describe, with -dirty for uncommitted edits)
  --rollback       Make the previous build current again. Stops iPhones still on an older build
                   from being offered the current one; an iPhone that already installed it needs
                   a new, higher build to move off it.

Settings, from the environment or ios/scripts/.ota.env (the environment wins):
  MM_SERVER                    Server URL, e.g. https://budget.example.com
  MM_UPLOAD_TOKEN              The server's APP_UPDATE_UPLOAD_TOKEN
  MM_CF_ACCESS_CLIENT_ID       Cloudflare Access service token, when the server sits behind
  MM_CF_ACCESS_CLIENT_SECRET   Cloudflare Access (set both or neither)
EOF
}

need_value() { [ $# -ge 2 ] || { echo "$1 needs a value" >&2; exit 2; }; }
file="" build="" notes="" commit="" rollback=0
while [ $# -gt 0 ]; do
  case "$1" in
    --file) need_value "$@"; file="$2"; shift 2 ;;
    --build) need_value "$@"; build="$2"; shift 2 ;;
    --notes) need_value "$@"; notes="$2"; shift 2 ;;
    --commit) need_value "$@"; commit="$2"; shift 2 ;;
    --rollback) rollback=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$rollback" = 0 ]; then
  [ -f "$file" ] || { echo "--file must be an existing .ipa" >&2; exit 2; }
  if [ -z "$build" ]; then
    build=$(python3 -I - "$file" <<'PY'
import plistlib, re, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as zf:
    name = next(n for n in zf.namelist() if re.match(r"^Payload/[^/]+\.app/Info\.plist$", n))
    print(plistlib.loads(zf.read(name))["CFBundleVersion"])
PY
)
  fi
  if [ "${#notes}" -gt 2000 ]; then
    echo "warning: the notes are ${#notes} characters; the server keeps the first 2000" >&2
    notes="${notes:0:2000}"
  fi
  [[ "$build" =~ ^[0-9]+$ ]] || { echo "--build must be a whole number, got: $build" >&2; exit 2; }
  commit="${commit:-$(git -C "$SCRIPT_DIR" describe --always --dirty 2>/dev/null || true)}"
fi

# Values already in the environment win over the file, so one run can point elsewhere.
if [ -f "$ENV_FILE" ]; then
  preset=""
  for v in MM_SERVER MM_UPLOAD_TOKEN MM_CF_ACCESS_CLIENT_ID MM_CF_ACCESS_CLIENT_SECRET; do
    if [ -n "${!v:-}" ]; then preset+="$v=$(printf %q "${!v}")"$'\n'; fi
  done
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  eval "$preset"
fi
: "${MM_SERVER:?set it to the server URL, e.g. https://budget.example.com, in the environment or $ENV_FILE}"
: "${MM_UPLOAD_TOKEN:?set it to APP_UPDATE_UPLOAD_TOKEN from the server, in the environment or $ENV_FILE}"
MM_SERVER="${MM_SERVER%/}"
if [ -n "${MM_CF_ACCESS_CLIENT_ID:-}" ] || [ -n "${MM_CF_ACCESS_CLIENT_SECRET:-}" ]; then
  [ -n "${MM_CF_ACCESS_CLIENT_ID:-}" ] && [ -n "${MM_CF_ACCESS_CLIENT_SECRET:-}" ] \
    || { echo "set both MM_CF_ACCESS_CLIENT_ID and MM_CF_ACCESS_CLIENT_SECRET, or neither" >&2; exit 2; }
fi

# The tokens go to curl through a header file, not its arguments, so they never show up in ps.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
{
  printf 'Authorization: Bearer %s\n' "$MM_UPLOAD_TOKEN"
  if [ -n "${MM_CF_ACCESS_CLIENT_ID:-}" ]; then
    printf 'CF-Access-Client-Id: %s\nCF-Access-Client-Secret: %s\n' \
      "$MM_CF_ACCESS_CLIENT_ID" "$MM_CF_ACCESS_CLIENT_SECRET"
  fi
} > "$tmp/headers"

# post <url> [curl args...]: prints the server's reply and fails unless it answered 2xx.
post() {
  local url="$1" code status=0
  shift
  code="$(curl --fail-with-body -X POST -H @"$tmp/headers" -o "$tmp/response" -w '%{http_code}' \
    "$@" "$url")" || status=$?
  if [ -s "$tmp/response" ]; then cat "$tmp/response"; echo; fi
  case "$code" in
    2??) [ "$status" = 0 ] && return 0 ;;
    30?) echo "The server redirected (HTTP $code), most likely to the Cloudflare Access login:" \
           "set MM_CF_ACCESS_CLIENT_ID/SECRET to a service token the Access policy accepts." >&2 ;;
    401) echo "HTTP 401: MM_UPLOAD_TOKEN doesn't match the server's APP_UPDATE_UPLOAD_TOKEN." >&2 ;;
    404) echo "HTTP 404: the server has no APP_UPDATE_UPLOAD_TOKEN set, or predates app updates." >&2 ;;
    414) echo "HTTP 414: the request URL is too long, most likely the --notes text: shorten the notes." >&2 ;;
    413) echo "HTTP 413: the IPA is over a request-size limit (Cloudflare, a reverse proxy, or the server's 1 GiB)." >&2 ;;
    *) echo "Request failed (HTTP $code, curl exit $status)." >&2 ;;
  esac
  exit 1
}

if [ "$rollback" = 1 ]; then
  echo "==> Rolling back to the previous iOS build on $MM_SERVER"
  post "$MM_SERVER/api/v1/app-updates/rollback?platform=ios" --silent --show-error
  exit 0
fi

quote() { python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }
size="$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")"
if [ "$size" -gt $((95 * 1048576)) ]; then
  echo "warning: the IPA is $((size / 1048576)) MB; Cloudflare rejects request bodies over 100 MB on Free and Pro plans" >&2
fi
echo "==> Publishing iOS build $build ($((size / 1048576)) MB) to $MM_SERVER"
post "$MM_SERVER/api/v1/app-updates/upload?platform=ios&build=$build&notes=$(quote "$notes")&commit=$(quote "$commit")" \
  --progress-bar -H 'Content-Type: application/octet-stream' --data-binary @"$file"
