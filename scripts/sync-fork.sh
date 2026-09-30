#!/usr/bin/env bash
#
# Keep this pi-commandcode-provider fork in sync with patlux/pi-commandcode-provider.
#
# Rebases the fork-only commits on main onto upstream/main, runs the local
# checks, force-pushes with lease, and reconciles the installed pi package.
# Run it from the working clone, not from pi's managed checkout.

set -euo pipefail

UPSTREAM_URL="https://github.com/patlux/pi-commandcode-provider.git"
PACKAGE_SOURCE="git:github.com/random6-xyz/pi-commandcode-provider"
BRANCH="main"

DRY_RUN=0
PUSH=1
RUN_TESTS=1
FULL_TESTS=0
UPDATE_PI=1

usage() {
  cat <<'EOF'
Usage: scripts/sync-fork.sh [options]

Rebase this fork onto patlux/pi-commandcode-provider main, verify the result,
force-push it to the fork with --force-with-lease, and reconcile the pi package
install. The working tree must be clean and main must be checked out.

Options:
  --dry-run        Fetch and report only; make no local or remote changes
  --no-push        Rebase and verify, but do not push
  --skip-tests     Skip npm install, typecheck, and unit tests
  --full           Also run the real-pi end-to-end test (tests/test-pi-local.mjs)
  --no-pi-update   Do not run `pi update` for the installed package
  -h, --help       Show this help

Examples:
  scripts/sync-fork.sh --dry-run
  scripts/sync-fork.sh
  scripts/sync-fork.sh --full
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

step() {
  echo "==> $*"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-push) PUSH=0 ;;
    --skip-tests) RUN_TESTS=0 ;;
    --full) FULL_TESTS=1 ;;
    --no-pi-update) UPDATE_PI=0 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) fail "unknown option: $1 (try --help)" ;;
  esac
  shift
done

# Prefer the checkout that contains this script (resolving the PATH symlink),
# so the script also works when invoked from an unrelated directory. Fall back
# to the current work tree and then to the default clone location.
resolve_repo_root() {
  local resolved candidate
  resolved=$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || true)
  if [ -n "$resolved" ]; then
    candidate=$(cd "$(dirname "$resolved")/.." 2>/dev/null && pwd) || candidate=""
    if [ -n "$candidate" ] && git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  if candidate=$(git rev-parse --show-toplevel 2>/dev/null); then
    printf '%s\n' "$candidate"
    return 0
  fi
  candidate="${HOME:-}/nomads/opensource/pi-commandcode-provider"
  if git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

if ! repo_root=$(resolve_repo_root); then
  fail "could not locate the pi-commandcode-provider checkout; clone it or run the script from inside the clone"
fi
cd "$repo_root"

managed_checkout="${HOME:-}/.pi/agent/git/github.com/random6-xyz/pi-commandcode-provider"
case "$repo_root" in
  "$managed_checkout" | "$managed_checkout"/*)
    fail "this is pi's managed checkout; run the script from your working clone"
    ;;
esac

current_branch=$(git symbolic-ref --quiet --short HEAD || true)
[ "$current_branch" = "$BRANCH" ] || fail "expected branch $BRANCH, found ${current_branch:-detached HEAD}"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: tracked changes are present; commit or stash them first" >&2
  git status --short >&2
  exit 1
fi

if ! git remote get-url upstream >/dev/null 2>&1; then
  [ "$DRY_RUN" = 1 ] && fail "upstream remote is missing; run without --dry-run to add it"
  step "adding upstream remote $UPSTREAM_URL"
  git remote add upstream "$UPSTREAM_URL"
fi

step "fetching upstream/$BRANCH"
git fetch --quiet upstream "$BRANCH" || fail "could not fetch upstream"

ORIGIN_HEAD=""
if git fetch --quiet origin "$BRANCH" 2>/dev/null; then
  ORIGIN_HEAD=$(git rev-parse --verify --quiet "refs/remotes/origin/$BRANCH" || true)
fi

LOCAL_HEAD=$(git rev-parse HEAD)
if [ -n "$ORIGIN_HEAD" ] && [ "$LOCAL_HEAD" != "$ORIGIN_HEAD" ]; then
  if ! git merge-base --is-ancestor "$ORIGIN_HEAD" HEAD; then
    fail "origin/$BRANCH has commits that are not in local HEAD; reconcile manually first"
  fi
fi

UPSTREAM_HEAD=$(git rev-parse "upstream/$BRANCH")

echo "    upstream/$BRANCH $(git log -1 --format='%h %s' "$UPSTREAM_HEAD")"
echo "    HEAD             $(git log -1 --format='%h %s' "$LOCAL_HEAD")"
echo "    fork commits:"
git log --oneline --reverse "upstream/$BRANCH..HEAD" | sed 's/^/      /'

if git merge-base --is-ancestor "$UPSTREAM_HEAD" HEAD; then
  step "already up to date with upstream/$BRANCH"
  [ "$DRY_RUN" = 1 ] && exit 0
  if [ "$UPDATE_PI" = 1 ]; then
    step "reconciling pi package $PACKAGE_SOURCE"
    pi update --extension "$PACKAGE_SOURCE" || fail "pi update failed"
  fi
  step "done (nothing to push)"
  exit 0
fi

read -r ahead behind < <(git rev-list --left-right --count "HEAD...upstream/$BRANCH")
step "rebasing $ahead fork commit(s) onto upstream/$BRANCH ($behind new upstream commit(s))"

if [ "$DRY_RUN" = 1 ]; then
  echo "==> dry run: stopping before rebase"
  exit 0
fi

if ! git rebase "upstream/$BRANCH"; then
  git rebase --abort >/dev/null 2>&1 || true
  fail "rebase conflict; the rebase was aborted, resolve manually with: git rebase upstream/$BRANCH"
fi

if [ "$RUN_TESTS" = 1 ]; then
  step "npm install"
  npm install --no-audit --no-fund || fail "npm install failed; reset with: git reset --hard $LOCAL_HEAD"

  step "npm run typecheck"
  npm run typecheck || fail "typecheck failed; rebase kept, reset with: git reset --hard $LOCAL_HEAD"

  step "npm run test:unit"
  npm run test:unit || fail "unit tests failed; rebase kept, reset with: git reset --hard $LOCAL_HEAD"

  if [ "$FULL_TESTS" = 1 ]; then
    step "node tests/test-pi-local.mjs"
    node tests/test-pi-local.mjs || fail "pi end-to-end test failed; rebase kept, reset with: git reset --hard $LOCAL_HEAD"
  fi
fi

if [ "$PUSH" = 1 ]; then
  if [ -n "$ORIGIN_HEAD" ]; then
    step "pushing to origin/$BRANCH (force-with-lease)"
    git push --force-with-lease="refs/heads/$BRANCH:$ORIGIN_HEAD" origin "HEAD:refs/heads/$BRANCH" ||
      fail "push rejected; fetch origin/$BRANCH and reconcile before retrying"
  else
    step "pushing to origin/$BRANCH"
    git push -u origin "HEAD:refs/heads/$BRANCH" || fail "push failed"
  fi
else
  step "skipping push (--no-push)"
fi

if [ "$UPDATE_PI" = 1 ]; then
  step "reconciling pi package $PACKAGE_SOURCE"
  pi update --extension "$PACKAGE_SOURCE" || fail "pi update failed; run it manually after the push"
fi

step "done"
git log --oneline -3 | sed 's/^/      /'
