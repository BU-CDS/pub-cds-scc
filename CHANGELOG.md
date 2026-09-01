# Changelog

All notable changes to the public cluster page.

## Unreleased

- **Data layer: window3 must end at the calendar month just closed**
  (2026-08-31, `scripts/50_cluster_data.R`, `scripts/test_cluster_data.R`):
  `window3` previously trusted `intersect(months_cpu, months_gpu)` verbatim --
  if one sibling emit's own history quietly stopped advancing (its producer
  cron dropped, say), the published "Past 3 months" would silently age by a
  month on every run instead of failing loud, until an unrelated freshness
  ceiling eventually tripped on its own. `50_cluster_data.R` now computes the
  calendar month just closed (America/New_York) and `stop()`s, naming both
  the actual last common complete month and the expected one, unless
  `window3`'s last month matches it. Also: `window3 <- tail(intersect(...), 3)`
  gains a `sort()` -- it silently assumed `periods$M` was already ascending;
  a descending emit would have made "Past 3 months" the *earliest* three.
  Fixture-tested: a GPU input whose newest common month is two months back
  now `stop()`s (naming both months), while the normal one-month-back case
  (the existing happy path) still passes (17/17 total assertions, up from 15).

- **Public page: per-card coverage captions for out-of-range windows**
  (2026-08-31, `build_cluster_page.R`, `scripts/test_page.mjs`): the GPU
  series (trailing ~6 months by design) and the CPU series (full history)
  rarely cover the same window, so "All months" or an early single month
  could sum a pool's KPI card over months that pool has no rows for at all --
  correct arithmetic, misleading framing (reads as "the pool did nothing"
  rather than "no data here"). Each totals card now carries a caption
  (`#gpu-cov`/`#cpu-cov`) showing "GPU data: Feb – Jul 2026" when the
  selected window is only partly covered by that pool's own series, and
  swaps the KPI tiles for "No GPU data for this period" when it isn't
  covered at all; nothing renders when the window is fully covered (true for
  the default `window3` by construction). Implemented identically in R
  (`coverage_note()`, for the server-rendered default) and JS
  (`coverageNote()`, recomputed on every period change), so the two always
  agree. Fixture-tested: a functional simulation exercises both the partial
  case ("All months" leaves a GPU caption while its tiles still render real
  numbers, and no caption for CPU) and the zero case (a pre-GPU-range month
  replaces the GPU tiles entirely) (157/157 total assertions, up from 142).

- **Public page: a missing embedded asset now fails the build, not the page**
  (2026-08-31, `build_cluster_page.R`, `scripts/test_page.mjs`): `b64()`
  previously returned `""` for a missing plate/emblem/font file, so a rename
  or move in the sibling clone's independently-evolving `assets/` directory
  would silently ship a headerless, system-font page with no alert -- nothing
  in the pipeline checked payload presence. `b64()` now `stop()`s by name on
  a missing file. Also added a floor-size check so a present-but-truncated
  asset doesn't slip through either: each of the four embedded base64
  payloads (plate, emblem, two font weights) must clear 1 KB.

- **Ops: `DEPLOY_PUSH=0` now stages via `deploy.sh` instead of skipping it**
  (2026-08-31, `refresh_public.sh`): `DEPLOY_PUSH=0` previously made
  `refresh_public.sh` skip `deploy.sh` entirely, so a staged, no-push run
  never exercised `deploy.sh`'s own guards or worktree lifecycle -- exactly
  the gap that let a stale zero-JS refusal go unnoticed until it would have
  blocked the very first real publish. `refresh_public.sh` now always runs
  `deploy.sh`; `deploy.sh`'s own `DEPLOY_PUSH` check (unchanged) decides
  whether it pushes or only stages the commit locally. The recovery mail
  (`clear_alert`) now fires under the `refresh` key that `fail()` actually
  uses (the old `clear_alert deploy` call was dead -- no `alert deploy` call
  exists anywhere, so a "RECOVERED" mail could never follow a "refresh
  FAILED" one) and only after an actual push. Verified: the full staged
  pipeline (`DEPLOY_PUSH=0 ./refresh_public.sh`) still exits 0 and reaches
  `deploy.sh` (visible in `refresh.log` as a staged, unpushed commit); the
  pushing path is unchanged and still covered by `scripts/test_deploy.sh`
  (12/12).

- **Housekeeping: doc/comment corrections, trimmed tooltip copy, locale-pinned
  formatting, an accessible name for the month picker** (2026-08-31, several
  files): `refresh_public.sh`'s header/lock comments said "Monthly" where the
  cadence is quarterly, and described overlapping runs as "skipping" the lock
  when `flock -w` actually waits for it. Two KPI tooltips described things
  this page doesn't show (`Walltime Accuracy`'s "coverage shown as n" -- no
  `n` is rendered here; `Avg Utilization`'s "split into the three tiers" --
  no tiered bar here) and are trimmed on both the R and JS copies. The page's
  JS `toLocaleString()` calls are pinned to `'en-US'` so a period-change
  recompute can't re-render a number in a different grouping style than the
  server-rendered default on a non-English browser. `<select id="pmonth">`
  gains `aria-label="Month"` (it carried no accessible name). And every
  internal-process reference ("Task N", "maintainer round N") is reworded to
  describe what changed, never the process that produced it, across
  `CHANGELOG.md`, `build_cluster_page.R`, `refresh_public.sh`,
  `scripts/test_page.mjs`, `scripts/test_deploy.sh`, and `scripts/test_gate.mjs`.
  Text-and-comment changes only; the full test suite (page 157/157, data
  layer 17/17, gate 24/24, `validate.mjs`, `test_deploy.sh` 12/12) is
  unaffected.

