# Changelog

All notable changes to the public cluster page.

## 2026-09-02

- **Page: instant tips on the Explorer pills, no Members caption** (2026-09-02,
  `build_cluster_page.R`, `scripts/test_page.mjs`): the two header pills carried
  their sign-in note as a native `title`, which the browser holds for about a
  second before showing, while every other tip on the page appears at once. The
  note now rides `data-tip`, so the page's own tip handler shows it instantly and
  styled like the rest. The muted "Members" caption that opened the cluster is
  gone: it said what the tip says. Section 23 of the page test asserts the tip
  text on each pill, no `title`, no caption span, and no caption rule.
- **Page: BU favicon** (2026-09-02, `assets/favicon.ico`, `build_cluster_page.R`,
  `scripts/test_page.mjs`, `README.md`): the head declares an icon: BU's own `favicon.ico`,
  the 16×16 ICO every bu.edu page serves, inline as a data URI and byte for
  byte the file www.bu.edu serves. The page declared none before, so every load
  asked GitHub Pages for `/favicon.ico`, which the `page` branch does not carry,
  and logged a 404 in the browser console. The file is this repo's own
  `assets/favicon.ico` (318 bytes), the one asset in the tree: BU's public
  favicon carries none of the licensing that keeps the fonts, plate and emblem
  in the sibling clone, and each of the three pages keeps its own copy. The
  builder reads it at build time like the sibling assets and fails closed
  without it. The page test pins the head to exactly one `rel="icon"` link,
  to those bytes, sitting after the title and ahead of the Google tag, and
  proves the source with two rebuilds against a sibling-assets fixture that
  has no icon: with `assets/favicon.ico` staged the page carries it, without
  it the build fails naming the file. Gate, validator and deploy guard pass
  unchanged.

## 2026-09-02 — published (cluster.cds.bu.edu)

- **Page: Google Analytics tag** (2026-09-02, `build_cluster_page.R`,
  `scripts/test_page.mjs`, `README.md`): the page reports visits to its own
  GA4 property, one property per page across the three CDS pages. The tag sits
  in the head after the title. It is Google's snippet with one change,
  `window.dataLayer.push` in place of the bare `dataLayer`: `validate.mjs` runs
  the inline scripts under a shim where that global is undefined, and Google's
  copy verbatim fails the gate. The page test's script rule moves from "one
  inline script, nothing external" to "the app script plus the Google loader
  and its bootstrap, and no other external script"; the no-fetch, no-storage,
  no-cookie-code and no-theme-detection rules stay, and the page may carry no
  measurement id but its own. The README no longer says "no tracking"; the
  footer's privacy statement link already covered analytics. Gate and validator
  pass. `deploy.sh`'s unconditional script guard matches the same rule: it
  refuses any sourced script other than the Google loader, whatever the tag's
  attributes (its old literal `<script src=` check missed `<script async
  src=`); `scripts/test_deploy.sh` covers a foreign loader refused and the
  Google loader accepted.

- **Page: explorer links in the header** (2026-09-02, `build_cluster_page.R`,
  `scripts/test_page.mjs`, `README.md`): a utilities cluster pinned top-right
  of the header in the pool explorers' own pill design, verbatim (translucent
  white pills, the pool word in its accent: chartreuse for GPU, cyan for CPU):
  a muted "Members" caption, then GPU Explorer and CPU Explorer in the panels'
  left-to-right order, each with a sign-in tooltip, navigating in the same tab
  as the explorers' own cross-links do. Caption and tooltip because the
  explorers are org-restricted: an anonymous visitor is redirected to sign-in.
  Below 1000px the cluster unpins and sits right-aligned under the lockup,
  which is longer here than on the explorers and collides with pinned pills at
  about 820px. Twenty new page-test assertions (markup, order, accents,
  tooltip, same-tab, the CSS verbatim, the narrow rule); gate and validator
  pass; verified by screenshot at 1440 and 820px.

- **Ops: `refresh_public.sh` refuses to run from the wrong checkout**
  (2026-09-02, `refresh_public.sh`, `scripts/test_refresh_guard.sh`,
  `README.md`): a preflight right after the lock. Every pipeline step's file
  must exist, so a checkout of the `page` orphan (index.html only) is refused
  under any branch name with a plain reason instead of R's "cannot open
  file". A run that could push (`DEPLOY_PUSH` unset or 1) must be on
  `PUB_EXPECT_BRANCH` (default `main`); `DEPLOY_PUSH=0` stages from any
  branch, and a deliberate publish from another branch names it. The pool
  dashboards' scripts carry the same pin as a cron-line opt-in; here it is on
  by default, because the case it closes is a hand run inside a development
  worktree, which no cron line covers. The quarterly cron line needs no
  change. Five throwaway-repo cases: main by default, a dev branch by
  default, a dev branch staged, the override, the sourceless checkout.

