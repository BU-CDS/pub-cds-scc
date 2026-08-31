# =====================================================================
# build_cluster_page.R — the public showcase: a self-contained, zero-
# JavaScript index.html assembled entirely by R string concatenation from
# output/cluster_data.json. Light theme only -- this is the single
# presentation of the page (no toggle, no OS-theme detection, no
# localStorage, no <script> anywhere). Tooltips are title="" attributes.
#
# Reads:  output/cluster_data.json          (Task 1's strip+combine emit)
# Assets (base64-embedded, read from the sibling clone, never copied in):
#   $PUB_CPU_CLONE/assets/bu_plate_white.png
#   $PUB_CPU_CLONE/assets/faculty_compt_data_sci_signature_toptier_rgb.png
#   $PUB_CPU_CLONE/assets/WhitneySSmAdvancedSemibold.woff2   (weight 600)
#   $PUB_CPU_CLONE/assets/WhitneySSmAdvancedBook.woff2       (weight 400)
# Writes: index.html (repo root, gitignored)
# Run: module load R/4.5.2 && Rscript build_cluster_page.R
# =====================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

.f   <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
ROOT <- if (length(.f)) normalizePath(dirname(.f[[1]])) else normalizePath(".")

PUB_CPU_CLONE <- Sys.getenv("PUB_CPU_CLONE", "/usr3/bustaff/mhorn/repos/cpu-cds-scc")

dataf <- file.path(ROOT, "output", "cluster_data.json")
stopifnot(file.exists(dataf))
d <- fromJSON(dataf, simplifyVector = TRUE)

b64 <- function(path) if (file.exists(path)) paste(system2("base64", c("-w0", path), stdout = TRUE), collapse = "") else ""
plate_uri     <- paste0("data:image/png;base64,", b64(file.path(PUB_CPU_CLONE, "assets", "bu_plate_white.png")))
emblem_uri    <- paste0("data:image/png;base64,", b64(file.path(PUB_CPU_CLONE, "assets", "faculty_compt_data_sci_signature_toptier_rgb.png")))
font_uri      <- paste0("data:font/woff2;base64,", b64(file.path(PUB_CPU_CLONE, "assets", "WhitneySSmAdvancedSemibold.woff2")))
font_uri_book <- paste0("data:font/woff2;base64,", b64(file.path(PUB_CPU_CLONE, "assets", "WhitneySSmAdvancedBook.woff2")))

# ---- helpers ------------------------------------------------------------
fmt <- function(x) format(round(as.numeric(x)), big.mark = ",", trim = TRUE, scientific = FALSE)

# Human-readable CPU model labels (GPU cards render as-is -- they're already
# short vendor names like L40S/H200). Regex per the task brief: a
# Gold-/Silver-/Platinum-/Bronze- prefix loses its hyphen for a space; an
# EPYC- prefix becomes "AMD EPYC "; a trailing digit-v-digit ("2660v3") gets
# a space before the v; then "Xeon " is prepended when the (possibly
# already-transformed) label opens with E<digit>/Gold/Silver/Platinum/
# Bronze/W, or is a bare 4-digit(+letter) model.
model_label <- function(x) {
  x <- sub("^(Gold|Silver|Platinum|Bronze)-", "\\1 ", x)
  x <- sub("^EPYC-", "AMD EPYC ", x)
  x <- sub("(\\d)v(\\d)$", "\\1 v\\2", x)
  xeon <- grepl("^(E\\d|Gold|Silver|Platinum|Bronze|W)", x) | grepl("^\\d{4}[A-Za-z]?$", x)
  ifelse(xeon, paste0("Xeon ", x), x)
}

MON <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
month_label <- function(m) paste0(MON[as.integer(substr(m, 6, 7))], " ", substr(m, 1, 4))
is_sparse <- function(months) grepl("-01$", months) | seq_along(months) == 1L   # January ticks + the series' first month

