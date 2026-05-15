#!/bin/bash
# CANONICAL_SYNC_VERSION=thin-pointer-2026-05-02
# ^^ DO NOT REMOVE — used by canonical's drift check.
#
# Thin-pointer canonical-sync hook (canonical bet 2026-05-02 WU-2).
#
# Replaces the vendored 28KB canonical-sync.template.sh snapshot with a
# ~80-line dispatcher that always invokes canonical's CURRENT sync logic.
# Eliminates two patching layers (hook content drift + URL refresh).
#
# Two paths, in order:
#
#   1. Sibling fast-path (local dev, desktop, multi-repo workspaces)
#      — if $CWD/../canonical/strategy/templates/canonical-sync.template.sh
#        exists, exec it directly with the current input. Always-current
#        because we read the file on every fire.
#
#   2. Curl fallback (Cloud Env, mobile, fresh sandboxes, CI)
#      — read .canonical-source.json for upstream URL + auth metadata,
#        fetch tarball, extract, exec the included template. Provider-
#        agnostic (GitHub, ADO, GitLab, public-no-auth).
#
# Configuration: .canonical-source.json (optional; only needed for curl path)
#
#   {
#     "source_url":  "<tarball-download URL on the upstream provider>",
#     "auth_method": "Bearer | Basic | none",
#     "token_env":   "<env-var name holding the auth token>"
#   }
#
# See canonical bet 2026-05-02-substrate-simplification-and-boss-doc.md.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
cd "$CWD"

# Opt-out sentinel (canonical#119): repos that must NOT inherit substrate
if [ -f "$CWD/.no-canonical-sync" ]; then
  echo "Canonical substrate sync: skipped (.no-canonical-sync sentinel present)."
  exit 0
fi

# === Path 1. Sibling fast-path ===
SIBLING_TEMPLATE="$CWD/../canonical/strategy/templates/canonical-sync.template.sh"
if [ -f "$SIBLING_TEMPLATE" ]; then
  echo "$INPUT" | bash "$SIBLING_TEMPLATE"
  exit $?
fi

# === Path 2. Curl fallback ===
SOURCE_FILE="$CWD/.canonical-source.json"
if [ ! -f "$SOURCE_FILE" ]; then
  echo "### CANONICAL SYNC FAILED"
  echo ""
  echo "No sibling canonical at \$CWD/../canonical AND no .canonical-source.json"
  echo "for fetch-from-upstream fallback. Cannot bootstrap canonical substrate."
  echo ""
  echo "Recovery:"
  echo "  - Desktop:  clone canonical alongside this repo at \$CWD/../canonical"
  echo "  - Cloud:    create .canonical-source.json (see canonical's"
  echo "              standards/canonical-source-config.md for schema)"
  echo ""
  exit 0
fi

SOURCE_URL=$(jq -r '.source_url // empty' "$SOURCE_FILE")
AUTH_METHOD=$(jq -r '.auth_method // "none"' "$SOURCE_FILE")
TOKEN_ENV=$(jq -r '.token_env // "CANONICAL_TOKEN"' "$SOURCE_FILE")

if [ -z "$SOURCE_URL" ]; then
  echo "### CANONICAL SYNC FAILED — .canonical-source.json missing source_url"
  exit 0
fi

# Resolve auth header (token from env)
TOKEN_VALUE=""
AUTH_HEADER=""
if [ "$AUTH_METHOD" != "none" ]; then
  TOKEN_VALUE=$(printenv "$TOKEN_ENV" 2>/dev/null || true)
  if [ -z "$TOKEN_VALUE" ]; then
    echo "### CANONICAL SYNC FAILED — token env var \$$TOKEN_ENV not set"
    echo ""
    echo "auth_method '$AUTH_METHOD' requires env var '$TOKEN_ENV' to be populated."
    echo "Set it via your platform's env-config (Cloud Env settings / GitHub Codespaces"
    echo "secret / ADO Variable Group / etc.) and re-run the session."
    echo ""
    exit 0
  fi
  case "$AUTH_METHOD" in
    Bearer) AUTH_HEADER="Authorization: Bearer $TOKEN_VALUE" ;;
    Basic)  AUTH_HEADER="Authorization: Basic $(printf ':%s' "$TOKEN_VALUE" | base64)" ;;
    *)      AUTH_HEADER="Authorization: $AUTH_METHOD $TOKEN_VALUE" ;;
  esac
fi

# Fetch tarball
TARBALL="/tmp/canonical-thin-pointer-$$.tar.gz"
if [ -n "$AUTH_HEADER" ]; then
  HTTP_CODE=$(curl -sS -L -H "$AUTH_HEADER" -w "%{http_code}" -o "$TARBALL" "$SOURCE_URL" 2>/dev/null || echo "000")
else
  HTTP_CODE=$(curl -sS -L -w "%{http_code}" -o "$TARBALL" "$SOURCE_URL" 2>/dev/null || echo "000")
fi

if [ "$HTTP_CODE" != "200" ]; then
  rm -f "$TARBALL" 2>/dev/null
  echo "### CANONICAL SYNC FAILED — fetch returned HTTP $HTTP_CODE"
  echo "URL: $SOURCE_URL"
  echo ""
  exit 0
fi

# Extract to a stable location
CANONICAL_FRESH="$HOME/canonical-fresh"
rm -rf "$CANONICAL_FRESH" 2>/dev/null
mkdir -p "$CANONICAL_FRESH"
tar -xzf "$TARBALL" -C "$CANONICAL_FRESH" --strip-components=1 2>/dev/null || {
  rm -f "$TARBALL"
  echo "### CANONICAL SYNC FAILED — tar extraction failed"
  exit 0
}
rm -f "$TARBALL"

# Exec the included template
FALLBACK_TEMPLATE="$CANONICAL_FRESH/strategy/templates/canonical-sync.template.sh"
if [ ! -f "$FALLBACK_TEMPLATE" ]; then
  echo "### CANONICAL SYNC FAILED — extracted tarball missing canonical-sync.template.sh"
  exit 0
fi
echo "$INPUT" | bash "$FALLBACK_TEMPLATE"
exit $?
