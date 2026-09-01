# =====================================================================
# build_cluster_page.R — the public showcase: a portal-lift of the two pool
# builders' own hardware/status panels (spec Revision R1, 2026-08-31). Twin
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
# truth. Neither sibling repo is written to.
#
# Reads:  output/cluster_data.json          (contract v2, Task 7's strip+combine emit)
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

b64 <- function(path) if (file.exists(path)) paste(system2("base64", c("-w0", path), stdout = TRUE), collapse = "") else ""
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

# ---- pool panels: one hardware row per capacity.types[] entry. No live data
# exists for this page (capacity, not occupancy) -- every block renders
# saturated. Node clusters are built purely from count x per_node; tooltips
# carry only what the JSON actually has (Server, RAM-per-node or VRAM-per-GPU)
# -- no hostnames, no install dates. Adaptation of gpu-cds-scc build_gpu_portal.R
# livePanel() / cpu-cds-scc build_cpu_portal.R renderLive(): same hwtop/hwcols/
# hwrow/cnode idiom, held-related bits dropped since there is no live feed. ----
panel_row <- function(label, server, count, per_node, ram, pool) {
  disp <- if (pool == "cpu") model_label(label) else label
  unit <- if (pool == "cpu") paste0(fmt(per_node), " cores") else paste0(fmt(ram), " GB")
  row_tip <- paste0("<b>", esc_h(disp), "</b><br>Server: ", esc_h(server),
                     if (pool == "cpu") paste0("<br>RAM: ", fmt(ram), " GB per node")
                     else paste0("<br>VRAM: ", fmt(ram), " GB per GPU"))
  cluster_tip <- if (pool == "cpu") paste0(fmt(per_node), " cores")
                 else paste0(fmt(per_node), " GPUs · ", fmt(ram), " GB each")
  square <- '<i class="on"></i>'
  one_cluster <- sprintf('<span class="cnode" data-tip="%s">%s</span>', esc_a(cluster_tip), paste(rep(square, per_node), collapse = ""))
  clusters <- paste(rep(one_cluster, count), collapse = "")
  sprintf('<div class="hwrow"><span class="hwlbl" data-tip="%s">%s</span><span class="hwc">%s</span><span class="hwnodes">%s</span></div>',
          esc_a(row_tip), esc_h(disp), unit, clusters)
}

panel_html <- function(types, pool) {
  rows <- vapply(seq_len(nrow(types)), function(i) {
    panel_row(types[i, 1], types[i, 2], as.integer(types[i, 3]), as.integer(types[i, 4]), as.numeric(types[i, 5]), pool)
  }, character(1))
  head_lbl <- if (pool == "cpu") "CPU" else "GPU"
  unit_lbl <- if (pool == "cpu") "Cores" else "VRAM"
  cols <- sprintf('<div class="hwcols"><span class="hwlbl">%s</span><span class="hwc">%s</span><span class="hwnodes">Nodes</span></div>', head_lbl, unit_lbl)
  paste0(cols, paste(rows, collapse = "\n"))
}

gpu_panel <- panel_html(d$capacity$gpu$types, "gpu")
cpu_panel <- panel_html(d$capacity$cpu$types, "cpu")

# ---- KPI totals: sum the monthly tables over a window (a set of "YYYY-MM"
# strings). Server-rendered here for the default trailing-3-month window
# (meta.window3) so the page means something before/without JS; the page's
# own inline JS repeats this arithmetic verbatim to recompute on a period
# change. Tile labels/tips lifted verbatim from the portals' own kpi() helper
# and TIPS object (CPU: build_cpu_portal.R ~L465-484,575; GPU:
# build_gpu_portal.R ~L544-570,659). ----
as_mat <- function(x, ncol) if (is.null(dim(x))) matrix(x, ncol = ncol, byrow = TRUE) else x
cm <- as_mat(d$cpu_monthly, 9)   # month,node_class,held_h,utilized_h,fail_h,wkill_h,njobs,wa_used_h,wa_req_h
gm <- as_mat(d$gpu_monthly, 10)  # month,card,held_h,real_h,residle_h,kwh,vram_h,fail_h,wkill_h,njobs

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
  held = "Core-hours reserved by jobs: cores held × hours run, busy or not. The denominator of everything.",
  utilized = "CPU time the jobs actually consumed (the accounting cpu field), capped per job at <b>Held</b>. Higher is better.",
  under = "<b>Held</b> core-hours the jobs left unused: <b>Held</b> − <b>Utilized</b>. Lower is better; some is unavoidable.",
  eff = "CPU time used over CPU time reserved.",
  wallacc = "Requested walltime actually used, over jobs with an <b>explicit</b> h_rt only — not the injected 12h default; coverage shown as n. Σused ÷ Σrequested; an explicit 12h request is indistinguishable from the default.",
  fail = "How much <b>Held</b> time went to jobs that broke? Hard failures only. Lower is better.",
  wkill = "How much <b>Held</b> time went to jobs SGE killed at their own h_rt. Not good or bad on its own — on the 12h scavenger queues it often just means hitting the scavenger ceiling."
)
GPU_TIPS <- list(
  held = "Total GPU hours held/reserved by jobs.",
  busy = "How hard did the GPU(s) work? <b>Utilized</b> over <b>Held</b>, split into the three tiers. Higher is better.",
  idle = "How much held time had a process but idle kernels? <b>Held</b> − <b>Utilized</b> − <b>Non-Utilized</b>. Lower is better; some is unavoidable.",
  residle = "Was the GPU held with no process at all? Each no-process sample counts its full 5 minutes. The worst waste. Lower is better.",
  kwh = "Energy from sampled GPU power.",
  fail = "How much <b>Held</b> time went to jobs that broke? Hard failures only. Lower is better.",
  wkill = "How much <b>Held</b> time went to jobs that hit their h_rt wall. Not good or bad on its own.",
  vram = "Mean VRAM in use, as a share of capacity."
)