# ---- capacity cards: one per types[] row, plus a row of node-count squares --
# per_node_ram_gb means per-NODE total RAM for the CPU pool (count*ram
# reconciles against capacity.cpu.ram_gb) but per-GPU VRAM for the GPU pool
# (only count*per_node*ram reconciles against capacity.gpu.vram_gb). The CPU
# card's "N cores, M GB" shape genuinely means M GB per node, so the identical
# shape on a GPU card would train the reader to misread M GB as a node total
# -- the GPU card spells out "each" so the number can only read as per-GPU.
hw_cards <- function(types, unit) {
  rows <- vapply(seq_len(nrow(types)), function(i) {
    label <- types[i, 1]; server <- types[i, 2]
    count <- as.numeric(types[i, 3]); per_node <- as.numeric(types[i, 4]); ram <- as.numeric(types[i, 5])
    disp <- if (unit == "cores") model_label(label) else label
    sq <- paste(rep(sprintf('<span class="sq" title="%s"></span>', server), count), collapse = "")
    inner <- if (unit == "cores")
      sprintf('%s %s, %s GB', fmt(per_node), unit, fmt(ram))
    else
      sprintf('%s %s · %s GB each', fmt(per_node), unit, fmt(ram))
    sprintf('<div class="hwcard"><div class="hwlabel">%s — %s × (%s)</div><div class="hwsq">%s</div></div>',
            disp, fmt(count), inner, sq)
  }, character(1))
  paste(rows, collapse = "\n")
}

# ---- monthly bars: totals summed across node-class/card, one bar per month --
bars_for <- function(monthly, months, measure_word) {
  m <- data.table(month = monthly[, 1], held = as.numeric(monthly[, 3]), njobs = as.numeric(monthly[, 4]))
  agg <- m[, .(held = sum(held), njobs = sum(njobs)), by = month]
  agg <- agg[match(months, agg$month)]
  mx <- max(agg$held)
  bars <- vapply(seq_len(nrow(agg)), function(i) {
    pct <- if (mx > 0) as.integer(round(agg$held[i] / mx * 100)) else 0L
    sprintf('<div class=bar style="height:%d%%" title="%s · %s %s · %s jobs"></div>',
            pct, agg$month[i], fmt(agg$held[i]), measure_word, fmt(agg$njobs[i]))
  }, character(1))
  sp <- is_sparse(months)
  labs <- vapply(seq_along(months), function(i)
    if (sp[i]) sprintf('<div class="bl">%s</div>', month_label(months[i])) else '<div class="bl"></div>',
    character(1))
  list(bars = paste(bars, collapse = ""), labs = paste(labs, collapse = ""))
}

cpu_series <- bars_for(d$cpu_monthly, d$meta$months_cpu, "core-hours")
gpu_series <- bars_for(d$gpu_monthly, d$meta$months_gpu, "GPU-hours")

