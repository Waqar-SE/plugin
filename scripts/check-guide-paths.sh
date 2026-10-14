#!/usr/bin/env bash
# Checks that each file path the style guides name exists in the product repository.
# Usage: scripts/check-guide-paths.sh /path/to/Simplihost
# Prints "missing: <path> (<guide>)" for each path it cannot find, and exits 1. Prints "ok" when every path exists.
set -u
repo=${1:?usage: $0 /path/to/product-repo}
here=$(cd "$(dirname "$0")/.." && pwd)

exists() { local p=$1; shift; for r in "$@"; do [ -e "$r/$p" ] && return 0; done; return 1; }

check() { # $1 guide, $2 regex of a path token in backticks, then the roots to try
  local guide=$1 regex=$2; shift 2
  grep -oE "$regex" "$guide" | tr -d '`' | grep -vE '(^|/)(X|<)|\.test\.' | sort -u | while read -r p; do
    exists "$p" "$@" || echo "missing: $p ($(basename "$guide"))"
  done
}

out=$(
  check "$here/style-guides/backend-style-guide.md" '`[a-z_]+(/[a-z_]+)+\.py`' \
    "$repo/src" "$repo/src/integrations" "$repo"/src/integrations/*
  check "$here/style-guides/frontend-style-guide.md" '`[A-Za-z_]+(/[A-Za-z_]+)+\.jsx?`' \
    "$repo/src/frontend" "$repo/src/frontend/components" "$repo/src/frontend/pages/dashboard" "$repo/src/frontend/app/api" "$repo/src/frontend/app"
  grep -ohE 'src/[a-z_/]+/CLAUDE\.md' "$here"/style-guides/*.md | sort -u | while read -r p; do
    [ -e "$repo/$p" ] || echo "missing: $p (CLAUDE.md)"
  done
)
if [ -n "$out" ]; then echo "$out"; exit 1; fi
echo "ok: every path the guides name exists in $repo"
