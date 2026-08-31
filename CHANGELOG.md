# Changelog

All notable changes to the public cluster page.

## Unreleased

- **Ops: monthly refresh + page-branch deploy** (2026-08-31, `refresh_public.sh`,
  `deploy.sh`, `scripts/test_deploy.sh`): `refresh_public.sh` runs the pipeline
  end to end -- strip+combine, de-id gate, build, structure test, de-id gate
  again over the built page, then publish -- under an `flock` (one attempt,
  waits rather than skips: a monthly cron losing a race costs a month) with
  throttled operator alerts on failure (address from gitignored
  `config/alert_email`, else silent). `deploy.sh` publishes `index.html` to
  the `page` branch GitHub Pages serves as a single amended, force-pushed
  commit (worktree removed on an EXIT trap so a mid-deploy failure can't
  strand a registration), writing `.nojekyll` and a `CNAME` from
  `PORTAL_PUBLIC_DOMAIN` (default `cluster.cds.bu.edu`); refuses any
  `index.html` containing `<script` or missing the "updated monthly" stamp;
  `DEPLOY_PUSH=0` stages the commit without pushing (also the switch
  `refresh_public.sh` uses to skip the publish step entirely for a staged,
  no-push run of the whole pipeline). Lifecycle-tested in throwaway repos
  under `mktemp -d` (11 assertions: a failed push cannot strand a worktree, a
  second deploy after a failure and after a stale/self-healing registration
  both succeed, the happy path publishes `index.html`/`.nojekyll`/`CNAME`
  with no leftover worktree, `PORTAL_PUBLIC_DOMAIN` overrides the CNAME, and
  a scripted or unstamped page is refused); also run end to end against the
  real sibling clones with `DEPLOY_PUSH=0` (exit 0, all 28 `test_page.mjs`
  assertions and both gate passes green, deploy step skipped, no push).