# ---- assemble -------------------------------------------------------------
html <- paste0('<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Research Computing at CDS</title>
<style>
:root{
 --t-sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
 --t-mono:ui-monospace,"SF Mono",SFMono-Regular,Menlo,Consolas,"Liberation Mono",monospace;
 --content-max:2100px;--content-pad:20px;
 --bg:#f2efec;--surface:#ffffff;--surface2:#ebe6e0;
 --ink:#2d2926;--text:#2d2926;--muted:#6b6158;--grid:#e8e3dd;--border:#dcd5cd;
 --used:#0b7468;--idle:#c0cad4;--ember:#b4451f;--headbg:#2d2926;--headfg:#ffffff;--shadow:rgba(15,30,45,.10);--hatch:rgba(20,30,42,.34);--busy:#dc2626;--free:#2563eb;--rule:#b7ada2;--hl:#fde68a;--amber:#e0a63e;--rust:#a0522d;
}
@font-face{font-family:"Whitney SSm A";font-weight:600;font-style:normal;font-display:swap;src:url("', font_uri, '") format("woff2");}
@font-face{font-family:"Whitney SSm A";font-weight:400;font-style:normal;font-display:swap;src:url("', font_uri_book, '") format("woff2");}
*{box-sizing:border-box}html{font-size:110%;}body{font-family:var(--t-sans);color:var(--text);margin:0;background:var(--bg);font-size:0.813rem;line-height:1.45;-webkit-font-smoothing:antialiased;}
header{background:var(--headbg);color:var(--headfg);padding:12px var(--content-pad);position:relative;border-top:3px solid #cc0000;border-bottom:1px solid rgba(255,255,255,.08);}header h1{font-size:1rem;margin:0;font-weight:600;letter-spacing:-.01em;font-family:"Whitney SSm A",var(--t-sans);}.buplate{height:1.615em;vertical-align:-.449em;margin-right:.34em;}.orgname{font-weight:400;letter-spacing:0;}.hsep{color:rgba(255,255,255,.4);font-weight:400;padding:0 .6em;}
.hwrap{max-width:min(var(--content-max),96vw);margin:0 auto;display:flex;align-items:baseline;gap:14px;flex-wrap:wrap;}
main{max-width:min(var(--content-max),96vw);margin:0 auto;padding:14px var(--content-pad) 60px;}
h2{font-size:0.95rem;font-weight:600;color:var(--ink);margin:22px 0 10px;}
h3{font-size:0.85rem;font-weight:600;color:var(--ink);margin:0 0 10px;}
.headline{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:16px 18px;margin-bottom:6px;box-shadow:0 1px 3px var(--shadow);}
.hl-row{display:flex;flex-wrap:wrap;align-items:baseline;gap:2px 10px;margin:6px 0;}
.hl-row + .hl-row{border-top:1px solid var(--grid);padding-top:10px;}
.hl-num{font-size:1.5rem;font-weight:700;color:var(--ink);font-variant-numeric:tabular-nums;}
.hl-lbl{font-size:0.75rem;color:var(--muted);text-transform:uppercase;letter-spacing:.04em;margin-right:16px;}
.hwcard{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:11px 13px;margin-bottom:10px;box-shadow:0 1px 3px var(--shadow);}
.hwlabel{font-size:0.813rem;color:var(--ink);font-weight:600;margin-bottom:8px;}
.hwsq{display:flex;flex-wrap:wrap;gap:5px;}
.sq{width:15px;height:15px;border:1px solid var(--border);border-radius:3px;background:var(--surface2);display:inline-block;}
.chart{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:14px 16px;margin-bottom:14px;box-shadow:0 1px 3px var(--shadow);}
.bars{display:flex;align-items:flex-end;gap:3px;height:150px;}
.bar{flex:1 1 0;min-width:2px;min-height:2px;background:var(--used);border-radius:2px 2px 0 0;}
.barlabels{display:flex;gap:3px;margin-top:5px;}
.bl{flex:1 1 0;text-align:center;font-size:0.656rem;color:var(--muted);white-space:nowrap;overflow:hidden;}
.chartcap{font-size:0.75rem;color:var(--muted);margin-top:10px;}
.pagefoot{max-width:min(var(--content-max),96vw);margin:20px auto 0;padding:18px var(--content-pad) 30px;border-top:1px solid var(--border);display:flex;align-items:center;gap:14px;flex-wrap:wrap;}
.ft-emblem{height:30px;width:auto;display:block;}
.ft-text{color:var(--muted);font-size:0.75rem;}
</style></head><body>
<header><div class="hwrap"><h1><img class="buplate" src="', plate_uri, '" alt="Boston University"><span class="orgname">Faculty of Computing &amp; Data Sciences</span><span class="hsep">|</span>Research Computing at CDS</h1></div></header>
<main>
<div class="headline">
<div class="hl-row"><span class="hl-num">', fmt(d$capacity$cpu$cores), '</span><span class="hl-lbl">cores</span><span class="hl-num">', fmt(d$capacity$gpu$gpus), '</span><span class="hl-lbl">GPUs</span></div>
<div class="hl-row"><span class="hl-num">', fmt(d$headline$cpu_core_h), '</span><span class="hl-lbl">core-hours</span><span class="hl-num">', fmt(d$headline$gpu_h), '</span><span class="hl-lbl">GPU-hours</span><span class="hl-num">', fmt(d$headline$jobs), '</span><span class="hl-lbl">jobs</span></div>
</div>
<section class="hw hw-cpu">
<h2>CPU Nodes</h2>
', hw_cards(d$capacity$cpu$types, "cores"), '
</section>
<section class="hw hw-gpu">
<h2>GPU Nodes</h2>
', hw_cards(d$capacity$gpu$types, "GPUs"), '
</section>
<section class="delivered">
<h2>Delivered</h2>
<div class="chart chart-cpu">
<h3>CPU Core-Hours</h3>
<div class="bars">', cpu_series$bars, '</div>
<div class="barlabels">', cpu_series$labs, '</div>
<div class="chartcap">core-hours allocated to jobs</div>
</div>
<div class="chart chart-gpu">
<h3>GPU Hours</h3>
<div class="bars">', gpu_series$bars, '</div>
<div class="barlabels">', gpu_series$labs, '</div>
<div class="chartcap">GPU-hours allocated to jobs</div>
</div>
</section>
</main>
<footer class="pagefoot"><img class="ft-emblem" src="', emblem_uri, '" alt="Boston University Faculty of Computing &amp; Data Sciences"><span class="ft-text">Data from SGE accounting and gpustats · updated monthly · ', d$meta$updated, '</span></footer>
</body></html>
')

writeLines(html, file.path(ROOT, "index.html"))
cat(sprintf("build_cluster_page: wrote index.html (%d bytes)\n", nchar(html)))
