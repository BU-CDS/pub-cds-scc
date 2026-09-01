#!/bin/bash
# test_deploy.sh — deploy.sh worktree lifecycle in throwaway repos. Mirrors
# cpu-cds-scc/scripts/test_deploy.sh: a mid-deploy failure must not strand a
# page worktree registration, and a stranded registration must not block the
# next deploy. Also covers this repo's script / "updated" stamp guards (an
# inline-script page is accepted, a page calling fetch( is refused, an
# unstamped page is refused, a clean page stages without pushing under
# DEPLOY_PUSH=0). Run directly; exits nonzero on any failure.
set -uo pipefail

S="$(cd "$(dirname "$0")" && pwd)"
DEPLOY="$S/../deploy.sh"
FAILS=0

ok(){ echo "PASS: $*"; }
bad(){ echo "FAIL: $*"; FAILS=$((FAILS+1)); }

mkrepo(){ # $1: dir — toy repo holding a clean page and a copy of deploy.sh
  git init -q -b main "$1"
  git -C "$1" config user.email test@test
  git -C "$1" config user.name test
  printf '<html><body>updated quarterly &middot; 2026-08-31</body></html>\n' > "$1/index.html"
  cp "$DEPLOY" "$1/deploy.sh"
  git -C "$1" add -A
  git -C "$1" -c commit.gpgsign=false commit -qm init
}

wt_count(){ git -C "$1" worktree list | wc -l; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. a failed push must not strand a worktree registration
R="$WORK/r1"; mkrepo "$R"
git -C "$R" remote add origin "$WORK/no-such-remote.git"
"$R/deploy.sh" >/dev/null 2>&1 && bad "push to a missing remote should fail"
if [ "$(wt_count "$R")" -eq 1 ]; then ok "no worktree stranded after a failed push"
else bad "worktree stranded after a failed push: $(git -C "$R" worktree list | tail -1)"; fi
out="$("$R/deploy.sh" 2>&1)"
case "$out" in
  *"already used by worktree"*) bad "second deploy wedged on the stale registration";;
  *) ok "second deploy reaches the push step again";;
esac

# 2. a stranded registration whose directory vanished must self-heal
R="$WORK/r2"; mkrepo "$R"
DEPLOY_PUSH=0 "$R/deploy.sh" >/dev/null 2>&1 || bad "baseline deploy failed"
T="$WORK/ghost"
git -C "$R" worktree add -q "$T" page && rm -rf "$T"
out="$(DEPLOY_PUSH=0 "$R/deploy.sh" 2>&1)"
if [ $? -eq 0 ]; then ok "deploy self-heals a stale registration"
else bad "deploy still wedged: $out"; fi

# 3. the happy path stays intact
R="$WORK/r3"; mkrepo "$R"
out="$(DEPLOY_PUSH=0 "$R/deploy.sh" 2>&1)"
[ $? -eq 0 ] || bad "happy-path deploy failed: $out"
if git -C "$R" show page:index.html >/dev/null 2>&1; then ok "page branch carries index.html"
else bad "page branch missing index.html"; fi
if [ "$(wt_count "$R")" -eq 1 ]; then ok "no leftover worktree after a clean deploy"
else bad "leftover worktree after a clean deploy"; fi
if git -C "$R" show page:CNAME 2>/dev/null | grep -qx "cluster.cds.bu.edu"; then
  ok "page branch carries the default CNAME"
else bad "page branch missing/wrong CNAME"; fi
if git -C "$R" show page:.nojekyll >/dev/null 2>&1; then ok "page branch carries .nojekyll"
else bad "page branch missing .nojekyll"; fi

# 4. custom domain via PORTAL_PUBLIC_DOMAIN
R="$WORK/r4"; mkrepo "$R"
out="$(PORTAL_PUBLIC_DOMAIN=example.org DEPLOY_PUSH=0 "$R/deploy.sh" 2>&1)"
[ $? -eq 0 ] || bad "custom-domain deploy failed: $out"
if git -C "$R" show page:CNAME 2>/dev/null | grep -qx "example.org"; then
  ok "PORTAL_PUBLIC_DOMAIN overrides the CNAME"
else bad "PORTAL_PUBLIC_DOMAIN did not reach CNAME"; fi

# guard: an inline <script> is accepted (the zero-JS rule is dead; the real
# page ships exactly one inline script)
T5="$WORK/t5"; mkrepo "$T5"
printf '<html><script>console.log(1)</script>updated quarterly &middot; 2026-08-31</html>\n' > "$T5/index.html"
( cd "$T5" && DEPLOY_PUSH=0 ./deploy.sh ) >/dev/null 2>&1 \
  && ok "inline-script page accepted" || bad "inline-script page was refused"
# guard: a page calling fetch( is refused (no external network calls, even
# from an otherwise-legitimate inline script)
T5B="$WORK/t5b"; mkrepo "$T5B"
printf '<html><script>fetch("/x")</script>updated quarterly &middot; 2026-08-31</html>\n' > "$T5B/index.html"
( cd "$T5B" && DEPLOY_PUSH=0 ./deploy.sh ) >/dev/null 2>&1 \
  && bad "fetch(-calling page was accepted" || ok "fetch(-calling page refused"
# guard: a page missing the "updated quarterly ·" stamp is refused
T6="$WORK/t6"; mkrepo "$T6"
printf '<html>no stamp here</html>\n' > "$T6/index.html"
( cd "$T6" && DEPLOY_PUSH=0 ./deploy.sh ) >/dev/null 2>&1 \
  && bad "unstamped page was accepted" || ok "unstamped page refused"
# clean page stages without pushing
T7="$WORK/t7"; mkrepo "$T7"
( cd "$T7" && DEPLOY_PUSH=0 ./deploy.sh ) >/dev/null 2>&1 \
  && ok "clean page staged (DEPLOY_PUSH=0)" || bad "clean page failed to stage"

if [ $FAILS -eq 0 ]; then echo "test_deploy: all green"; else echo "test_deploy: $FAILS failing"; fi
exit "$((FAILS > 0))"