- **Data layer: strip + combine, contract v2** (2026-08-31, `scripts/50_cluster_data.R`,
  `scripts/test_cluster_data.R`): reads the two pool dashboards' emitted data read-only,
  keeps month-grain aggregates for complete months only, derives pool capacity from the
  inventory records, and writes `output/cluster_data.json`. Monthly rows widen to a
  per-pool metric series read from each sibling emit's own columns by name -- `cpu_monthly`:
  `[month, node_class, held_h, utilized_h, fail_h, wkill_h, njobs, wa_used_h, wa_req_h]`;
  `gpu_monthly`: `[month, card, held_h, real_h, residle_h, kwh, vram_h, fail_h, wkill_h,
  njobs]` -- failing closed if either emit is missing a required column. `meta.window3`
  (trailing complete months, up to 3, common to both pools) replaces the old six-month
  window; `headline` (kept for the gate's conservation check, not rendered) sums over
  `window3`. The GPU input freshness ceiling widens 35d -> 100d for the new quarterly
  cadence; the CPU input ceiling stays 48h (still-daily refresh). Refuses identified or
  stale input. The monthly and capacity tables serialize as typed rows, so numbers land
  as JSON numbers rather than quoted strings. Fixture-tested (15 assertions) and verified
  against the real emits (38 CPU rows across 19 months, 29 GPU rows across 6 months;
  capacity totals hand-checked against the inventory records).

- **Gate: whitelist/blocklist/conservation for cluster_data** (2026-08-31,
  `scripts/gate_cluster.mjs`, `scripts/test_gate.mjs`): checks `output/cluster_data.json`
  (and, when given a second argument, the built page's HTML) before the whitelist
  is trusted to publish. Whitelists every hardware model, server model, card, node
  class, and `YYYY-MM` period against the same sibling inventory CSVs the data layer
  reads; blocklist-scans the full text for real hostnames and registry-code patterns;
  recomputes the headline totals from the monthly tables and fails on any mismatch.
  Fails closed on unreadable input. Fixture-tested (24 assertions) and run against the
  real Task-1 output (exit 0).

- **Public page: portal-lift rebuild** (2026-08-31, `build_cluster_page.R`,
  `scripts/test_page.mjs`, `validate.mjs`; spec Revision R1): replaces the static
  zero-JS showcase with a lift of the two portals' own hardware/status panels --
  the old zero-JS rule is dead, this page ships exactly one inline `<script>`,
  self-contained (no `fetch`/`XMLHttpRequest`, no `localStorage`, no
  `document.cookie`, no `prefers-color-scheme`). Layout: header lockup (unchanged)
  -> one deckrow with the GPU pool panel left and the CPU pool panel right (each
  lifted from `gpu-cds-scc/build_gpu_portal.R` `livePanel()` / `cpu-cds-scc/
  build_cpu_portal.R` `renderLive()` -- hwtop/hwcols/hwrow/cnode idiom, CPU model
  codes rendered human-readably, e.g. `Gold-6242` -> "Xeon Gold 6242") -> a
  month-grain period selector (every published month plus "Past 3 months"
  (default), "Past 6 months", "All months") -> a second deckrow with the GPU and
  CPU KPI totals cards (tile labels/tips lifted verbatim from each portal's own
  `kpi()` helper and `TIPS` object) -> footer (unchanged). Every panel block
  renders fully saturated -- capacity, not occupancy -- with no LIVE/STALE badge
  and no held counts, since this page carries no live feed; tooltips are built
  purely from `capacity.types[]` (Server, RAM-per-node/VRAM-per-GPU, per-cluster
  unit counts) -- no hostnames, no install dates, matching what contract v2
  actually has. The KPI cards are server-rendered for the default trailing-3-month
  window so the page means something before/without JS, and the inline script
  repeats the identical arithmetic (R and JS share `Math.round`-compatible
  rounding) to recompute both cards on a period change. `validate.mjs` (copied
  from `cpu-cds-scc/validate.mjs`'s DOM-shim runner) executes the page's inline
  JS under a minimal shim and fails the build on any runtime throw; wired into
  `refresh_public.sh` between the structure test and the second de-id gate pass.
  Fixture-tested against the real Task 7 output (59 assertions covering
  structure/containment, panel saturation, the period selector, both KPI cards'
  tile labels, the de-id blocklist, and a functional simulation that executes the
  embedded script and confirms a period change recomputes both cards correctly)
  and run through `gate_cluster.mjs` with the built page (exit 0). `index.html`
  is 231 KB, dominated by the embedded assets.

- **Ops: quarterly cadence + deploy guard for the scripted page** (2026-08-31,
  `deploy.sh`, `scripts/test_deploy.sh`, `build_cluster_page.R`,
  `scripts/test_page.mjs`; spec Revision R1): the footer stamp moves
  `updated monthly` -> `updated quarterly` to match the new quarterly refresh
  cadence, and `deploy.sh`'s zero-JS guard -- dead now that the page carries a
  real inline `<script>` (Task 8) -- is replaced with a guard that admits
  inline scripts but refuses anything reaching outside the page: an
  `index.html` containing `fetch(`, `XMLHttpRequest`, `localStorage`,
  `document.cookie`, or an externally-sourced `<script src=` is refused, and
  the stamp check now requires `updated quarterly` (both unconditional, no
  env var bypasses them). Lifecycle-tested in throwaway repos under
  `mktemp -d` (12 assertions): the old `<script>`-refusal scenario becomes an
  inline-script-ACCEPTED scenario, plus a new `fetch(`-refusal scenario, plus
  the existing stamp/worktree-lifecycle coverage updated to the new wording.
  Rebuilt and re-verified: `test_page.mjs` (59 assertions, including the
  footer's `updated quarterly` stamp) and `validate.mjs` green, and the full
  staged pipeline (`DEPLOY_PUSH=0 ./refresh_public.sh`) green end to end.
