#!/bin/bash -l
# (login shell: sources /etc/profile so Lmod's 'module' is defined under cron)
# refresh_public.sh — regenerate + publish the CDS public cluster page (the
# CPU + GPU buy-in pool showcase). Monthly pipeline: strip+combine the sibling
# emits -> de-id gate -> build the portal-lift page (twin pool panels, period
# selector, per-pool KPI totals; inline JS) -> structure test -> DOM-shim JS
# execution check -> de-id gate again over the built page -> publish (deploy.sh).
#
# Idempotent + flock-guarded (overlapping runs skip the lock, they don't
# clobber output/index.html) + logged. Local-only: output/, index.html,
# refresh.log, .alert/, .refresh.lock, config/alert_email are gitignored.
# DEPLOY_PUSH=0 runs the whole pipeline but skips the publish step (Task 5's
# staged review; test_deploy.sh exercises deploy.sh's own DEPLOY_PUSH=0
# stage-without-push path directly).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
S="$ROOT/scripts"
LOG="$ROOT/refresh.log"
LOCK="$ROOT/.refresh.lock"

log(){ echo "$(date '+%F %T') $*" >>"$LOG"; }

# --- operator alerts -------------------------------------------------------
# Address: PUB_ALERT_EMAIL from the cron env, else config/alert_email, so a
# clone can be armed without editing the crontab. PUB_ALERT_CMD is an extra
# hook (webhook, pager). Every path here is best effort: alerting never aborts.
: "${PUB_ALERT_EMAIL:=$(cat "$ROOT/config/alert_email" 2>/dev/null || true)}"
ALERTDIR="$ROOT/.alert"
NAG_S="${PUB_ALERT_NAG_S:-21600}"   # a condition that stays broken re-mails at most every 6 h

send(){ # $1 subject, $2 body
  if [ -n "${PUB_ALERT_EMAIL:-}" ] && command -v mail >/dev/null 2>&1; then
    printf '%s\n' "$2" | mail -s "$1" "$PUB_ALERT_EMAIL" || true
  fi
  [ -n "${PUB_ALERT_CMD:-}" ] && eval "$PUB_ALERT_CMD" >/dev/null 2>&1 || true
  return 0; }

# alert KEY SUBJECT BODY — mails the first tick a condition appears, then at most
# once per NAG_S while it lasts. Throttled so a wedge doesn't turn into a mail
# per invocation.
alert(){
  mkdir -p "$ALERTDIR" 2>/dev/null || true
  local f="$ALERTDIR/$1" now first last
  now=$(date +%s); first=$now; last=0
  [ -f "$f" ] && read -r first last <"$f" || true
  [ -n "${first:-}" ] || first=$now
  [ -n "${last:-}" ] || last=0
  if [ $((now - last)) -ge "$NAG_S" ]; then
    send "$2" "$3

First seen $(date -d "@$first" '+%F %T %Z') on $(hostname).
Repeats at most every $((NAG_S/3600))h, then one RECOVERED mail when it clears."
    log "alert mailed: $2"; last=$now
  fi
  # best effort: an NFS hiccup or a permissions change on $ALERTDIR must not
  # turn recording throttle state into a reason to abort a build that already
  # succeeded.
  printf '%s %s\n' "$first" "$last" >"$f" 2>/dev/null || true; }

# clear_alert KEY LABEL — one recovery mail, and only if an alert was actually live.
clear_alert(){
  local f="$ALERTDIR/$1" first=0
  [ -f "$f" ] || return 0
  read -r first _ <"$f" || first=0
  rm -f "$f" 2>/dev/null || true   # same best-effort contract as alert()'s write
  send "public cluster page RECOVERED: $2" "$2 is healthy again at $(date '+%F %T %Z') on $(hostname).
Broken since $(date -d "@$first" '+%F %T %Z')."
  log "recovered: $2"; }

fail(){ log "FAILED: $*"
  alert refresh "public cluster page refresh FAILED ($(hostname))" "$(tail -25 "$LOG")"
  exit 1; }
run(){ log "run $*"; "$@" >>"$LOG" 2>&1 || fail "$*"; }

# --- the lock --------------------------------------------------------------
# Monthly cron: one attempt, so a wedge should wait rather than skip -- a skip
# here costs a month, not a tick.
acquire_lock(){
  exec 9>"$LOCK"
  flock -w "${PUB_LOCK_WAIT_S:-1800}" 9 \
    || fail "could not acquire $LOCK within ${PUB_LOCK_WAIT_S:-1800}s -- another refresh is wedged"; }

acquire_lock

module load R/4.5.2 2>>"$LOG" || true
command -v Rscript >/dev/null 2>&1 || fail "Rscript not on PATH after 'module load R/4.5.2'"
module load nodejs/20.12.2 2>>"$LOG" || true
command -v node >/dev/null 2>&1 || fail "node not on PATH after 'module load nodejs/20.12.2'"

cd "$ROOT"
log "start"
run Rscript "$S/50_cluster_data.R"                                   # sibling emits -> output/cluster_data.json
run node "$S/gate_cluster.mjs" "$ROOT/output/cluster_data.json"      # de-id gate: data layer
run Rscript "$ROOT/build_cluster_page.R"                             # cluster_data.json -> index.html
run node "$S/test_page.mjs" "$ROOT/index.html"                       # structure + de-id assertions on the built page
run node "$ROOT/validate.mjs" "$ROOT/index.html"                     # DOM-shim: the page's inline JS must execute cleanly
run node "$S/gate_cluster.mjs" "$ROOT/output/cluster_data.json" "$ROOT/index.html"   # de-id gate: page too

if [ "${DEPLOY_PUSH:-1}" = 1 ]; then
  log "deploy"
  run "$ROOT/deploy.sh"
  clear_alert deploy "page publish"
else
  log "deploy skipped (DEPLOY_PUSH=0)"
fi
log "done"
