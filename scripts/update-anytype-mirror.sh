#!/usr/bin/env bash
# Refresh the Codeberg fork of anyproto/anytype-ts from GitHub upstream,
# then bump the vendor/anytype-ts submodule pin in this repo and push to
# both remotes.
#
# Codeberg has pull-mirrors disabled site-wide, so we sync from the local
# submodule clone: fetch upstream → push to Codeberg origin.
#
# Usage:
#   scripts/update-anytype-mirror.sh           # bump to latest upstream develop
#   scripts/update-anytype-mirror.sh v0.55.0   # bump to a specific tag/branch/SHA

set -euo pipefail

UPSTREAM_URL="https://github.com/anyproto/anytype-ts.git"
DEFAULT_REF="develop"
TARGET_REF="${1:-$DEFAULT_REF}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE_DIR="$REPO_ROOT/vendor/anytype-ts"

cd "$SUBMODULE_DIR"

# Make sure 'upstream' points at the GitHub repo (idempotent).
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$UPSTREAM_URL"
fi

echo "==> fetching upstream ($UPSTREAM_URL)"
git fetch --tags upstream

echo "==> resolving $TARGET_REF"
NEW_SHA=$(git rev-parse "upstream/$TARGET_REF" 2>/dev/null || git rev-parse "$TARGET_REF")
NEW_SHORT=$(git rev-parse --short "$NEW_SHA")
DESC=$(git describe --tags --always "$NEW_SHA")
echo "    upstream $TARGET_REF = $NEW_SHORT ($DESC)"

CUR_SHA=$(git rev-parse HEAD)
if [ "$CUR_SHA" = "$NEW_SHA" ]; then
  echo "==> already at $NEW_SHORT — nothing to do"
  exit 0
fi

echo "==> pushing fetched refs to Codeberg origin"
git push origin "refs/remotes/upstream/$TARGET_REF:refs/heads/$TARGET_REF"
git push --tags origin

echo "==> checking out $NEW_SHORT in submodule"
git checkout --detach "$NEW_SHA"

cd "$REPO_ROOT"
git add vendor/anytype-ts
if git diff --cached --quiet; then
  echo "==> submodule pin already up to date in parent repo"
  exit 0
fi

MSG="vendor: bump anytype-ts to $DESC ($NEW_SHORT)"
echo "==> committing in parent repo: $MSG"
git commit -m "$MSG"

echo "==> pushing parent repo to all remotes"
git push origin main

echo "==> done. anytype-ts pinned at $DESC ($NEW_SHORT)"
