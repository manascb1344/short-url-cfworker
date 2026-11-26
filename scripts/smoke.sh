#!/usr/bin/env bash
set -euo pipefail

PORT=8787
BASE="http://127.0.0.1:${PORT}"

printf 'ADMIN_PASSWORD=smoke-test-password\n' > .dev.vars

pnpm exec wrangler dev --local --port "$PORT" &
server_pid=$!
cleanup() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  rm -f .dev.vars
}
trap cleanup EXIT

admin_status=000
for ((i = 0; i < 30; i++)); do
  admin_status=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/admin/" || true)
  if [[ "$admin_status" == "200" ]]; then
    break
  fi
  sleep 1
done
echo "admin_page_status=$admin_status"
if [[ "$admin_status" != "200" ]]; then
  echo "FAIL: admin page did not return 200 within 30 seconds"
  exit 1
fi

# The admin page is a static asset and does not run the Worker. Request the
# home page so ensureSchema creates the links table before the insert.
curl -s -o /dev/null "$BASE/"

pnpm exec wrangler d1 execute short-url --local --command "INSERT OR REPLACE INTO links (slug, url, created_at, updated_at) VALUES ('smoke', 'https://example.com', 0, 0)"

headers=$(curl -sI "$BASE/smoke")
redirect_status=$(awk 'NR == 1 { print $2 }' <<< "$headers")
location=$(awk 'tolower($1) == "location:" { sub(/\r$/, "", $2); print $2 }' <<< "$headers")
echo "redirect_status=$redirect_status"
echo "location_header=$location"

failed=0
if [[ "$redirect_status" != "302" ]]; then
  echo "FAIL: expected HTTP 302, got $redirect_status"
  failed=1
fi
if [[ "$location" != "https://example.com" ]]; then
  echo "FAIL: expected Location https://example.com, got $location"
  failed=1
fi
exit "$failed"
