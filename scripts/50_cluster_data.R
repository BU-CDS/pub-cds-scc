# =====================================================================
# 50_cluster_data.R — strip + combine the CPU and GPU sibling emits into
# the one public fact table this page's charts read.
#
# Reads (read-only, env-overridable):
#   $PUB_CPU_CLONE/output/portal_data.json        (raw CPU strip+aggregate emit)
#   $PUB_GPU_CLONE/output/public_data.json        (already-public GPU emit)
#   $PUB_CPU_CLONE/config/cds_cpu_inventory.csv
#   $PUB_GPU_CLONE/config/gpu_inventory_history.csv
# Writes: output/cluster_data.json
#
# proj/user/queue/host never reach the output: CPU F is aggregated away to
# (month, node_class), GPU F to (month, card); hardware inventory is read
# for capacity counts only (host is never emitted, just counted). Refuses
# identified or stale input outright — this is the only place either
# sibling clone's data touches a public artifact.
# Run: module load R/4.5.2 && Rscript scripts/50_cluster_data.R   (~1 s)
# =====================================================================
.f    <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
ROOT  <- if (length(.f)) normalizePath(file.path(dirname(.f[[1]]), "..")) else normalizePath("..")
OUTPUT_DIR <- file.path(ROOT, "output")
dir.create(OUTPUT_DIR, showWarnings = FALSE)

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

PUB_CPU_CLONE <- Sys.getenv("PUB_CPU_CLONE", "/usr3/bustaff/mhorn/repos/cpu-cds-scc")
PUB_GPU_CLONE <- Sys.getenv("PUB_GPU_CLONE", "/usr3/bustaff/mhorn/repos/gpu-cds-scc")

CPU_MAX_AGE_H <- 48    # CPU emit refreshes ~daily
GPU_MAX_AGE_D <- 100   # GPU emit refreshes ~quarterly

cpu_inf <- file.path(PUB_CPU_CLONE, "output", "portal_data.json")
gpu_inf <- file.path(PUB_GPU_CLONE, "output", "public_data.json")
stopifnot(file.exists(cpu_inf), file.exists(gpu_inf))

cpu <- fromJSON(cpu_inf, simplifyMatrix = TRUE)
gpu <- fromJSON(gpu_inf, simplifyMatrix = TRUE)

if (isTRUE(cpu$meta$identified) || !isTRUE(cpu$meta$deid))
  stop("50_cluster_data: CPU portal_data.json is identified or unmarked; refusing to build cluster_data")
if (isTRUE(gpu$meta$identified) || !isTRUE(gpu$meta$public))
  stop("50_cluster_data: GPU public_data.json is identified or not public; refusing to build cluster_data")

now <- as.numeric(Sys.time())
cpu_age_h <- (now - cpu$meta$generated_epoch) / 3600
if (cpu_age_h > CPU_MAX_AGE_H)
  stop(sprintf("50_cluster_data: CPU input stale (%.1f h > %d h limit)", cpu_age_h, CPU_MAX_AGE_H))
gpu_age_d <- (now - gpu$meta$generated_epoch) / 86400
if (gpu_age_d > GPU_MAX_AGE_D)
  stop(sprintf("50_cluster_data: GPU input stale (%.1f d > %d d limit)", gpu_age_d, GPU_MAX_AGE_D))

cur <- format(Sys.Date(), "%Y-%m")
months_cpu <- setdiff(cpu$periods$M, cur)   # complete months only: the in-progress month never publishes
months_gpu <- setdiff(gpu$periods$M, cur)
stopifnot(length(months_cpu) >= 1, length(months_gpu) >= 1)
window3 <- tail(sort(intersect(months_cpu, months_gpu)), 3)   # trailing (<=3) months common to both, for the headline

# C1 guard: window3 must end at the calendar month just closed (America/New_York),
# not merely "whatever the two emits happen to agree on". Without this, an input
# that stops advancing on one side (e.g. a dropped producer cron) silently ages
# the published "Past 3 months" by a month every run until a freshness ceiling
# finally trips -- loud only after the damage is already done. Fail closed instead.
cur_et <- format(as.POSIXct(Sys.time(), tz = "America/New_York"), "%Y-%m")
expected_month <- format(seq(as.Date(paste0(cur_et, "-01")), by = "-1 month", length.out = 2)[2], "%Y-%m")
last_common <- if (length(window3)) tail(window3, 1) else "(none)"
if (last_common != expected_month)
  stop(sprintf("50_cluster_data: window3 lag -- last common complete month is %s, expected %s (the month just closed)",
               last_common, expected_month))

# contract v2 metric columns, read from the sibling emits' own F columns by name.
# Fail closed if the emit doesn't have one: better a broken build than silently
# zero-filling (or garbage-filling) a published metric.
CPU_METRICS <- c("held", "utilized", "fail_h", "wkill_h", "njobs", "wa_used_h", "wa_req_h")
GPU_METRICS <- c("held", "real", "residle_h", "kwh", "vram_h", "fail_h", "wkill_h", "njobs")
require_cols <- function(cols, have, label) {
  missing <- setdiff(cols, have)
  if (length(missing))
    stop(sprintf("50_cluster_data: %s missing required column(s): %s", label, paste(missing, collapse = ", ")))
}
require_cols(CPU_METRICS, cpu$Fcols, "CPU portal_data.json")
require_cols(GPU_METRICS, gpu$Fcols, "GPU public_data.json")