## 2026-09-01 — published (cluster.cds.bu.edu)

- **Docs: inputs and cadence after the GPU-source change** (2026-09-01,
  `README.md`): the page's description gains the over-time charts; the
  pipeline description names the two internal de-identified emits as the
  only data inputs.

- **Page: "Over time" charts under the totals** (2026-09-01,
  `build_cluster_page.R`, `validate.mjs`, `scripts/test_page.mjs`): a new
  section with one chart deck per pool (GPU Activity / CPU Activity) and
  three slides chosen by a segmented bar -- Monthly volume (reserved hours
  each month drawn inside a faint column of nominal capacity, with the
  cumulative total since the first published month as the headline),
  Weekly rhythm (reserved hours per complete week across the whole record,
  the busiest week as the headline) and Researchers (researchers and
  research groups per month, with the distinct totals over the record).
  Every chart is rendered when the page is built; the page's own script
  only switches slides, highlights the months of the period selected above
  (the rest of each series stays visible but dimmed), and advances the
  slides every ten seconds -- pausing while the pointer is over the
  section, stopping for good at the first click, and never moving at all
  for readers who ask their system for reduced motion. A hash such as
  `#rhy` opens the page on that slide. Bars are teal, capped at 24 px,
  separated by a surface gap; research groups use the page's ember hue with
  a legend; gridlines are hairlines; hovering any column shows its exact
  figures. The panel-saturation test is now scoped to the pool panels, and
  both script runners shadow the browser timers so the auto-advance cannot
  keep them alive. Fixture-tested (structure, default highlight, tooltips,
  hero and peak figures recomputed from the data, tab and timer behaviour,
  reduced-motion, a pool with no weekly rows) and verified by screenshot
  at 1440 and 1920 px.

- **Data layer + gate: GPU history from the GPU pool's own internal data, a
  complete-month rule for both pools, and a weekly table (contract v4)**
  (2026-09-01, `scripts/50_cluster_data.R`, `scripts/test_cluster_data.R`,
  `scripts/gate_cluster.mjs`, `scripts/test_gate.mjs`, `scripts/week_helpers.R`): the page no longer
  reads the GPU pool's separately published six-month extract; its hours,
  energy and VRAM series now come from the same de-identified internal data
  already read for researcher counts, aggregated by month and GPU type
  exactly as before, so the GPU record runs from April 2025 (the first
  complete month of GPU data) instead of the trailing six months. A month
  that began before a pool's data collection started never publishes, for
  either pool. New `weekly` rows -- reserved hours per complete ISO week,
  keyed by the week's Monday, one row per week inside the published months
  with zero where nothing ran -- feed the coming over-time charts. The gate
  checks every week is a Monday, that each pool's weeks are exactly the
  complete weeks inside its own published months (none missing, none extra,
  no duplicates), and that the weekly total sits within 5% of the monthly
  total. Fixture-tested end to end; the data layer builds with no GPU
  extract present.