kpi_tile <- function(n, l, t = "") sprintf('<div class="k"%s><div class="kl">%s</div><div class="kn">%s</div></div>',
                                            if (nzchar(t)) sprintf(' data-tip="%s"', t) else "", l, n)

cpu_kpi_html <- function(T) {
  paste0(
    kpi_tile(fmth(T$held), "Held core-h", CPU_TIPS$held),
    kpi_tile(pct(T$utilized, T$held), "Avg Efficiency %", CPU_TIPS$eff),
    kpi_tile(fmth(max(0, T$held - T$utilized)), "Under-utilized core-h", CPU_TIPS$under),
    kpi_tile(fmth(T$utilized), "Utilized core-h", CPU_TIPS$utilized),
    kpi_tile(fmt(T$njobs), "Jobs #"),
    kpi_tile(if (T$wa_req_h > 0) paste0(jround(100 * T$wa_used_h / T$wa_req_h), "%") else "—", "Walltime Accuracy %", CPU_TIPS$wallacc),
    kpi_tile(pct(T$fail_h, T$held), "on hard-failed jobs", CPU_TIPS$fail),
    kpi_tile(pct(T$wkill_h, T$held), "on wall-killed jobs", CPU_TIPS$wkill)
  )
}
gpu_kpi_html <- function(T) {
  paste0(
    kpi_tile(fmth(T$held), "Held GPU-h", GPU_TIPS$held),
    kpi_tile(pct(T$real, T$held), "Avg Utilization", GPU_TIPS$busy),
    kpi_tile(fmth(max(0, T$held - T$real - T$residle_h)), "Under-Utilized GPU-h", GPU_TIPS$idle),
    kpi_tile(fmth(T$residle_h), "Non-Utilized GPU-h", GPU_TIPS$residle),
    kpi_tile(fmth(T$kwh), "Energy kWh", GPU_TIPS$kwh),
    kpi_tile(pct(T$fail_h, T$held), "on hard-failed jobs", GPU_TIPS$fail),
    kpi_tile(pct(T$wkill_h, T$held), "on wall-killed jobs", GPU_TIPS$wkill),
    kpi_tile(pct(T$vram_h, T$held), "Mean VRAM", GPU_TIPS$vram)
  )
}

window3 <- d$meta$window3
default_cpu_kpi <- cpu_kpi_html(sum_cpu_window(window3))
default_gpu_kpi <- gpu_kpi_html(sum_gpu_window(window3))
default_range <- range_text(window3)

