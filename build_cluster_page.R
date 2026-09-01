# =====================================================================
# build_cluster_page.R — the public showcase: a portal-lift of the two pool
# builders' own hardware/status panels (design revision of 2026-08-31). Twin
# pool panels (GPU left, CPU right) render pure CAPACITY -- every square/
# block fully saturated, no live occupancy, no LIVE/STALE badge -- plus a
# month-grain period selector and per-pool KPI totals cards recomputed by
# inline JS from the monthly tables (also server-rendered here for the
# default trailing-3-month window, so the page means something before/
# without JS). The old zero-JS rule is dead: this page ships exactly one
# inline <script>, self-contained -- no fetch/XHR, no storage, no theme
# machinery -- lifted from cpu-cds-scc/build_cpu_portal.R (renderLive(),
# its KPI card, TIPS, cpuLabel) and gpu-cds-scc/build_gpu_portal.R
# (livePanel(), its KPI card, cardGB) as the read-only source of visual
# truth. Neither sibling repo is written to. R6 (2026-09-01): an "Over
# time" section under the totals -- three server-rendered slides per pool
# (Monthly volume / Weekly rhythm / Researchers) as CSS bar columns; the
# inline script only switches slides, toggles the period highlight and
# runs a gentle auto-advance.
#
# Reads:  output/cluster_data.json          (contract v4, the strip+combine emit)
# Assets (base64-embedded, read from the sibling clone, never copied in):
#   $PUB_CPU_CLONE/assets/bu_plate_white.png
#   $PUB_CPU_CLONE/assets/faculty_compt_data_sci_signature_toptier_rgb.png
#   $PUB_CPU_CLONE/assets/WhitneySSmAdvancedSemibold.woff2   (weight 600)
#   $PUB_CPU_CLONE/assets/WhitneySSmAdvancedBook.woff2       (weight 400)
# Writes: index.html (repo root, gitignored)
# Run: module load R/4.5.2 && Rscript build_cluster_page.R
# =====================================================================
suppressPackageStartupMessages({
  library(jsonlite)
})

.f   <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
ROOT <- if (length(.f)) normalizePath(dirname(.f[[1]])) else normalizePath(".")

PUB_CPU_CLONE <- Sys.getenv("PUB_CPU_CLONE", "/usr3/bustaff/mhorn/repos/cpu-cds-scc")

dataf <- file.path(ROOT, "output", "cluster_data.json")
stopifnot(file.exists(dataf))
data_json <- paste(readLines(dataf, warn = FALSE), collapse = "\n")   # embedded verbatim as the page's DATA
d <- fromJSON(dataf, simplifyVector = TRUE)

b64 <- function(path) {
  if (!file.exists(path)) stop("build_cluster_page: missing asset ", path)
  paste(system2("base64", c("-w0", path), stdout = TRUE), collapse = "")
}
plate_uri     <- paste0("data:image/png;base64,", b64(file.path(PUB_CPU_CLONE, "assets", "bu_plate_white.png")))
emblem_uri    <- paste0("data:image/png;base64,", b64(file.path(PUB_CPU_CLONE, "assets", "faculty_compt_data_sci_signature_toptier_rgb.png")))
font_uri      <- paste0("data:font/woff2;base64,", b64(file.path(PUB_CPU_CLONE, "assets", "WhitneySSmAdvancedSemibold.woff2")))
font_uri_book <- paste0("data:font/woff2;base64,", b64(file.path(PUB_CPU_CLONE, "assets", "WhitneySSmAdvancedBook.woff2")))

# ---- helpers ----------------------------------------------------------------
jround <- function(x) floor(as.numeric(x) + 0.5)   # JS Math.round semantics (round-half-up, x >= 0) so R's server-render and the page's own JS agree bit-for-bit
fmt    <- function(x) format(jround(as.numeric(x)), big.mark = ",", trim = TRUE, scientific = FALSE)
fmth   <- function(x) { x <- as.numeric(x); if (is.na(x)) return("—"); if (x <= 0) return("0"); if (x < 1) return("&lt;1"); fmt(x) }
pct    <- function(num, den) if (!is.na(den) && den > 0) paste0(jround(100 * num / den), "%") else "0%"

esc_h <- function(s) { s <- gsub("&", "&amp;", s, fixed = TRUE); gsub("<", "&lt;", s, fixed = TRUE) }
esc_a <- function(s) { s <- gsub("&", "&amp;", s, fixed = TRUE); s <- gsub("\"", "&quot;", s, fixed = TRUE); gsub("<", "&lt;", s, fixed = TRUE) }

# Human-readable CPU model labels (GPU cards render as-is -- already short vendor
# names like L40S/H200). Lifted verbatim from cpu-cds-scc/build_cpu_portal.R's
# cpuLabel(): a Gold-/Silver-/Platinum-/Bronze- prefix loses its hyphen for a space;
# an EPYC- prefix becomes "AMD EPYC "; a trailing digit-v-digit ("2660v3") gets a
# space before the v; then "Xeon " is prepended when the label opens with E<digit>/
# Gold/Silver/Platinum/Bronze/W, or is a bare 4-digit(+letter) model.
model_label <- function(x) {
  x <- sub("^(Gold|Silver|Platinum|Bronze)-", "\\1 ", x)
  x <- sub("^EPYC-", "AMD EPYC ", x)
  x <- sub("(\\d)v(\\d)$", "\\1\u00a0v\\2", x)   # non-breaking space so "v3" never orphans onto its own line in the narrowed .hwlbl column
  xeon <- grepl("^(E\\d|Gold|Silver|Platinum|Bronze|W)", x) | grepl("^\\d{4}[A-Za-z]?$", x)
  ifelse(xeon, paste0("Xeon ", x), x)
}

MON <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
month_label <- function(m) paste0(MON[as.integer(substr(m, 6, 7))], " ", substr(m, 1, 4))

# resolved-range text in the "Totals" section header, e.g. "May – Jul 2026"
# (year shown once when both ends share a year) or "Jul 2026" for a single
# month -- no leading separator; it sits right after "Totals" in the title line.
# Mirrors the page's own JS rangeText() so the SSR default and a JS recompute agree.
range_text <- function(months) {
  if (!length(months)) return("")
  a <- months[1]; b <- months[length(months)]
  if (a == b) return(month_label(a))
  a_lbl <- if (substr(a, 1, 4) == substr(b, 1, 4)) MON[as.integer(substr(a, 6, 7))] else month_label(a)
  paste0(a_lbl, " – ", month_label(b))
}

# Per-card coverage note: the GPU series (trailing ~6 months by design) and the
# CPU series (full history) rarely cover the same window, so a wide selection
# ("All months", an early single month) can sum a pool's KPI card over months
# that pool has no rows for at all -- correct arithmetic, misleading framing
# (reads as "the pool did nothing" rather than "no data here"). Mirrors the
# page's own JS coverageNote() so the SSR default and a JS recompute agree.
# Returns list(note=, empty=): note is a caption ("GPU data: Feb – Jul 2026")
# shown when the window is only partly covered; empty is TRUE when the pool
# has no rows anywhere in the window (its KPI tiles are replaced entirely).
coverage_note <- function(months, pool_months, pool_label) {
  covered <- intersect(months, pool_months)
  if (length(covered) == length(months)) return(list(note = "", empty = FALSE))
  if (length(covered) == 0) return(list(note = "", empty = TRUE))
  list(note = paste0(pool_label, " data: ", range_text(covered)), empty = FALSE)
}