- **Page: researchers, groups and capacity-reserved tiles; 12-month
  additions in the panel headers** (2026-09-01, `build_cluster_page.R`,
  `scripts/test_page.mjs`): every Totals card now leads with three new
  tiles -- Researchers served, Research groups, Capacity reserved (reserved
  hours as a share of the pool's nominal capacity-hours for the period) --
  ahead of the existing tiles, drawn from the new `community` and
  `capacity_monthly` tables. Each pool panel's header ("GPU Pool" / "CPU
  Pool") can also carry a right-aligned growth note -- "N GPUs added in the
  past 12 months" / "N nodes added in the past 12 months" -- shown only
  when that pool actually added hardware in the past year; a pool with no
  additions carries no note at all. The server-rendered default view and
  the page's own period-switching script compute every new number
  identically -- a lookup by the selected period's window key for the
  researcher/group counts, a sum over the window's months for capacity --
  with the same rounding as the existing tiles.
  Fixture-tested (244/244 total assertions, including a rebuild against a
  fixture with the two pools' 12-month additions swapped to confirm the
  header note is genuinely data-driven and not pinned to one pool) and
  verified end-to-end: `validate.mjs`, the de-id gate over the built page,
  and the full staged pipeline, all green.

- **Data layer + gate: community counts, nominal capacity-hours and
  12-month additions (contract v3)** (2026-09-01, `scripts/50_cluster_data.R`,
  `scripts/test_cluster_data.R`, `scripts/gate_cluster.mjs`,
  `scripts/test_gate.mjs`): a third read-only input joins the two pool
  dashboards' data -- the GPU pool's own internal de-identified emit, read
  ONLY for each month's distinct researcher/group membership (its other
  tables are never touched). Two new tables: `community` -- distinct
  researchers served and research groups with at least one job, for every
  selectable period (each published month, "Past 3 months", "Past 6
  months", "All months"), per pool; `capacity_monthly` -- nominal
  capacity-hours per month (cores for the CPU pool, GPUs for the GPU pool),
  prorated by each hardware unit's install/retirement date. Also adds
  `added_12m` per pool -- nominal units installed in the 12 months up to
  and including the run date, not retired. No researcher code or group
  name reaches any output field, only distinct counts. A period's
  researcher/group count is always the requested period intersected with
  that SAME pool's own published months, so every tile on a card covers
  the same span as its pool's other numbers (a period with no overlap for
  a pool reads zero, not an error) -- the coverage caption already
  discloses when a pool's data doesn't reach as far back as the period
  nominally suggests.
  The gate learns the new tables' vocabulary, requires every period/pool
  and month/pool combination to appear exactly once, and checks
  monotonicity directly across every pair (Past 3 <= Past 6, Past 6 <=
  All, and Past 3 <= All, plus any single month <= All), capacity-hours
  greater than zero, and additions never exceeding the pool total. It also
  reads every researcher code and group name out of both internal emits at
  gate time -- refusing to publish outright if that read comes back empty,
  since an empty check is a broken check, not "nothing to leak" -- and
  scans `cluster_data.json` and the built page, entity-decoded as well as
  raw, for a leak (an escaped `&amp;` can't hide a code containing `&`);
  a leak failure names the category and a short non-reversible local
  reference, never the value itself.
  Fixture-tested (`test_cluster_data.R`: 29 assertions; `test_gate.mjs`:
  48 assertions) and verified end-to-end against the real emits, gate
  included.

- **CPU panel: memory shown as a column, not a tooltip line**
  (2026-08-31, `build_cluster_page.R`, `scripts/test_page.mjs`): the CPU
  hardware panel gains a fourth column -- CPU, Cores, RAM, Nodes -- showing
  each model's per-node memory (e.g. "1,007 GB"), right-aligned like the
  Cores column. Both panels' model tooltips now read just
  "<Model><br>Server: <server>"; the redundant "RAM: ... GB per node" /
  "VRAM: ... GB per GPU" line is gone (the node-cluster tooltips, and the
  GPU panel's own VRAM column, are unchanged -- memory now appears exactly
  once per panel). Column widths were checked against real measured text
  rather than assumed: the Cores and RAM columns widen a little past the
  first pitch to comfortably fit the widest real values ("32 cores",
  "1,007 GB"), with the label column narrowing slightly to compensate; the
  GPU panel's share of the two-panel row narrows from 40% to 37% to make
  room. Confirmed the CPU hardware row's cluster-square layout still fits
  on one line with margin to spare at 1440/1700/1920px. Fixture-tested
  (204/204 total assertions) and run through `validate.mjs`, the de-id gate
  over the built page, and the full staged pipeline, all green.

- **Public page: totals cards show positive/neutral counterparts, no
  negative-connotation tiles** (2026-08-31, `build_cluster_page.R`,
  `scripts/test_page.mjs`): the GPU and CPU Totals cards no longer show
  Under-Utilized, Non-Utilized, on hard-failed jobs, on wall-killed jobs, or
  Walltime Accuracy -- every tile now reads as a positive or neutral fact
  about the period. GPU Totals (6 tiles): Reserved GPU-h, Utilized GPU-h
  (the same kernel-active hours the Avg utilization percentage is built
  from), Avg utilization, Jobs run, Energy used (kWh), Mean VRAM in use. CPU
  Totals (5 tiles): Reserved core-h, Utilized core-h, Avg efficiency, Jobs
  run, and a new tile, Core-h per job (Reserved core-hours divided by Jobs
  run, rounded to whole hours -- the typical reservation size; reads "–"
  when there were no jobs). Tooltips were rewritten alongside the tiles;
  none mention failures, wall-kills, or "lower is better" framing anymore.
  R and the inline JS compute every tile identically, verified by executing
  the embedded script and confirming its recompute matches the
  server-rendered default tile for tile, and that picking "All months" or a
  single month recomputes Jobs run and Core-h per job correctly alongside
  the rest. Fixture-tested (185/185 total assertions, up from 157) and run
  through `validate.mjs`, the de-id gate over the built page, and the full
  staged pipeline, all green.

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
  gains `aria-label="Month"` (it carried no accessible name).
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
  `scripts/test_page.mjs`, `validate.mjs`): replaces the static
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
  `scripts/test_page.mjs`): the footer stamp moves
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
