#!/usr/bin/env bash
# nix run .#verify
#
# Runs the checks from spec §11 against an already-running stack
# (`docker compose up -d proxy pi` or `nix run .#start-agent` first, in
# another terminal, or leave `pi` as a long-lived shell for this).
# This is a smoke test, not a substitute for reading the results.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$REPO_ROOT"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; FAILED=1; }
FAILED=0

echo "==> [1/5] pi has no route to the internet except via proxy's allowlist"
if docker compose exec -T pi sh -c 'wget -q -T 3 -O- https://example.com' >/dev/null 2>&1; then
  fail "pi reached a non-allowlisted host directly — egress isolation is broken"
else
  pass "direct outbound connection to a non-allowlisted host failed, as expected"
fi

echo "==> [2/5] pi's root filesystem is read-only"
if docker compose exec -T pi sh -c 'touch /this-should-fail 2>/dev/null'; then
  fail "pi container's root filesystem accepted a write outside mounted paths"
else
  pass "write outside mounted paths was rejected"
fi

echo "==> [3/5] Ollama model-management endpoints are unreachable via proxy"
if docker compose exec -T pi sh -c \
  "wget -q -T 3 -O- --post-data='{}' http://proxy:11434/api/pull" >/dev/null 2>&1; then
  fail "proxy allowed /api/pull through to Ollama"
else
  pass "/api/pull was rejected by the proxy's Ollama gate"
fi

echo "==> [4/5] no secret values in git history or the nix store"
if git log --all -p 2>/dev/null | grep -Ei 'ANTHROPIC_API_KEY *= *[A-Za-z0-9]|OPENAI_API_KEY *= *[A-Za-z0-9]|sk-ant-|sk-proj-' >/dev/null; then
  fail "a plausible secret pattern was found in git history — investigate before trusting this repo"
else
  pass "no obvious secret patterns found in git history"
fi
if [ -f .env ] && git check-ignore -q .env; then
  pass ".env is present and git-ignored"
elif [ -f .env ]; then
  fail ".env exists but is NOT git-ignored — fix .gitignore before committing"
fi

echo "==> [5/5] login flow populates the auth directory, default profile picks it up"
AUTH_DIR="${PI_AUTH_DIR:-$HOME/.config/pi-sandbox/auth}"
if [ -s "$AUTH_DIR/auth.json" ]; then
  pass "auth.json exists and is non-empty at $AUTH_DIR — run a default-profile session to confirm no re-auth prompt appears"
else
  echo "  SKIP: no auth.json yet — run 'nix run .#login' first, this check only confirms the file exists"
fi

if [ "$FAILED" = "1" ]; then
  echo "==> One or more checks FAILED. See above."
  exit 1
fi
echo "==> All automatable checks passed."