tomat  <- function(m, cols) { x <- as.data.table(m); setnames(x, cols); x }
numify <- function(x, cc) { for (col in cc) x[, (col) := as.numeric(get(col))]; x }
# Row-wise list, not as.matrix(): a data.table mixing character and numeric columns
# would have as.matrix() coerce every column to character (and pad-quote the numbers),
# so held_h/njobs/count/per_node/per_node_ram_gb must serialize as JSON numbers, not
# strings. Each row becomes an unnamed list; auto_unbox turns its length-1 elements
# into bare scalars, so toJSON renders one mixed-type JSON array per row.
to_rows <- function(dt) unname(lapply(seq_len(nrow(dt)), function(i) unname(as.list(dt[i]))))

Fc <- numify(tomat(cpu$F, cpu$Fcols), CPU_METRICS)[pt == "M" & p %chin% months_cpu]
Fg <- numify(tomat(gpu$F, gpu$Fcols), GPU_METRICS)[pt == "M" & p %chin% months_gpu]

# column order fixed to the spec's contract v2 row shape
cpu_m <- Fc[, .(held_h     = round(sum(held), 2),
                utilized_h = round(sum(utilized), 2),
                fail_h     = round(sum(fail_h), 2),
                wkill_h    = round(sum(wkill_h), 2),
                njobs      = sum(njobs),
                wa_used_h  = round(sum(wa_used_h), 2),
                wa_req_h   = round(sum(wa_req_h), 2)),
             by = .(p, node_class)]
setorder(cpu_m, p, node_class)
gpu_m <- Fg[, .(held_h    = round(sum(held), 2),
                real_h    = round(sum(real), 2),
                residle_h = round(sum(residle_h), 2),
                kwh       = round(sum(kwh), 2),
                vram_h    = round(sum(vram_h), 2),
                fail_h    = round(sum(fail_h), 2),
                wkill_h   = round(sum(wkill_h), 2),
                njobs     = sum(njobs)),
             by = .(p, card)]
setorder(gpu_m, p, card)

stopifnot(!any(c("proj", "user", "host", "code", "codename") %in% c(names(cpu_m), names(gpu_m))))   # belt: the strip is structural

# capacity: hardware inventory, config-sourced so a node with zero samples in
# the window still advertises. Retired nodes never count.
cpu_inv <- fread(file.path(PUB_CPU_CLONE, "config", "cds_cpu_inventory.csv"), colClasses = "character")[retired == "" & nzchar(host)]
gpu_inv <- fread(file.path(PUB_GPU_CLONE, "config", "gpu_inventory_history.csv"), colClasses = "character")[retired == "" & nzchar(host)]

cpu_types <- cpu_inv[, .(count = .N), by = .(label = cpu_type, server = server_model,
                                              per_node = as.integer(ncpu), per_node_ram_gb = as.numeric(mem_gb))]
setorder(cpu_types, -per_node_ram_gb)
gpu_types <- gpu_inv[, .(count = .N), by = .(label = gpu_type, server = server_model,
                                              per_node = as.integer(gpus), per_node_ram_gb = as.numeric(gpu_mem_gb))]
setorder(gpu_types, -per_node_ram_gb)

capacity <- list(
  cpu = list(nodes = nrow(cpu_inv),
             cores = sum(as.integer(cpu_inv$ncpu)),
             ram_gb = round(sum(as.numeric(cpu_inv$mem_gb)), 1),
             types = to_rows(cpu_types[, .(label, server, count, per_node, per_node_ram_gb)])),
  gpu = list(nodes = nrow(gpu_inv),
             gpus = sum(as.integer(gpu_inv$gpus)),
             vram_gb = round(sum(as.integer(gpu_inv$gpus) * as.numeric(gpu_inv$gpu_mem_gb)), 1),
             types = to_rows(gpu_types[, .(label, server, count, per_node, per_node_ram_gb)]))
)

headline <- list(
  cpu_core_h = round(Fc[p %chin% window3, sum(held)], 2),
  gpu_h      = round(Fg[p %chin% window3, sum(held)], 2),
  jobs       = Fc[p %chin% window3, sum(njobs)] + Fg[p %chin% window3, sum(njobs)]
)

meta <- list(updated = format(Sys.Date(), "%Y-%m-%d"), public = TRUE,
             months_cpu = I(months_cpu), months_gpu = I(months_gpu), window3 = I(window3))

out <- list(meta = meta, capacity = capacity,
            cpu_monthly = to_rows(cpu_m),
            gpu_monthly = to_rows(gpu_m),
            headline = headline)

.outf <- file.path(OUTPUT_DIR, "cluster_data.json")
writeLines(toJSON(out, auto_unbox = TRUE, digits = NA), paste0(.outf, ".tmp"))
invisible(file.rename(paste0(.outf, ".tmp"), .outf))   # atomic, same as the siblings' 52/57
cat(sprintf("wrote cluster_data.json — cpu_monthly %d rows (%s..%s), gpu_monthly %d rows (%s..%s); headline %.1f cpu core-h / %.1f gpu-h / %d jobs\n",
            nrow(cpu_m), months_cpu[1], months_cpu[length(months_cpu)],
            nrow(gpu_m), months_gpu[1], months_gpu[length(months_gpu)],
            headline$cpu_core_h, headline$gpu_h, headline$jobs))