# ---- pool panels: one hardware row per capacity.types[] entry. No live data
# exists for this page (capacity, not occupancy) -- every block renders
# saturated. Node clusters are built purely from count x per_node; tooltips
# carry only the model and server -- no hostnames, no install dates. Per-node
# RAM / per-GPU VRAM appears exactly once per panel: as its own column on the
# CPU panel (a second .hwc cell, tagged .hwram so tests can target it), and as
# the GPU panel's existing VRAM column -- never duplicated into tooltip text.
# Adaptation of gpu-cds-scc build_gpu_portal.R livePanel() / cpu-cds-scc
# build_cpu_portal.R renderLive(): same hwtop/hwcols/hwrow/cnode idiom,
# held-related bits dropped since there is no live feed. ----
panel_row <- function(label, server, count, per_node, ram, pool) {
  disp <- if (pool == "cpu") model_label(label) else label
  unit <- if (pool == "cpu") paste0(fmt(per_node), " cores") else paste0(fmt(ram), " GB")
  row_tip <- paste0("<b>", esc_h(disp), "</b><br>Server: ", esc_h(server))
  cluster_tip <- if (pool == "cpu") paste0(fmt(per_node), " cores")
                 else paste0(fmt(per_node), " GPUs · ", fmt(ram), " GB each")
  square <- '<i class="on"></i>'
  one_cluster <- sprintf('<span class="cnode" data-tip="%s">%s</span>', esc_a(cluster_tip), paste(rep(square, per_node), collapse = ""))
  clusters <- paste(rep(one_cluster, count), collapse = "")
  ram_cell <- if (pool == "cpu") sprintf('<span class="hwc hwram">%s GB</span>', fmt(ram)) else ""
  sprintf('<div class="hwrow"><span class="hwlbl" data-tip="%s">%s</span><span class="hwc">%s</span>%s<span class="hwnodes">%s</span></div>',
          esc_a(row_tip), esc_h(disp), unit, ram_cell, clusters)
}

panel_html <- function(types, pool) {
  rows <- vapply(seq_len(nrow(types)), function(i) {
    panel_row(types[i, 1], types[i, 2], as.integer(types[i, 3]), as.integer(types[i, 4]), as.numeric(types[i, 5]), pool)
  }, character(1))
  head_lbl <- if (pool == "cpu") "CPU" else "GPU"
  unit_lbl <- if (pool == "cpu") "Cores" else "VRAM"
  ram_head <- if (pool == "cpu") '<span class="hwc hwram">RAM</span>' else ""
  cols <- sprintf('<div class="hwcols"><span class="hwlbl">%s</span><span class="hwc">%s</span>%s<span class="hwnodes">Nodes</span></div>', head_lbl, unit_lbl, ram_head)
  paste0(cols, paste(rows, collapse = "\n"))
}

gpu_panel <- panel_html(d$capacity$gpu$types, "gpu")
cpu_panel <- panel_html(d$capacity$cpu$types, "cpu")

# R5.2: a data-driven growth note in a pool panel's <h3>, right-aligned by the
# .pool h3 flex rule -- rendered ONLY when that pool's added_12m is > 0
# (maintainer ruling 2026-09-01); no <span> at all otherwise.
GROWTH_WORD <- list(cpu = c(singular = "node", plural = "nodes"), gpu = c(singular = "GPU", plural = "GPUs"))
growth_note <- function(pool, n) {
  n <- suppressWarnings(as.integer(n))
  if (is.na(n) || n <= 0) return("")
  word <- GROWTH_WORD[[pool]][[if (n == 1) "singular" else "plural"]]
  sprintf('<span class="hnote">%s %s added in the past 12 months</span>', fmt(n), word)
}
gpu_growth <- growth_note("gpu", d$capacity$gpu$added_12m)
cpu_growth <- growth_note("cpu", d$capacity$cpu$added_12m)

# ---- KPI totals: sum the monthly tables over a window (a set of "YYYY-MM"
# strings). Server-rendered here for the default trailing-3-month window
# (meta.window3) so the page means something before/without JS; the page's
# own inline JS repeats this arithmetic verbatim to recompute on a period
# change. The kpi() tile helper is lifted from the portals; the tile set
# itself is a deliberate revision for this public page -- every tile reads
# positive/neutral (Reserved, Utilized, Avg efficiency/utilization, Jobs
# run, Energy used, Mean VRAM in use, Core-h per job), with no
# negative-connotation counterpart (no Under-/Non-Utilized, no failed/
# wall-killed shares, no Walltime Accuracy). ----
as_mat <- function(x, ncol) if (is.null(dim(x))) matrix(x, ncol = ncol, byrow = TRUE) else x
cm <- as_mat(d$cpu_monthly, 9)   # month,node_class,held_h,utilized_h,fail_h,wkill_h,njobs,wa_used_h,wa_req_h
gm <- as_mat(d$gpu_monthly, 10)  # month,card,held_h,real_h,residle_h,kwh,vram_h,fail_h,wkill_h,njobs
cmty <- as_mat(d$community, 4)         # window_key,pool,users,groups
capm <- as_mat(d$capacity_monthly, 3)  # month,pool,cap_h
wk <- as_mat(d$weekly, 3)   # monday,pool,held_h (contract v4)

# R5.4 lookup/sum: community is looked up by window key (not re-summed --
# contract v3 already precomputes each pool's distinct-count intersection with
# its own published months for every selectable period); capacity_monthly is
# summed over the window's months for that pool. A window with no rows for a
# pool naturally sums/looks up to 0, matching the coverage-note "no data"
# replacement above (this pairing never surfaces a live 0/0 tile).
community_for <- function(window_key, pool) {
  idx <- which(cmty[, 1] == window_key & cmty[, 2] == pool)
  if (!length(idx)) return(list(users = 0L, groups = 0L))
  list(users = as.integer(cmty[idx[1], 3]), groups = as.integer(cmty[idx[1], 4]))
}
cap_sum_for <- function(months, pool) {
  idx <- capm[, 2] == pool & capm[, 1] %in% months
  sum(as.numeric(capm[idx, 3]))
}

sum_cpu_window <- function(months) {
  idx <- cm[, 1] %in% months
  list(held = sum(as.numeric(cm[idx, 3])), utilized = sum(as.numeric(cm[idx, 4])),
       fail_h = sum(as.numeric(cm[idx, 5])), wkill_h = sum(as.numeric(cm[idx, 6])),
       njobs = sum(as.numeric(cm[idx, 7])), wa_used_h = sum(as.numeric(cm[idx, 8])), wa_req_h = sum(as.numeric(cm[idx, 9])))
}
sum_gpu_window <- function(months) {
  idx <- gm[, 1] %in% months
  list(held = sum(as.numeric(gm[idx, 3])), real = sum(as.numeric(gm[idx, 4])), residle_h = sum(as.numeric(gm[idx, 5])),
       kwh = sum(as.numeric(gm[idx, 6])), vram_h = sum(as.numeric(gm[idx, 7])), fail_h = sum(as.numeric(gm[idx, 8])),
       wkill_h = sum(as.numeric(gm[idx, 9])), njobs = sum(as.numeric(gm[idx, 10])))
}