# ---- period controls: a segmented [Past 3 | Past 6 | All] bar (default:
# Past 3 months, "on") plus a compact month-only <select> for single-month
# views (neutral "Month…" placeholder, month grain, every published month
# across CPU+GPU union). ----
all_months <- sort(unique(c(d$meta$months_cpu, d$meta$months_gpu)))
month_opts <- paste(vapply(rev(all_months), function(m) sprintf('<option value="%s">%s</option>', m, month_label(m)), character(1)), collapse = "")
month_select_options <- paste0('<option value="" selected>Month…</option>', month_opts)

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
.deckrow{display:flex;gap:16px;align-items:stretch;margin-bottom:12px;}.deckrow .deck{flex:1 1 auto;margin-bottom:0;min-width:0;}
#gpupanel,#gpucard{flex:0 1 40%;}#cpupanel,#cpucard{flex:1 1 0;}
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
.pool-cpu{--lblw:130px;--valw:64px;--core-s:clamp(5px,0.35vw,12px);}.pool-cpu .cnode{display:grid;grid-template-columns:repeat(8,var(--core-s));gap:3px;padding:5px;border:1px solid var(--border);border-radius:6px;background:var(--surface2);}.pool-cpu .cnode i{width:var(--core-s);height:var(--core-s);border-radius:3px;display:block;background:var(--idle);}.pool-cpu .cnode i.on{background:var(--used);}
.pool-gpu{--lblw:80px;--valw:56px;--gpu-w:clamp(13px,0.93vw,40px);--gpu-h:clamp(10px,0.47vw,20px);}.pool-gpu .cnode{display:inline-flex;gap:3px;padding:5px;border:1px solid var(--border);border-radius:6px;background:var(--surface2);}.pool-gpu .cnode i{width:var(--gpu-w);height:var(--gpu-h);border-radius:4px;display:block;background:var(--idle);}.pool-gpu .cnode i.on{background:var(--used);}
@media(min-width:1700px){.pool-cpu{--core-s:clamp(8px,0.5vw,12px);}.pool-gpu{--gpu-w:clamp(22px,1.4vw,40px);--gpu-h:clamp(11px,0.7vw,20px);}.deck{padding:13px 14px;}.kpi .kn{font-size:1.3rem;}}
[data-tip]{cursor:help;}
#tip{position:fixed;z-index:99;max-width:300px;background:#0f1f3a;color:#eaf1fb;font-size:0.719rem;line-height:1.45;padding:7px 10px;border-radius:6px;box-shadow:0 6px 22px rgba(0,0,0,.28);pointer-events:none;display:none;}#tip b{color:#9ec5ff;font-weight:600;}
.kpi{display:grid;grid-template-columns:repeat(2,1fr);gap:14px 18px;margin:0;}.kpi .k{padding:0;}
.kpi .kn{font-size:1.188rem;font-weight:bold;color:var(--ink);font-variant-numeric:tabular-nums;letter-spacing:-.01em;line-height:1.15;}.kpi .kl{font-size:0.688rem;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.04em;margin-bottom:2px;white-space:nowrap;}.kpi .k[data-tip]{cursor:help;}
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
</style></head><body>
<header><div class="hwrap"><h1><img class="buplate" src=")-----",
plate_uri,
r"-----(" alt="Boston University"><span class="orgname">Faculty of Computing &amp; Data Sciences</span><span class="hsep">|</span>Research Computing at CDS</h1></div></header>
<main>
<div class="livewrap"><span class="liveupd"><a href="https://rcs.bu.edu" target="_blank" rel="noopener">Data from BU SCC</a> · updated quarterly · )-----",
d$meta$updated,
r"-----(</span></div>
<div class="deckrow">
<div class="deck pool-gpu" id="gpupanel"><h3>GPU Pool</h3>)-----",
gpu_panel,
r"-----(</div>
<div class="deck pool-cpu" id="cpupanel"><h3>CPU Pool</h3>)-----",
cpu_panel,
r"-----(</div>
</div>
<div class="sechead" id="sechead">
<div class="ttl">Totals<span id="prange">)-----",
default_range,
r"-----(</span></div>
<div class="ctl">
<span class="seg"><button id="seg-p3" class="on" data-w="past3">Past 3 months</button><button id="seg-p6" data-w="past6">Past 6 months</button><button id="seg-all" data-w="all">All months</button></span>
<select id="pmonth">)-----",
month_select_options,
r"-----(</select>
</div>
</div>
<div class="deckrow">
<div class="deck" id="gpucard"><h3>GPU Totals</h3><div class="kpi" id="kpi-gpu">)-----",
default_gpu_kpi,
r"-----(</div></div>
<div class="deck" id="cpucard"><h3>CPU Totals</h3><div class="kpi" id="kpi-cpu">)-----",
default_cpu_kpi,
r"-----(</div></div>
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
function fmt(x){return Math.round(x).toLocaleString();}
function fmth(x){if(x==null)return '—';if(x<=0)return '0';if(x<1)return '&lt;1';return Math.round(x).toLocaleString();}
const kpi=(n,l,t)=>'<div class=k'+(t?' data-tip="'+t+'"':'')+'><div class=kl>'+l+'</div><div class=kn>'+n+'</div></div>';
const CPU_TIPS={
 held:'Core-hours reserved by jobs: cores held × hours run, busy or not. The denominator of everything.',
 utilized:'CPU time the jobs actually consumed (the accounting cpu field), capped per job at <b>Held</b>. Higher is better.',
 under:'<b>Held</b> core-hours the jobs left unused: <b>Held</b> − <b>Utilized</b>. Lower is better; some is unavoidable.',
 eff:'CPU time used over CPU time reserved.',
 wallacc:'Requested walltime actually used, over jobs with an <b>explicit</b> h_rt only — not the injected 12h default; coverage shown as n. Σused ÷ Σrequested; an explicit 12h request is indistinguishable from the default.',
 fail:'How much <b>Held</b> time went to jobs that broke? Hard failures only. Lower is better.',
 wkill:'How much <b>Held</b> time went to jobs SGE killed at their own h_rt. Not good or bad on its own — on the 12h scavenger queues it often just means hitting the scavenger ceiling.'
};
const GPU_TIPS={
 held:'Total GPU hours held/reserved by jobs.',
 busy:'How hard did the GPU(s) work? <b>Utilized</b> over <b>Held</b>, split into the three tiers. Higher is better.',
 idle:'How much held time had a process but idle kernels? <b>Held</b> − <b>Utilized</b> − <b>Non-Utilized</b>. Lower is better; some is unavoidable.',
 residle:'Was the GPU held with no process at all? Each no-process sample counts its full 5 minutes. The worst waste. Lower is better.',
 kwh:'Energy from sampled GPU power.',
 fail:'How much <b>Held</b> time went to jobs that broke? Hard failures only. Lower is better.',
 wkill:'How much <b>Held</b> time went to jobs that hit their h_rt wall. Not good or bad on its own.',
 vram:'Mean VRAM in use, as a share of capacity.'
};
const ALLM=[...new Set([...DATA.meta.months_cpu,...DATA.meta.months_gpu])].sort();
function windowFor(v){
  if(v==='past3')return DATA.meta.window3.slice();
  if(v==='past6')return ALLM.slice(-6);
  if(v==='all')return ALLM.slice();
  return [v];
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
function cpuKpiHtml(T){
  return kpi(fmth(T.held),'Held core-h',CPU_TIPS.held)
    +kpi((T.held?Math.round(100*T.utilized/T.held):0)+'%','Avg Efficiency %',CPU_TIPS.eff)
    +kpi(fmth(Math.max(0,T.held-T.utilized)),'Under-utilized core-h',CPU_TIPS.under)
    +kpi(fmth(T.utilized),'Utilized core-h',CPU_TIPS.utilized)
    +kpi(fmt(T.njobs),'Jobs #','')
    +kpi(T.wa_req_h>0?Math.round(100*T.wa_used_h/T.wa_req_h)+'%':'—','Walltime Accuracy %',CPU_TIPS.wallacc)
    +kpi((T.held?Math.round(100*T.fail_h/T.held):0)+'%','on hard-failed jobs',CPU_TIPS.fail)
    +kpi((T.held?Math.round(100*T.wkill_h/T.held):0)+'%','on wall-killed jobs',CPU_TIPS.wkill);
}
function gpuKpiHtml(T){
  return kpi(fmth(T.held),'Held GPU-h',GPU_TIPS.held)
    +kpi((T.held?Math.round(100*T.real/T.held):0)+'%','Avg Utilization',GPU_TIPS.busy)
    +kpi(fmth(Math.max(0,T.held-T.real-T.residle_h)),'Under-Utilized GPU-h',GPU_TIPS.idle)
    +kpi(fmth(T.residle_h),'Non-Utilized GPU-h',GPU_TIPS.residle)
    +kpi(fmth(T.kwh),'Energy kWh',GPU_TIPS.kwh)
    +kpi((T.held?Math.round(100*T.fail_h/T.held):0)+'%','on hard-failed jobs',GPU_TIPS.fail)
    +kpi((T.held?Math.round(100*T.wkill_h/T.held):0)+'%','on wall-killed jobs',GPU_TIPS.wkill)
    +kpi((T.held?Math.round(100*T.vram_h/T.held):0)+'%','Mean VRAM',GPU_TIPS.vram);
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
function applyWindow(months){
  $('#kpi-cpu').innerHTML=cpuKpiHtml(sumCpu(months));
  $('#kpi-gpu').innerHTML=gpuKpiHtml(sumGpu(months));
  $('#prange').textContent=rangeText(months);
}
const SEGS=[['#seg-p3','past3'],['#seg-p6','past6'],['#seg-all','all']];
SEGS.forEach(([sel])=>{
  const b=$(sel);
  b.addEventListener('click',()=>{
    SEGS.forEach(([s])=>$(s).classList.remove('on'));
    b.classList.add('on');
    $('#pmonth').value='';
    applyWindow(windowFor(b.dataset.w));
  });
});
$('#pmonth').addEventListener('change',()=>{
  const v=$('#pmonth').value;
  if(!v)return;
  SEGS.forEach(([s])=>$(s).classList.remove('on'));
  applyWindow(windowFor(v));
});
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
