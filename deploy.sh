#!/bin/bash -l
# deploy.sh — publish the freshly-built index.html (CDS public cluster page)
# to the page branch, which GitHub Pages serves. page is kept as a single
# amended commit and force-pushed, so the public page accumulates no history.
# Run after refresh_public.sh builds index.html. Requires push access (deploy
# key / PAT).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$ROOT" rev-parse --show-toplevel)"
PAGE="$ROOT/index.html"
[ -f "$PAGE" ] || { echo "deploy: no index.html to publish"; exit 1; }

# script guard: the zero-JS rule is dead (spec Revision R1) -- the page now
# legitimately ships one inline <script> for period switching + KPI recompute.
# What is still refused, unconditionally (no env var bypasses it): anything
# that would make the script reach outside the page -- an external request,
# browser storage, or an externally-sourced <script src=>.
for needle in 'fetch(' 'XMLHttpRequest' 'localStorage' 'document.cookie' '<script src='; do
  if grep -qF -- "$needle" "$PAGE"; then
    echo "deploy: REFUSED -- page contains '$needle'. Inline scripts are fine; external calls/storage/sourced scripts are not." >&2
    exit 1
  fi
done

# ...and require the "updated quarterly" stamp: a page built from a broken
# template (or a stray fragment) that carries neither must not publish.
if ! grep -q 'updated quarterly' "$PAGE"; then
  echo "deploy: REFUSED -- page lacks the 'updated quarterly' stamp. Rebuild with build_cluster_page.R." >&2
  exit 1
fi

# reap any stale registration first: a deploy that dies between 'worktree add'
# and 'worktree remove' leaves the page branch claimed by a temp worktree whose
# /scratch dir is gone, wedging every later add. The prune heals leftovers
# from older runs; the traps below stop THIS run from stranding one.
git -C "$REPO" worktree prune

# create page once (orphan, single commit) if it does not exist yet
if ! git -C "$REPO" show-ref --verify -q refs/heads/page; then
  WT0="$(mktemp -d)"
  trap 'git -C "$REPO" worktree remove --force "$WT0" 2>/dev/null || rm -rf "$WT0"; git -C "$REPO" worktree prune' EXIT
  git -C "$REPO" worktree add -q --detach "$WT0"
  ( cd "$WT0" && git checkout -q --orphan page \
      && git reset -q --hard \
      && : > .nojekyll && cp "$PAGE" index.html \
      && git add -f index.html .nojekyll \
      && git commit -q -m "Publish $(date '+%F %H:%M %Z')" )
  git -C "$REPO" worktree remove --force "$WT0"
  trap - EXIT
fi

# publish: amend the single page commit with the current page, force-push
WT="$(mktemp -d)"
trap 'git -C "$REPO" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"; git -C "$REPO" worktree prune' EXIT
git -C "$REPO" worktree add -q "$WT" page
cp "$PAGE" "$WT/index.html"; : > "$WT/.nojekyll"
# custom domain: Pages needs a CNAME file in the published branch.
printf '%s\n' "${PORTAL_PUBLIC_DOMAIN:-cluster.cds.bu.edu}" > "$WT/CNAME"
git -C "$WT" add -f index.html .nojekyll CNAME
git -C "$WT" commit -q --amend -m "Publish $(date '+%F %H:%M %Z')"
if [ "${DEPLOY_PUSH:-1}" = 1 ]; then
  git -C "$WT" push -qf origin page
  echo "deploy: pushed index.html to page"
else
  echo "deploy: built page locally (DEPLOY_PUSH=0, not pushed)"
fi
git -C "$REPO" worktree remove --force "$WT"
trap - EXIT