- **Public page: status-line stamp reworded and hyperlinked to rcs.bu.edu**
  (2026-08-31, `build_cluster_page.R`, `scripts/test_page.mjs`): the
  `.livewrap` status line's "Data from SGE accounting and gpustats" opening
  is now "Data from BU SCC", linked to `https://rcs.bu.edu`; " · updated
  quarterly · `<date>`" stays plain text unchanged (`deploy.sh`'s stamp grep
  is unaffected). Fixture-tested (RED against the pre-fix page, GREEN after
  rebuild, 142/142 total assertions); `validate.mjs` and the de-id gate over
  the built HTML (both `BU SCC` and the `rcs.bu.edu` URL clear the
  blocklist) and `scripts/test_deploy.sh` (12/12) unaffected.

- **Public page: footer/main width under the sticky-footer body** (2026-08-31,
  `build_cluster_page.R`, `scripts/test_page.mjs`): since the sticky-footer
  `body{display:flex;flex-direction:column}` was introduced, a column-flex item with
  `margin:0 auto` does not stretch (Flexbox §9.4 step 11) -- it shrink-wraps
  to fit-content instead, which left `main` and `.pagefoot` narrower than the
  intended `min(var(--content-max),98vw)` (the footer's three zones bunched
  into a jumbled center block instead of left/center/right, and every fit
  arithmetic in this changelog implicitly assumed the wider width). Both now
  carry an explicit `width:100%` alongside their `max-width`. Fixture-tested
  (RED against the pre-fix page, GREEN after rebuild, 139/139 total
  assertions); `validate.mjs` and `scripts/test_deploy.sh` (12/12) unaffected.

- **Public page: footer mirrors the portal footers; data stamp moves to a
  status line** (2026-08-31, `build_cluster_page.R`, `scripts/test_page.mjs`):
  the footer is now the same three-zone layout as `gpu-cds-scc`/`cpu-cds-scc`
  (emblem left, GitHub mark center, Privacy Statement right) instead of a
  single emblem + text stamp. Since this page has no theme, the portals'
  light/dark emblem pair collapses to one `<img class="ft-emblem">`, and since
  it has no codenames, the portals' `#poke` toggle is omitted entirely; the
  GitHub link points at this repo's own public mirror
  (`https://github.com/BU-CDS/pub-cds-scc`). The "Data from SGE accounting and
  gpustats · updated quarterly · `<date>`" stamp `deploy.sh` still greps for
  moves out of the footer into the portals' own public-mode status line
  (`.livewrap`/`.liveupd`) directly under the header, ahead of the first
  deckrow -- text unchanged, only relocated. `.pagefoot` keeps this page's own
  `98vw` gutter and sticky-footer `margin-top:auto` in place of the portals'
  fixed top margin; everything else in the footer CSS is verbatim portal.
  `.livewrap` itself carries neither `max-width` nor `var(--content-pad)` --
  unlike the portals, where `.livewrap` is a top-level element, here it is
  nested inside `<main>`, which already applies both, so its own copy would
  have double-padded the stamp text inside the deck's outer edge.
  Fixture-tested (RED against the pre-round page, GREEN after rebuild, 137/137
  total assertions) and run through the full staged pipeline including
  `gate_cluster.mjs` over the built HTML (both external URLs pass the de-id
  blocklist) and `scripts/test_deploy.sh` (12/12, stamp text unchanged).

- **Ops: quarterly refresh + page-branch deploy** (2026-08-31, `refresh_public.sh`,
  `deploy.sh`, `scripts/test_deploy.sh`): `refresh_public.sh` runs the pipeline
  end to end -- strip+combine, de-id gate, build, structure test, de-id gate
  again over the built page, then publish -- under an `flock` (one attempt,
  waits rather than skips: a quarterly cron losing a race costs a quarter) with
  throttled operator alerts on failure (address from gitignored
  `config/alert_email`, else silent). `deploy.sh` publishes `index.html` to
  the `page` branch GitHub Pages serves as a single amended, force-pushed
  commit (worktree removed on an EXIT trap so a mid-deploy failure can't
  strand a registration), writing `.nojekyll` and a `CNAME` from
  `PORTAL_PUBLIC_DOMAIN` (default `cluster.cds.bu.edu`); guards against
  `index.html` reaching outside the page (external requests/storage/an
  externally-sourced `<script src=`) or missing the required stamp text
  (see "quarterly cadence + deploy guard" below for the guard's current
  shape and exact stamp wording, which supersedes both of those checks'
  original zero-JS-era phrasing). `DEPLOY_PUSH=0` stages the commit locally
  without pushing -- the same switch `refresh_public.sh` passes straight
  through to `deploy.sh` on every run, staged or not (it no longer skips
  reaching `deploy.sh` at all). Lifecycle-tested in throwaway repos
  under `mktemp -d` (11 assertions: a failed push cannot strand a worktree, a
  second deploy after a failure and after a stale/self-healing registration
  both succeed, the happy path publishes `index.html`/`.nojekyll`/`CNAME`
  with no leftover worktree, `PORTAL_PUBLIC_DOMAIN` overrides the CNAME, and
  a scripted or unstamped page is refused); also run end to end against the
  real sibling clones with `DEPLOY_PUSH=0` (exit 0, all `test_page.mjs`
  assertions and both gate passes green, deploy step staged, no push).

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
  real strip+combine output (exit 0).

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
  Fixture-tested against the real strip+combine output (59 assertions covering
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
  real inline `<script>` -- is replaced with a guard that admits
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
