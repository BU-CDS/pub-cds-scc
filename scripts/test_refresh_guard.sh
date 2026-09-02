#!/bin/bash
# test_refresh_guard.sh — refresh_public.sh's checkout preflight in throwaway
# repos. A push-capable run (DEPLOY_PUSH unset or 1) must refuse to start unless
# the checkout is on the expected branch (PUB_EXPECT_BRANCH, default main); a
# staged run (DEPLOY_PUSH=0) may build from any source branch; a checkout with
# no sources (the page orphan) is refused under any branch name. The pipeline
# steps are stubbed (empty R/JS files, a no-op deploy.sh), so the happy paths
# need only the R and node modules the real script loads. Alerts are disarmed.
# Run directly; exits nonzero on any failure.
set -uo pipefail

S="$(cd "$(dirname "$0")" && pwd)"
REFRESH="$S/../refresh_public.sh"
FAILS=0

ok(){ echo "PASS: $*"; }
bad(){ echo "FAIL: $*"; FAILS=$((FAILS+1)); }

mkrepo(){ # $1: dir — toy repo on main: a copy of refresh_public.sh, every step stubbed
  git init -q -b main "$1"
  git -C "$1" config user.email test@test
  git -C "$1" config user.name test
  mkdir -p "$1/scripts"
  cp "$REFRESH" "$1/refresh_public.sh"
  : > "$1/scripts/50_cluster_data.R"; : > "$1/scripts/gate_cluster.mjs"
  : > "$1/build_cluster_page.R";      : > "$1/scripts/test_page.mjs"
  : > "$1/validate.mjs"
  printf '#!/bin/bash\necho "deploy: stub"\n' > "$1/deploy.sh"; chmod +x "$1/deploy.sh"
  git -C "$1" add -A
  git -C "$1" -c commit.gpgsign=false commit -qm init
}

# run REPO [VAR=VAL ...] — the copy, alerts disarmed; prints its exit status
run(){ local r="$1"; shift
  env -u PUB_ALERT_EMAIL -u PUB_ALERT_CMD "$@" "$r/refresh_public.sh" >/dev/null 2>&1; echo $?; }
logged(){ grep -q -- "$2" "$1/refresh.log" 2>/dev/null; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. production shape: main, push-capable -> runs to completion
R="$WORK/r1"; mkrepo "$R"
rc="$(run "$R")"
if [ "$rc" = 0 ] && logged "$R" " done"; then ok "main + DEPLOY_PUSH default: run completes"
else bad "main + DEPLOY_PUSH default: rc=$rc, log: $(tail -3 "$R/refresh.log" 2>/dev/null)"; fi

# 2. a dev branch, push-capable -> refused before any step runs
R="$WORK/r2"; mkrepo "$R"; git -C "$R" checkout -q -b build
rc="$(run "$R")"
if [ "$rc" != 0 ] && logged "$R" "FAILED: repo on branch 'build', expected 'main'"; then
  ok "build + DEPLOY_PUSH default: refused with the branch reason"
else bad "build + DEPLOY_PUSH default: rc=$rc, log: $(tail -3 "$R/refresh.log" 2>/dev/null)"; fi
if grep -qE '^[0-9-]+ [0-9:]+ run ' "$R/refresh.log"; then bad "build + DEPLOY_PUSH default: a pipeline step ran before the refusal"
else ok "build + DEPLOY_PUSH default: no step ran"; fi

# 3. a dev branch, staged -> allowed (a build that cannot push is branch-agnostic)
R="$WORK/r3"; mkrepo "$R"; git -C "$R" checkout -q -b build
rc="$(run "$R" DEPLOY_PUSH=0)"
if [ "$rc" = 0 ] && logged "$R" "deploy staged locally"; then ok "build + DEPLOY_PUSH=0: staged run completes"
else bad "build + DEPLOY_PUSH=0: rc=$rc, log: $(tail -3 "$R/refresh.log" 2>/dev/null)"; fi

# 4. deliberate publish from another branch: PUB_EXPECT_BRANCH names it
R="$WORK/r4"; mkrepo "$R"; git -C "$R" checkout -q -b hotfix
rc="$(run "$R" PUB_EXPECT_BRANCH=hotfix)"
if [ "$rc" = 0 ] && logged "$R" " done"; then ok "hotfix + PUB_EXPECT_BRANCH=hotfix: run completes"
else bad "hotfix + PUB_EXPECT_BRANCH=hotfix: rc=$rc, log: $(tail -3 "$R/refresh.log" 2>/dev/null)"; fi

# 5. the page orphan (index.html only, no sources) is refused under ANY branch name
R="$WORK/r5"; mkrepo "$R"
git -C "$R" checkout -q --orphan main2 && git -C "$R" rm -q -rf . && git -C "$R" branch -q -M main
cp "$REFRESH" "$R/refresh_public.sh"
rc="$(run "$R" DEPLOY_PUSH=0)"
if [ "$rc" != 0 ] && logged "$R" "FAILED: missing source"; then ok "sourceless checkout on main: refused with the missing-source reason"
else bad "sourceless checkout on main: rc=$rc, log: $(tail -3 "$R/refresh.log" 2>/dev/null)"; fi

if [ $FAILS -eq 0 ]; then echo "test_refresh_guard: all green"; else echo "test_refresh_guard: $FAILS failing"; fi
exit "$((FAILS > 0))"