CPU_TIPS <- list(
  held = "Core-hours reserved by jobs: cores held × hours run.",
  utilized = "CPU time the jobs consumed.",
  eff = "Utilized over Reserved.",
  jobs = "Jobs that ran on the pool in the period.",
  perjob = "Reserved core-hours per job — the typical reservation size."
)
GPU_TIPS <- list(
  held = "GPU-hours reserved by jobs over the period: GPUs held × hours run.",
  utilized = "GPU-hours with active kernels, from sampled utilization.",
  busy = "Utilized over Reserved.",
  jobs = "Jobs that ran on the pool in the period.",
  kwh = "Energy from sampled GPU power.",
  vram = "Mean VRAM in use, as a share of capacity."
)
# R5.1: three new tiles lead every totals card, same tooltips on both pools.
COMMUNITY_TIPS <- list(
  users = "Distinct researchers who ran at least one job in the period.",
  groups = "Distinct research groups with at least one job in the period.",
  cap = "Share of the pool's nominal capacity-hours reserved by jobs. Reserved is not the same as busy — see Avg utilization."
)

kpi_tile <- function(n, l, t = "") sprintf('<div class="k"%s><div class="kl">%s</div><div class="kn">%s</div></div>',
                                            if (nzchar(t)) sprintf(' data-tip="%s"', t) else "", l, n)

community_tiles_html <- function(cmty_t, cap_pct) {
  paste0(
    kpi_tile(fmt(cmty_t$users), "Researchers served", COMMUNITY_TIPS$users),
    kpi_tile(fmt(cmty_t$groups), "Research groups", COMMUNITY_TIPS$groups),
    kpi_tile(cap_pct, "Capacity reserved", COMMUNITY_TIPS$cap)
  )
}

cpu_kpi_html <- function(T, cmty_t, cap_pct) {
  paste0(
    community_tiles_html(cmty_t, cap_pct),
    kpi_tile(fmth(T$held), "Reserved core-h", CPU_TIPS$held),
    kpi_tile(fmth(T$utilized), "Utilized core-h", CPU_TIPS$utilized),
    kpi_tile(pct(T$utilized, T$held), "Avg efficiency", CPU_TIPS$eff),
    kpi_tile(fmt(T$njobs), "Jobs run", CPU_TIPS$jobs),
    kpi_tile(if (T$njobs > 0) fmt(T$held / T$njobs) else "—", "Core-h per job", CPU_TIPS$perjob)
  )
}
gpu_kpi_html <- function(T, cmty_t, cap_pct) {
  paste0(
    community_tiles_html(cmty_t, cap_pct),
    kpi_tile(fmth(T$held), "Reserved GPU-h", GPU_TIPS$held),
    kpi_tile(fmth(T$real), "Utilized GPU-h", GPU_TIPS$utilized),
    kpi_tile(pct(T$real, T$held), "Avg utilization", GPU_TIPS$busy),
    kpi_tile(fmt(T$njobs), "Jobs run", GPU_TIPS$jobs),
    kpi_tile(fmth(T$kwh), "Energy used (kWh)", GPU_TIPS$kwh),
    kpi_tile(pct(T$vram_h, T$held), "Mean VRAM in use", GPU_TIPS$vram)
  )
}

window3 <- d$meta$window3
cpu_cov <- coverage_note(window3, d$meta$months_cpu, "CPU")
gpu_cov <- coverage_note(window3, d$meta$months_gpu, "GPU")
cpu_t3 <- sum_cpu_window(window3)
gpu_t3 <- sum_gpu_window(window3)
cpu_cap3 <- pct(cpu_t3$held, cap_sum_for(window3, "cpu"))
gpu_cap3 <- pct(gpu_t3$held, cap_sum_for(window3, "gpu"))
default_cpu_kpi <- if (cpu_cov$empty) '<div class="nodata">No CPU data for this period</div>' else cpu_kpi_html(cpu_t3, community_for("P3", "cpu"), cpu_cap3)
default_gpu_kpi <- if (gpu_cov$empty) '<div class="nodata">No GPU data for this period</div>' else gpu_kpi_html(gpu_t3, community_for("P3", "gpu"), gpu_cap3)
default_range <- range_text(window3)

# ---- period controls: a segmented [Past 3 | Past 6 | All] bar (default:
# Past 3 months, "on") plus a compact month-only <select> for single-month
# views (neutral "Month…" placeholder, month grain, every published month
# across CPU+GPU union). ----
all_months <- sort(unique(c(d$meta$months_cpu, d$meta$months_gpu)))
month_opts <- paste(vapply(rev(all_months), function(m) sprintf('<option value="%s">%s</option>', m, month_label(m)), character(1)), collapse = "")
month_select_options <- paste0('<option value="" selected>Month…</option>', month_opts)

# ---- R6 "Over time": three server-rendered slides per pool. The inline script
# never recomputes a chart -- it only switches slides, toggles the period
# highlight (.col.on for data-m in the selected window) and runs the
# auto-advance. Marks per R6.6: <= 24 px columns, 2 px surface gap (1 px
# weekly), 4 px rounded tops, hairline grid, no text in a series colour. ----
compact <- function(x) {   # 1.41 M / 261 k / 950 (R6.6)
  x <- as.numeric(x)
  if (x >= 1e6) return(paste0(sub("\\.?0+$", "", sprintf("%.2f", x / 1e6)), " M"))
  if (x >= 1e3) return(paste0(jround(x / 1e3), " k"))
  fmt(x)
}
tick_label <- function(x) {   # axis ticks: 150k / 1.2M (no space, one decimal)
  if (x >= 1e6) return(paste0(sub("\\.0$", "", sprintf("%.1f", x / 1e6)), "M"))
  if (x >= 1e3) return(paste0(sub("\\.0$", "", sprintf("%.1f", x / 1e3)), "k"))
  sub("\\.0$", "", sprintf("%.1f", x))
}
nice_ticks <- function(mx) {   # top = 1.04 x max; the smallest step in {1,2,2.5,5}x10^n giving <= 5 lines below top
  top <- max(mx, 1) * 1.04
  p <- 10^floor(log10(top / 4))
  cands <- c(1, 2, 2.5, 5, 10) * p
  # "<= 5 lines below top" counts the actual rendered ticks (seq() stops at <= top,
  # i.e. floor(top/step) of them) -- comparing the raw ratio to 5 instead rejects a
  # step like 5000 for top=28254 (ratio 5.65) even though it renders exactly 5 ticks,
  # skipping straight to a coarser step that renders only 2.
  step <- cands[which(floor(top / cands) <= 5)[1]]
  list(top = top, ticks = seq(step, top, by = step))
}
pc <- function(v, top) sprintf("%.2f", 100 * as.numeric(v) / top)   # heights/offsets as % of top, 2 dp
day_label <- function(d) { d <- as.Date(d); paste(as.integer(format(d, "%d")), MON[as.integer(format(d, "%m"))], format(d, "%Y")) }
QUARTER <- c(1L, 4L, 7L, 10L)

