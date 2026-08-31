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
GPU_MAX_AGE_D <- 35    # GPU emit refreshes ~monthly

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
window6 <- tail(intersect(months_cpu, months_gpu), 6)   # trailing months common to both, for the headline

tomat  <- function(m, cols) { x <- as.data.table(m); setnames(x, cols); x }
numify <- function(x, cc) { for (col in cc) x[, (col) := as.numeric(get(col))]; x }
# Row-wise list, not as.matrix(): a data.table mixing character and numeric columns
# would have as.matrix() coerce every column to character (and pad-quote the numbers),
# so held_h/njobs/count/per_node/per_node_ram_gb must serialize as JSON numbers, not
# strings. Each row becomes an unnamed list; auto_unbox turns its length-1 elements
# into bare scalars, so toJSON renders one mixed-type JSON array per row.
to_rows <- function(dt) unname(lapply(seq_len(nrow(dt)), function(i) unname(as.list(dt[i]))))

Fc <- numify(tomat(cpu$F, cpu$Fcols), c("held", "njobs"))[pt == "M" & p %chin% months_cpu]
Fg <- numify(tomat(gpu$F, gpu$Fcols), c("held", "njobs"))[pt == "M" & p %chin% months_gpu]

cpu_m <- Fc[, .(held_h = round(sum(held), 2), njobs = sum(njobs)), by = .(p, node_class)]
setorder(cpu_m, p, node_class)
gpu_m <- Fg[, .(held_h = round(sum(held), 2), njobs = sum(njobs)), by = .(p, card)]
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
  cpu_core_h = round(Fc[p %chin% window6, sum(held)], 2),
  gpu_h      = round(Fg[p %chin% window6, sum(held)], 2),
  jobs       = Fc[p %chin% window6, sum(njobs)] + Fg[p %chin% window6, sum(njobs)]
)

meta <- list(updated = format(Sys.Date(), "%Y-%m-%d"), public = TRUE,
             months_cpu = I(months_cpu), months_gpu = I(months_gpu), window6 = I(window6))

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