ov_plot <- function(tk, cols, xax, cls = "") {
  yax  <- paste0('<div class="yax">', paste(sprintf('<span style="bottom:%s%%">%s</span>', pc(tk$ticks, tk$top), vapply(tk$ticks, tick_label, character(1))), collapse = ""), '<span style="bottom:0">0</span></div>')
  grid <- paste(sprintf('<i style="bottom:%s%%"></i>', pc(tk$ticks, tk$top)), collapse = "")
  sprintf('<div class="plot%s">%s<div class="area"><div class="grid">%s</div><div class="cols">%s</div></div><div class="xax">%s</div></div>',
          if (nzchar(cls)) paste0(" ", cls) else "", yax, grid, paste(cols, collapse = ""), xax)
}
# x labels at quarter months (Jan/Apr/Jul/Oct); the year on January and on the first label
ov_x_monthly <- function(months) {
  out <- character(0); n <- length(months)
  for (i in seq_len(n)) {
    mo <- as.integer(substr(months[i], 6, 7)); if (!(mo %in% QUARTER)) next
    out <- c(out, sprintf('<span style="left:%.2f%%">%s</span>', 100 * (i - 0.5) / n, if (mo == 1L || i == 1L) month_label(months[i]) else MON[mo]))
  }
  paste(out, collapse = "")
}
ov_x_weekly <- function(mondays) {   # anchored at the first week whose Monday falls in a quarter month
  out <- character(0); n <- length(mondays); first <- TRUE; prev <- ""
  for (i in seq_len(n)) {
    m <- format(mondays[i], "%Y-%m"); mo <- as.integer(substr(m, 6, 7)); same <- identical(m, prev); prev <- m
    if (same || !(mo %in% QUARTER)) next
    out <- c(out, sprintf('<span style="left:%.2f%%">%s</span>', 100 * (i - 1) / n, if (mo == 1L || first) month_label(m) else MON[mo])); first <- FALSE
  }
  paste(out, collapse = "")
}
ov_col  <- function(m, tip, inner) sprintf('<span class="col%s" data-m="%s" data-tip="%s">%s</span>', if (m %in% window3) " on" else "", m, esc_a(tip), inner)
ov_peak <- function(h_pct, label) sprintf('<em class="pk" style="bottom:calc(%s%% + 2px)">%s</em>', h_pct, label)
held_for <- function(m, pool) if (pool == "cpu") sum_cpu_window(m)$held else sum_gpu_window(m)$held

ov_vol <- function(pool, months, unit, unit_long) {
  held <- vapply(months, held_for, numeric(1), pool = pool)
  cap  <- vapply(months, cap_sum_for, numeric(1), pool = pool)
  tk <- nice_ticks(max(cap)); peak <- which.max(held)
  cols <- vapply(seq_along(months), function(i) {
    hp  <- pc(held[i], tk$top)
    tip <- sprintf("<b>%s</b><br>%s %s reserved · %s of capacity<br>Nominal capacity %s %s", month_label(months[i]), fmt(held[i]), unit, pct(held[i], cap[i]), fmt(cap[i]), unit)
    ov_col(months[i], tip, sprintf('<b class="slot"><i class="trk" style="height:%s%%"></i><i class="bar" style="height:%s%%"></i>%s</b>',
                                   pc(cap[i], tk$top), hp, if (i == peak) ov_peak(hp, fmt(held[i])) else ""))
  }, character(1))
  sprintf('<div class="slide" data-s="vol"><div class="cap"><span class="ct">Reserved %s by month<i>reserved (solid) against nominal capacity (faint)</i></span><span class="hero"><b>%s</b>%s reserved since %s</span></div>%s</div>',
          unit_long, compact(sum(held)), unit_long, month_label(months[1]), ov_plot(tk, cols, ov_x_monthly(months)))
}
ov_rhy <- function(pool, unit, unit_long) {
  rows <- wk[wk[, 2] == pool, , drop = FALSE]
  if (!nrow(rows)) return(sprintf('<div class="slide" data-s="rhy" hidden><div class="cap"><span class="ct">Reserved %s by week</span></div><div class="nodata">No %s data</div></div>', unit_long, toupper(pool)))
  o <- order(rows[, 1]); mondays <- as.Date(rows[o, 1]); held <- as.numeric(rows[o, 3])
  tk <- nice_ticks(max(held)); peak <- which.max(held)
  cols <- vapply(seq_along(mondays), function(i) {
    hp  <- pc(held[i], tk$top)
    tip <- sprintf("<b>Week of %s</b><br>%s %s reserved", day_label(mondays[i]), fmt(held[i]), unit)
    ov_col(format(mondays[i] + 3, "%Y-%m"), tip,   # a week belongs to the month of its Thursday (R6.6)
           sprintf('<b class="slot"><i class="bar" style="height:%s%%"></i>%s</b>', hp, if (i == peak) ov_peak(hp, fmt(held[i])) else ""))
  }, character(1))
  sprintf('<div class="slide" data-s="rhy" hidden><div class="cap"><span class="ct">Reserved %s by week<i>complete weeks, %s – %s</i></span><span class="hero"><b>%s</b>%s in the busiest week (%s)</span></div>%s</div>',
          unit_long, day_label(mondays[1]), day_label(mondays[length(mondays)] + 6), fmt(held[peak]), unit_long, day_label(mondays[peak]),
          ov_plot(tk, cols, ov_x_weekly(mondays), "wk"))
}
ov_com <- function(pool, months) {
  cm_m   <- lapply(paste0("M:", months), community_for, pool = pool)
  users  <- vapply(cm_m, function(x) as.numeric(x$users), numeric(1))
  groups <- vapply(cm_m, function(x) as.numeric(x$groups), numeric(1))
  all_r  <- community_for("ALL", pool)
  tk <- nice_ticks(max(users)); peak <- which.max(users)
  cols <- vapply(seq_along(months), function(i) {
    up  <- pc(users[i], tk$top)
    tip <- sprintf("<b>%s</b><br>%s researchers · %s research groups", month_label(months[i]), fmt(users[i]), fmt(groups[i]))
    ov_col(months[i], tip, sprintf('<b class="pair"><i class="u" style="height:%s%%"></i><i class="g" style="height:%s%%"></i>%s</b>',
                                   up, pc(groups[i], tk$top), if (i == peak) ov_peak(up, fmt(users[i])) else ""))
  }, character(1))
  sprintf('<div class="slide" data-s="com" hidden><div class="cap"><span class="ct">Researchers and research groups by month<span class="lg"><i class="u"></i>Researchers<i class="g"></i>Research groups</span></span><span class="hero"><b>%s</b>researchers · <b>%s</b>research groups since %s</span></div>%s</div>',
          fmt(all_r$users), fmt(all_r$groups), month_label(months[1]), ov_plot(tk, cols, ov_x_monthly(months)))
}
ov_deck <- function(pool) {
  months <- if (pool == "cpu") d$meta$months_cpu else d$meta$months_gpu
  unit <- if (pool == "cpu") "core-h" else "GPU-h"; unit_long <- if (pool == "cpu") "core-hours" else "GPU-hours"
  sprintf('<div class="deck ov" id="%sov"><h3>%s Activity</h3>%s%s%s</div>', pool, toupper(pool),
          ov_vol(pool, months, unit, unit_long), ov_rhy(pool, unit, unit_long), ov_com(pool, months))
}
ov_gpu_deck  <- ov_deck("gpu")
ov_cpu_deck  <- ov_deck("cpu")
ov_range_all <- range_text(all_months)

# ---- assemble ----------------------------------------------------------------
html <- paste0(
r"-----(<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Research Computing at CDS</title>
<style>
:root{
 --t-sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
 --t-mono:ui-monospace,"SF Mono",SFMono-Regular,Menlo,Consolas,"Liberation Mono",monospace;
 --content-max:2100px;--content-pad:12px;
 --bg:#f2efec;--surface:#ffffff;--surface2:#ebe6e0;
 --ink:#2d2926;--text:#2d2926;--muted:#6b6158;--grid:#e8e3dd;--border:#dcd5cd;
 --used:#0b7468;--idle:#c0cad4;--ember:#b4451f;--headbg:#2d2926;--headfg:#ffffff;--shadow:rgba(15,30,45,.10);--hatch:rgba(20,30,42,.34);--busy:#dc2626;--free:#2563eb;--rule:#b7ada2;--hl:#fde68a;--amber:#e0a63e;--rust:#a0522d;
}
@font-face{font-family:"Whitney SSm A";font-weight:600;font-style:normal;font-display:swap;src:url(")-----",
font_uri,
r"-----(") format("woff2");}
@font-face{font-family:"Whitney SSm A";font-weight:400;font-style:normal;font-display:swap;src:url(")-----",
font_uri_book,
r"-----(") format("woff2");}
*{box-sizing:border-box}html{font-size:110%;}html,body{height:100%;}body{display:flex;flex-direction:column;min-height:100vh;min-height:100dvh;font-family:var(--t-sans);color:var(--text);margin:0;background:var(--bg);font-size:0.813rem;line-height:1.45;-webkit-font-smoothing:antialiased;}
header{background:var(--headbg);color:var(--headfg);padding:12px var(--content-pad);position:relative;border-top:3px solid #cc0000;border-bottom:1px solid rgba(255,255,255,.08);}header h1{font-size:1rem;margin:0;font-weight:600;letter-spacing:-.01em;font-family:"Whitney SSm A",var(--t-sans);}.buplate{height:1.615em;vertical-align:-.449em;margin-right:.34em;}.orgname{font-weight:400;letter-spacing:0;}.hsep{color:rgba(255,255,255,.4);font-weight:400;padding:0 .6em;}
.hwrap{max-width:min(var(--content-max),98vw);margin:0 auto;display:flex;align-items:baseline;gap:14px;flex-wrap:wrap;}
main{max-width:min(var(--content-max),98vw);width:100%;margin:0 auto;padding:14px var(--content-pad) 60px;flex:1 0 auto;}
h3{font-size:0.85rem;font-weight:600;color:var(--ink);margin:0 0 10px;}
.deck{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:11px 12px;margin-bottom:12px;box-shadow:0 1px 3px var(--shadow);}
.deck h3{font-size:0.8rem;font-weight:700;color:var(--ink);margin:0 0 8px;}
.pool-gpu h3,.pool-cpu h3,#gpucard h3,#cpucard h3{border-bottom:3px solid;padding-bottom:6px;margin-bottom:10px;}
.pool-gpu h3,#gpucard h3{border-color:#baf72e;}
.pool-cpu h3,#cpucard h3{border-color:#4cc9db;}
.pool h3{display:flex;justify-content:space-between;align-items:baseline}
.hnote{font-weight:400;font-size:0.72rem;color:var(--muted);letter-spacing:0;white-space:nowrap}
.deckrow{display:flex;gap:16px;align-items:stretch;margin-bottom:12px;}.deckrow .deck{flex:1 1 auto;margin-bottom:0;min-width:0;}
#gpupanel,#gpucard{flex:0 1 37%;}#cpupanel,#cpucard{flex:1 1 0;}
@media(max-width:900px){.deckrow{display:block;}.deckrow .deck{margin-bottom:12px;}.sechead{flex-wrap:wrap;}}
select{font:inherit;font-size:0.781rem;padding:3px 6px;border:1px solid var(--border);border-radius:5px;background:var(--surface);color:var(--text);}#pmonth{font-variant-numeric:tabular-nums;}
.sechead{display:flex;align-items:baseline;justify-content:space-between;gap:16px;margin:0 0 10px;padding-bottom:6px;border-bottom:1px solid var(--rule);}
.sechead .ttl{font-size:.8rem;font-weight:700;color:var(--ink);}.sechead .ttl span{font-weight:400;color:var(--muted);margin-left:8px;}
.sechead .ctl{display:flex;align-items:center;gap:10px;}
.seg{display:inline-flex;border:1px solid var(--border);border-radius:5px;overflow:hidden;}.seg button{border:none;border-right:1px solid var(--border);background:var(--surface);font:inherit;font-size:0.75rem;padding:4px 10px;cursor:pointer;color:var(--text);border-radius:0;}.seg button:last-child{border-right:none;}.seg button:hover{background:var(--surface2);}.seg button.on{background:var(--used);color:#fff;}
.hwcols,.hwrow{display:grid;grid-template-columns:var(--lblw) var(--valw) 1fr;column-gap:18px;align-items:center;}.hwcols{font-size:0.75rem;border-bottom:1px solid var(--border);padding-bottom:4px;margin-bottom:2px;}.hwcols span{color:var(--ink);font-weight:bold;}
.hwrow{padding:5px 0;border-bottom:1px solid var(--grid);}.hwrow:last-child{border-bottom:none;padding-bottom:0;}
.hwlbl{color:var(--text);white-space:nowrap;}.hwc{text-align:right;color:var(--text);font-variant-numeric:tabular-nums;white-space:nowrap;}
.hwnodes{display:flex;flex-wrap:wrap;gap:8px;align-items:center;}
.pool-cpu .hwcols,.pool-cpu .hwrow{grid-template-columns:var(--lblw) var(--valw) var(--ramw) 1fr;}
.pool-cpu{--lblw:120px;--valw:60px;--ramw:66px;--core-s:clamp(5px,0.35vw,12px);}.pool-cpu .cnode{display:grid;grid-template-columns:repeat(8,var(--core-s));gap:3px;padding:5px;border:1px solid var(--border);border-radius:6px;background:var(--surface2);}.pool-cpu .cnode i{width:var(--core-s);height:var(--core-s);border-radius:3px;display:block;background:var(--idle);}.pool-cpu .cnode i.on{background:var(--used);}
.pool-gpu{--lblw:80px;--valw:56px;--gpu-w:clamp(13px,0.93vw,40px);--gpu-h:clamp(10px,0.47vw,20px);}.pool-gpu .cnode{display:inline-flex;gap:3px;padding:5px;border:1px solid var(--border);border-radius:6px;background:var(--surface2);}.pool-gpu .cnode i{width:var(--gpu-w);height:var(--gpu-h);border-radius:4px;display:block;background:var(--idle);}.pool-gpu .cnode i.on{background:var(--used);}
@media(min-width:1700px){.pool-cpu{--core-s:clamp(8px,0.5vw,12px);}.pool-gpu{--gpu-w:clamp(22px,1.4vw,40px);--gpu-h:clamp(11px,0.7vw,20px);}.deck{padding:13px 14px;}.kpi .kn{font-size:1.3rem;}}
[data-tip]{cursor:help;}
#tip{position:fixed;z-index:99;max-width:300px;background:#0f1f3a;color:#eaf1fb;font-size:0.719rem;line-height:1.45;padding:7px 10px;border-radius:6px;box-shadow:0 6px 22px rgba(0,0,0,.28);pointer-events:none;display:none;}#tip b{color:#9ec5ff;font-weight:600;}
.kpi{display:grid;grid-template-columns:repeat(2,1fr);gap:14px 18px;margin:0;}.kpi .k{padding:0;}
.kpi .kn{font-size:1.188rem;font-weight:bold;color:var(--ink);font-variant-numeric:tabular-nums;letter-spacing:-.01em;line-height:1.15;}.kpi .kl{font-size:0.688rem;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.04em;margin-bottom:2px;white-space:nowrap;}.kpi .k[data-tip]{cursor:help;}
.covnote{font-size:0.7rem;color:var(--muted);margin:-4px 0 8px;}.covnote:empty{display:none;margin:0;}
.nodata{color:var(--muted);font-size:0.8rem;padding:8px 0;grid-column:1/-1;}
.livewrap{margin:0 0 10px;padding:0;display:flex;flex-wrap:wrap;gap:16px;align-items:center;}
.liveupd{color:var(--text);font-size:0.75rem;white-space:nowrap;}
.liveupd a{color:inherit;text-decoration:underline;text-decoration-color:var(--muted);text-underline-offset:2px;}
.liveupd a:hover{color:var(--used);text-decoration-color:currentColor;}
.pagefoot{max-width:min(var(--content-max),98vw);width:100%;margin:0 auto;margin-top:auto;padding:18px var(--content-pad) 30px;border-top:1px solid var(--border);display:flex;align-items:center;justify-content:space-between;gap:18px;flex-wrap:wrap;}
.pagefoot .ft-l{flex:1 1 200px;display:flex;align-items:center;}
.pagefoot .ft-c{flex:0 0 auto;text-align:center;}
.pagefoot .ft-r{flex:1 1 200px;text-align:right;}
.ft-emblem{height:30px;width:auto;display:block;}
.ft-link{color:var(--muted);font-size:0.75rem;text-decoration:none;display:inline-flex;align-items:center;}
.ft-link:hover{color:var(--used);text-decoration:underline;}
.ft-gh{color:var(--muted);}
.ft-gh:hover{color:var(--used);}
.ft-gh svg{height:30px;width:auto;display:block;}
.slide[hidden]{display:none}
#gpuov{flex:0 1 37%;}#cpuov{flex:1 1 0;}
#gpuov h3,#cpuov h3{border-bottom:3px solid;padding-bottom:6px;margin-bottom:10px;}#gpuov h3{border-color:#baf72e;}#cpuov h3{border-color:#4cc9db;}
.ov{--dim:.5;}
.ov .cap{display:flex;flex-direction:column;gap:3px;margin:0 0 8px;}
.ov .ct{font-size:.75rem;font-weight:600;color:var(--text);}.ov .ct>i{font-style:normal;font-weight:400;color:var(--muted);margin-left:8px;}
.ov .hero{font-size:.72rem;color:var(--muted);white-space:nowrap;}.ov .hero b{font-size:1.25rem;font-weight:600;color:var(--ink);letter-spacing:-.01em;margin-right:5px;}.ov .hero b+b{margin-left:6px;}
.ov .lg{display:inline-flex;align-items:center;gap:10px;margin-left:10px;font-size:.7rem;font-weight:400;color:var(--muted);}.ov .lg i{display:inline-block;width:9px;height:9px;border-radius:2px;margin-right:4px;vertical-align:-1px;}.ov .lg i.u{background:var(--used);}.ov .lg i.g{background:var(--ember);}
.ov .plot{display:grid;grid-template-columns:auto 1fr;grid-template-rows:var(--h,190px) auto;column-gap:8px;}
.ov .yax{position:relative;min-width:26px;font-size:.65rem;line-height:1;color:var(--muted);font-variant-numeric:tabular-nums;text-align:right;}.ov .yax span{position:absolute;right:0;transform:translateY(50%);}
.ov .area{position:relative;}.ov .grid i{position:absolute;left:0;right:0;border-top:1px solid var(--grid);}
.ov .cols{position:absolute;inset:0;display:flex;align-items:flex-end;gap:2px;border-bottom:1px solid var(--rule);}.ov .wk .cols{gap:1px;}
.ov .col{flex:1 1 0;min-width:0;height:100%;display:flex;align-items:flex-end;justify-content:center;cursor:help;}
.ov .slot,.ov .pair{position:relative;width:100%;max-width:24px;height:100%;}
.ov .trk{position:absolute;left:0;right:0;bottom:0;background:rgba(11,116,104,.10);border-radius:4px 4px 0 0;}
.ov .bar{position:absolute;left:0;right:0;bottom:0;background:var(--used);border-radius:4px 4px 0 0;opacity:var(--dim);}.ov .wk .bar{border-radius:2px 2px 0 0;}
.ov .pair{display:flex;gap:2px;align-items:flex-end;max-width:28px;}.ov .pair i{flex:1 1 0;border-radius:3px 3px 0 0;opacity:var(--dim);}.ov .pair .u{background:var(--used);}.ov .pair .g{background:var(--ember);}
.ov .col.on .bar,.ov .col.on .pair i,.ov .col:hover .bar,.ov .col:hover .pair i{opacity:1;}
.ov .pk{position:absolute;left:50%;transform:translateX(-50%);font-size:.62rem;font-style:normal;line-height:1;color:var(--muted);white-space:nowrap;padding-bottom:1px;}
.ov .xax{grid-column:2;position:relative;height:16px;margin-top:5px;font-size:.65rem;line-height:1;color:var(--muted);}.ov .xax span{position:absolute;top:0;white-space:nowrap;transform:translateX(-50%);}
.ov .wk .xax span{transform:none;padding-left:4px;border-left:1px solid var(--rule);margin-top:-5px;padding-top:5px;}
.ov .nodata{padding:8px 0;}
@media(min-width:1700px){.ov .plot{--h:220px;}}
</style></head><body>
<header><div class="hwrap"><h1><img class="buplate" src=")-----",
plate_uri,
r"-----(" alt="Boston University"><span class="orgname">Faculty of Computing &amp; Data Sciences</span><span class="hsep">|</span>Research Computing at CDS</h1></div></header>
<main>
<div class="livewrap"><span class="liveupd"><a href="https://rcs.bu.edu" target="_blank" rel="noopener">Data from BU SCC</a> · updated quarterly · )-----",
d$meta$updated,
r"-----(</span></div>
<div class="deckrow">
<div class="deck pool pool-gpu" id="gpupanel"><h3>GPU Pool)-----",
gpu_growth,
r"-----(</h3>)-----",
gpu_panel,
r"-----(</div>
<div class="deck pool pool-cpu" id="cpupanel"><h3>CPU Pool)-----",
cpu_growth,
r"-----(</h3>)-----",
cpu_panel,
r"-----(</div>
</div>
<div class="sechead" id="sechead">
<div class="ttl">Totals<span id="prange">)-----",
default_range,
r"-----(</span></div>
<div class="ctl">
<span class="seg"><button id="seg-p3" class="on" data-w="past3">Past 3 months</button><button id="seg-p6" data-w="past6">Past 6 months</button><button id="seg-all" data-w="all">All months</button></span>
<select id="pmonth" aria-label="Month">)-----",
month_select_options,
r"-----(</select>
</div>
</div>
<div class="deckrow">
<div class="deck" id="gpucard"><h3>GPU Totals</h3><div class="covnote" id="gpu-cov">)-----",
gpu_cov$note,
r"-----(</div><div class="kpi" id="kpi-gpu">)-----",
default_gpu_kpi,
r"-----(</div></div>
<div class="deck" id="cpucard"><h3>CPU Totals</h3><div class="covnote" id="cpu-cov">)-----",
cpu_cov$note,
r"-----(</div><div class="kpi" id="kpi-cpu">)-----",
default_cpu_kpi,
r"-----(</div></div>
</div>
<div class="sechead" id="ovhead">
<div class="ttl">Over time<span>)-----",
ov_range_all,
r"-----( · <span id="ovsel">)-----",
default_range,
r"-----(</span> highlighted</span></div>
<div class="ctl"><span class="seg" id="ovtabs"><button class="on" data-s="vol">Monthly volume</button><button data-s="rhy">Weekly rhythm</button><button data-s="com">Researchers</button></span></div>
</div>
<div class="deckrow">
)-----",
ov_gpu_deck,
"\n",
ov_cpu_deck,
r"-----(
</div>
</main>
<footer class="pagefoot"><div class="ft-l"><img class="ft-emblem" src=")-----",
emblem_uri,
r"-----(" alt="Boston University Faculty of Computing &amp; Data Sciences"></div><div class="ft-c"><a class="ft-link ft-gh" href="https://github.com/BU-CDS/pub-cds-scc" target="_blank" rel="noopener" aria-label="GitHub repository" title="GitHub repository"><svg viewBox="0 0 16 16" width="19" height="19" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"></path></svg></a></div><div class="ft-r"><a class="ft-link" href="https://www.bu.edu/policies/digital-privacy-statement/" target="_blank" rel="noopener">Privacy Statement</a></div></footer>
<script>
const DATA = )-----",
data_json,
r"-----(;
const $=s=>document.querySelector(s);
function fmt(x){return Math.round(x).toLocaleString('en-US');}
function fmth(x){if(x==null)return '—';if(x<=0)return '0';if(x<1)return '&lt;1';return Math.round(x).toLocaleString('en-US');}
const kpi=(n,l,t)=>'<div class=k'+(t?' data-tip="'+t+'"':'')+'><div class=kl>'+l+'</div><div class=kn>'+n+'</div></div>';
const CPU_TIPS={
 held:'Core-hours reserved by jobs: cores held × hours run.',
 utilized:'CPU time the jobs consumed.',
 eff:'Utilized over Reserved.',
 jobs:'Jobs that ran on the pool in the period.',
 perjob:'Reserved core-hours per job — the typical reservation size.'
};
const GPU_TIPS={
 held:'GPU-hours reserved by jobs over the period: GPUs held × hours run.',
 utilized:'GPU-hours with active kernels, from sampled utilization.',
 busy:'Utilized over Reserved.',
 jobs:'Jobs that ran on the pool in the period.',
 kwh:'Energy from sampled GPU power.',
 vram:'Mean VRAM in use, as a share of capacity.'
};
const COMMUNITY_TIPS={
 users:'Distinct researchers who ran at least one job in the period.',
 groups:'Distinct research groups with at least one job in the period.',
 cap:'Share of the pool\'s nominal capacity-hours reserved by jobs. Reserved is not the same as busy — see Avg utilization.'
};
const ALLM=[...new Set([...DATA.meta.months_cpu,...DATA.meta.months_gpu])].sort();
function windowFor(v){
  if(v==='past3')return DATA.meta.window3.slice();
  if(v==='past6')return ALLM.slice(-6);
  if(v==='all')return ALLM.slice();
  return [v];
}
function keyFor(v){
  if(v==='past3')return 'P3';
  if(v==='past6')return 'P6';
  if(v==='all')return 'ALL';
  return 'M:'+v;
}
function communityFor(key,pool){
  for(const r of DATA.community)if(r[0]===key&&r[1]===pool)return{users:r[2],groups:r[3]};
  return{users:0,groups:0};
}
function capForWindow(months,pool){
  const set=new Set(months);let s=0;
  for(const r of DATA.capacity_monthly)if(r[1]===pool&&set.has(r[0]))s+=r[2];
  return s;
}
function sumCpu(months){
  const set=new Set(months);
  const T={held:0,utilized:0,fail_h:0,wkill_h:0,njobs:0,wa_used_h:0,wa_req_h:0};
  for(const r of DATA.cpu_monthly){if(!set.has(r[0]))continue;T.held+=r[2];T.utilized+=r[3];T.fail_h+=r[4];T.wkill_h+=r[5];T.njobs+=r[6];T.wa_used_h+=r[7];T.wa_req_h+=r[8];}
  return T;
}
function sumGpu(months){
  const set=new Set(months);
  const T={held:0,real:0,residle_h:0,kwh:0,vram_h:0,fail_h:0,wkill_h:0,njobs:0};
  for(const r of DATA.gpu_monthly){if(!set.has(r[0]))continue;T.held+=r[2];T.real+=r[3];T.residle_h+=r[4];T.kwh+=r[5];T.vram_h+=r[6];T.fail_h+=r[7];T.wkill_h+=r[8];T.njobs+=r[9];}
  return T;
}
function communityTilesHtml(cm,capPct){
  return kpi(fmt(cm.users),'Researchers served',COMMUNITY_TIPS.users)
    +kpi(fmt(cm.groups),'Research groups',COMMUNITY_TIPS.groups)
    +kpi(capPct+'%','Capacity reserved',COMMUNITY_TIPS.cap);
}
function cpuKpiHtml(T,cm,capPct){
  return communityTilesHtml(cm,capPct)
    +kpi(fmth(T.held),'Reserved core-h',CPU_TIPS.held)
    +kpi(fmth(T.utilized),'Utilized core-h',CPU_TIPS.utilized)
    +kpi((T.held?Math.round(100*T.utilized/T.held):0)+'%','Avg efficiency',CPU_TIPS.eff)
    +kpi(fmt(T.njobs),'Jobs run',CPU_TIPS.jobs)
    +kpi(T.njobs>0?fmt(T.held/T.njobs):'—','Core-h per job',CPU_TIPS.perjob);
}
function gpuKpiHtml(T,cm,capPct){
  return communityTilesHtml(cm,capPct)
    +kpi(fmth(T.held),'Reserved GPU-h',GPU_TIPS.held)
    +kpi(fmth(T.real),'Utilized GPU-h',GPU_TIPS.utilized)
    +kpi((T.held?Math.round(100*T.real/T.held):0)+'%','Avg utilization',GPU_TIPS.busy)
    +kpi(fmt(T.njobs),'Jobs run',GPU_TIPS.jobs)
    +kpi(fmth(T.kwh),'Energy used (kWh)',GPU_TIPS.kwh)
    +kpi((T.held?Math.round(100*T.vram_h/T.held):0)+'%','Mean VRAM in use',GPU_TIPS.vram);
}
const MON=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
function monthLabel(m,withYear){return MON[+m.slice(5,7)-1]+(withYear?' '+m.slice(0,4):'');}
function rangeText(months){
  if(!months.length)return '';
  const a=months[0],b=months[months.length-1];
  if(a===b)return monthLabel(a,true);
  const sameYear=a.slice(0,4)===b.slice(0,4);
  return monthLabel(a,!sameYear)+' – '+monthLabel(b,true);
}
function coverageNote(months,poolMonths,poolLabel){
  const set=new Set(poolMonths);
  const covered=months.filter(m=>set.has(m));
  if(covered.length===months.length)return {note:'',empty:false};
  if(covered.length===0)return {note:'',empty:true};
  return {note:poolLabel+' data: '+rangeText(covered),empty:false};
}
function applyWindow(months,key){
  const cpuCov=coverageNote(months,DATA.meta.months_cpu,'CPU');
  const gpuCov=coverageNote(months,DATA.meta.months_gpu,'GPU');
  $('#cpu-cov').textContent=cpuCov.note;
  $('#gpu-cov').textContent=gpuCov.note;
  const cpuT=sumCpu(months),cpuCapH=capForWindow(months,'cpu');
  const gpuT=sumGpu(months),gpuCapH=capForWindow(months,'gpu');
  $('#kpi-cpu').innerHTML=cpuCov.empty?'<div class="nodata">No CPU data for this period</div>':cpuKpiHtml(cpuT,communityFor(key,'cpu'),cpuCapH?Math.round(100*cpuT.held/cpuCapH):0);
  $('#kpi-gpu').innerHTML=gpuCov.empty?'<div class="nodata">No GPU data for this period</div>':gpuKpiHtml(gpuT,communityFor(key,'gpu'),gpuCapH?Math.round(100*gpuT.held/gpuCapH):0);
  $('#prange').textContent=rangeText(months);
  ovHighlight(months);
}
const SEGS=[['#seg-p3','past3'],['#seg-p6','past6'],['#seg-all','all']];
SEGS.forEach(([sel])=>{
  const b=$(sel);
  b.addEventListener('click',()=>{
    SEGS.forEach(([s])=>$(s).classList.remove('on'));
    b.classList.add('on');
    $('#pmonth').value='';
    applyWindow(windowFor(b.dataset.w),keyFor(b.dataset.w));
  });
});
$('#pmonth').addEventListener('change',()=>{
  const v=$('#pmonth').value;
  if(!v)return;
  SEGS.forEach(([s])=>$(s).classList.remove('on'));
  applyWindow(windowFor(v),keyFor(v));
});
const OV_ORDER=['vol','rhy','com'];
const ovTabs=[...document.querySelectorAll('#ovtabs button')],ovSlides=[...document.querySelectorAll('.ov .slide')];
let ovCur=0,ovTimer=null,ovStopped=false;
const ovReduce=!!(window.matchMedia&&window.matchMedia('(prefers-reduced-motion: reduce)').matches);
function ovShow(k){ovCur=OV_ORDER.indexOf(k);ovTabs.forEach(b=>b.classList.toggle('on',b.dataset.s===k));ovSlides.forEach(s=>{s.hidden=s.dataset.s!==k;});}
function ovStop(){if(ovTimer){clearInterval(ovTimer);ovTimer=null;}}
function ovStart(){if(ovStopped||ovReduce||ovTimer)return;ovTimer=setInterval(()=>ovShow(OV_ORDER[(ovCur+1)%OV_ORDER.length]),10000);}
function ovHighlight(months){const set=new Set(months);document.querySelectorAll('.ov [data-m]').forEach(el=>el.classList.toggle('on',set.has(el.dataset.m)));const sel=$('#ovsel');if(sel)sel.textContent=rangeText(months);}
ovTabs.forEach(b=>b.addEventListener('click',()=>{ovStopped=true;ovStop();ovShow(b.dataset.s);}));
['#ovhead','#gpuov','#cpuov'].forEach(s=>{const el=$(s);if(!el)return;el.addEventListener('mouseenter',ovStop);el.addEventListener('mouseleave',ovStart);});
document.addEventListener('visibilitychange',()=>{if(document.hidden)ovStop();else ovStart();});
{const h=(typeof location==='undefined'?'':(location.hash||'')).slice(1);if(OV_ORDER.includes(h)){ovStopped=true;ovShow(h);}else ovStart();}
ovHighlight(DATA.meta.window3);
const tipEl=document.createElement('div');tipEl.id='tip';
function posTip(x,y){const w=tipEl.offsetWidth,h=tipEl.offsetHeight;let L=x+14,T=y+16;if(L+w>innerWidth-8)L=Math.max(8,x-w-14);if(T+h>innerHeight-8)T=Math.max(8,y-h-16);tipEl.style.left=L+'px';tipEl.style.top=T+'px';}
function showTip(html,x,y){if(!html){tipEl.style.display='none';return;}tipEl.innerHTML=html;tipEl.style.display='block';posTip(x,y);}
document.body.appendChild(tipEl);
document.addEventListener('mousemove',e=>{const d=e.target.closest&&e.target.closest('[data-tip]');showTip(d?d.dataset.tip:'',e.clientX,e.clientY);});
document.addEventListener('focusin',e=>{const t=e.target,r=t.getBoundingClientRect&&t.getBoundingClientRect();if(!r)return;const d=t.closest&&t.closest('[data-tip]');showTip(d?d.dataset.tip:'',r.left,r.bottom);});
document.addEventListener('focusout',()=>showTip(''));
</script>
</body></html>
)-----"
)

writeLines(html, file.path(ROOT, "index.html"), useBytes = TRUE)
cat(sprintf("build_cluster_page: wrote index.html (%d bytes)\n", nchar(html, type = "bytes")))
