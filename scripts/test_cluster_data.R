# =====================================================================
# test_cluster_data.R — fixture-driven tests for 50_cluster_data.R.
#
# Builds fake CPU/GPU sibling clones under tempdir() (JSON + inventory
# CSVs), runs 50_cluster_data.R against them as a subprocess (so its own
# stop()-on-bad-input paths are exercised for real, exit code and all),
# and checks the emitted output/cluster_data.json.
#
# Run: module load R/4.5.2 && Rscript scripts/test_cluster_data.R
# =====================================================================
suppressPackageStartupMessages({
  library(jsonlite)
})

.f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
TEST_DIR <- if (length(.f)) normalizePath(dirname(.f[[1]])) else normalizePath(".")
SCRIPT   <- file.path(TEST_DIR, "50_cluster_data.R")
stopifnot("50_cluster_data.R: script missing" = file.exists(SCRIPT))

pass <- function(msg) cat("PASS:", msg, "\n")

# ---- month labels relative to today, so the test is stable on any run date --
cur_d   <- as.Date(paste0(format(Sys.Date(), "%Y-%m"), "-01"))
prev1_d <- seq(cur_d,   by = "-1 month", length.out = 2)[2]
prev2_d <- seq(prev1_d, by = "-1 month", length.out = 2)[2]
cur     <- format(cur_d,   "%Y-%m")
prev1   <- format(prev1_d, "%Y-%m")
prev2   <- format(prev2_d, "%Y-%m")
months3 <- c(prev2, prev1, cur)

# ---- fixture builders --------------------------------------------------
# Copied verbatim from the real $PUB_CPU_CLONE/output/portal_data.json "Fcols" (2026-08-31).
CPU_FCOLS <- c("pt","p","proj","user","node_class","queue","held","utilized","runtime_h",
               "fail_h","wkill_h","njobs","peakmem_gb","fitn","m1024n","nwait",
               "w0","w1","w2","w3","w4","d0","d1","d2","d3","d4","wa_n","wa_used_h","wa_req_h")

build_cpu_json <- function(rows, months = months3, meta_over = list()) {
  meta <- modifyList(list(generated_epoch = as.numeric(Sys.time()), deid = TRUE, identified = FALSE), meta_over)
  n <- nrow(rows)
  F <- matrix("0", nrow = n, ncol = length(CPU_FCOLS)); colnames(F) <- CPU_FCOLS
  F[, "pt"] <- "M"; F[, "proj"] <- "proj1"; F[, "user"] <- "u-0000"; F[, "queue"] <- "owner"
  F[, "p"] <- rows$p; F[, "node_class"] <- rows$node_class
  F[, "held"] <- as.character(rows$held); F[, "njobs"] <- as.character(rows$njobs)
  list(meta = meta, periods = list(M = I(months), W = character(0), D = character(0)),
       Fcols = CPU_FCOLS, F = unname(F))
}

build_gpu_json <- function(rows, months = months3, meta_over = list()) {
  meta <- modifyList(list(generated_epoch = as.numeric(Sys.time()), public = TRUE,
                           identified = FALSE, deid = TRUE), meta_over)
  cols <- c("pt","p","card","held","njobs")
  n <- nrow(rows)
  F <- matrix("0", nrow = n, ncol = length(cols)); colnames(F) <- cols
  F[, "pt"] <- "M"; F[, "p"] <- rows$p; F[, "card"] <- rows$card
  F[, "held"] <- as.character(rows$held); F[, "njobs"] <- as.character(rows$njobs)
  list(meta = meta, periods = list(M = I(months), W = character(0), D = character(0)),
       Fcols = cols, F = unname(F))
}

# CPU: 2 node classes x 3 months (current month must be dropped)
cpu_rows <- data.frame(
  p          = c(prev2, prev2, prev1, prev1, cur, cur),
  node_class = c("m1024","standard","m1024","standard","m1024","standard"),
  held       = c(50, 100, 60, 110, 999, 999),
  njobs      = c(2, 5, 3, 6, 99, 99),
  stringsAsFactors = FALSE
)
# GPU: 2 cards x 3 months (current month must be dropped)
gpu_rows <- data.frame(
  p     = c(prev2, prev2, prev1, prev1, cur, cur),
  card  = c("H200","L40S","H200","L40S","H200","L40S"),
  held  = c(300, 200, 310, 210, 888, 888),
  njobs = c(20, 10, 21, 11, 88, 88),
  stringsAsFactors = FALSE
)

# CPU inventory: 3 rows, 1 retired
cpu_inv <- data.frame(
  host = c("nodeA","nodeB","nodeC"), server_model = c("ModelX","ModelX","ModelY"),
  cpu_type = c("TypeA","TypeA","TypeB"), ncpu = c(20,20,32), mem_gb = c(100,100,200),
  retired = c("","","2020-01-01"), stringsAsFactors = FALSE
)
# GPU inventory: 3 rows, 1 retired
gpu_inv <- data.frame(
  host = c("g1","g2","g3"), server_model = c("GModelX","GModelX","GModelY"),
  gpu_type = c("L40S","L40S","H200"), gpus = c(4,4,2), gpu_mem_gb = c(40,40,80),
  retired = c("","","2020-01-01"), stringsAsFactors = FALSE
)

# ---- build one fixture root + run 50_cluster_data.R against it --------
make_fixture <- function(cpu_meta_over = list(), gpu_meta_over = list()) {
  fx <- tempfile("cluster_data_fixture_")
  dir.create(file.path(fx, "scripts"), recursive = TRUE)
  file.copy(SCRIPT, file.path(fx, "scripts", "50_cluster_data.R"))
  cpu_dir <- file.path(fx, "cpu-clone"); gpu_dir <- file.path(fx, "gpu-clone")
  dir.create(file.path(cpu_dir, "output"), recursive = TRUE)
  dir.create(file.path(cpu_dir, "config"), recursive = TRUE)
  dir.create(file.path(gpu_dir, "output"), recursive = TRUE)
  dir.create(file.path(gpu_dir, "config"), recursive = TRUE)
  writeLines(toJSON(build_cpu_json(cpu_rows, meta_over = cpu_meta_over), auto_unbox = TRUE),
             file.path(cpu_dir, "output", "portal_data.json"))
  writeLines(toJSON(build_gpu_json(gpu_rows, meta_over = gpu_meta_over), auto_unbox = TRUE),
             file.path(gpu_dir, "output", "public_data.json"))
  write.csv(cpu_inv, file.path(cpu_dir, "config", "cds_cpu_inventory.csv"), row.names = FALSE, quote = FALSE)
  write.csv(gpu_inv, file.path(gpu_dir, "config", "gpu_inventory_history.csv"), row.names = FALSE, quote = FALSE)
  list(fx = fx, cpu_dir = cpu_dir, gpu_dir = gpu_dir, script = file.path(fx, "scripts", "50_cluster_data.R"))
}

run_script <- function(f) {
  old_cpu <- Sys.getenv("PUB_CPU_CLONE", unset = NA); old_gpu <- Sys.getenv("PUB_GPU_CLONE", unset = NA)
  Sys.setenv(PUB_CPU_CLONE = f$cpu_dir, PUB_GPU_CLONE = f$gpu_dir)
  on.exit({
    if (is.na(old_cpu)) Sys.unsetenv("PUB_CPU_CLONE") else Sys.setenv(PUB_CPU_CLONE = old_cpu)
    if (is.na(old_gpu)) Sys.unsetenv("PUB_GPU_CLONE") else Sys.setenv(PUB_GPU_CLONE = old_gpu)
  })
  out <- suppressWarnings(system2("Rscript", shQuote(f$script), stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  list(status = if (is.null(status)) 0L else status, output = paste(out, collapse = "\n"))
}

collect_keys <- function(x) {
  if (!is.list(x)) return(character(0))
  nm <- names(x); if (is.null(nm)) nm <- character(0)
  c(nm, unlist(lapply(x, collect_keys), use.names = FALSE))
}

# =====================================================================
# 1) Happy path: fresh, well-formed fixtures -> succeeds
# =====================================================================
f1 <- make_fixture()
r1 <- run_script(f1)
stopifnot("happy-path run must exit 0" = r1$status == 0)
pass("happy-path run exits 0")

outf <- file.path(f1$fx, "output", "cluster_data.json")
stopifnot("output/cluster_data.json must be written" = file.exists(outf))
out <- fromJSON(outf, simplifyVector = TRUE, simplifyMatrix = TRUE)

# numeric fields must be real JSON numbers, not quoted strings. simplifyVector = FALSE
# preserves each JSON scalar's actual parsed type, so a string like "50" reads back as
# is.character() here even though as.numeric("50") == 50 would hide the same defect in
# every other assertion in this file that goes through the simplified `out` above.
raw <- fromJSON(outf, simplifyVector = FALSE)
row_types_ok <- function(row, n_char) {
  n <- length(row)
  all(vapply(row[seq_len(n_char)], is.character, logical(1))) &&
    all(vapply(row[seq_len(n - n_char) + n_char], is.numeric, logical(1)))
}
stopifnot("cpu_monthly rows must be [char,char,num,num], not all-string" = row_types_ok(raw$cpu_monthly[[1]], 2))
stopifnot("gpu_monthly rows must be [char,char,num,num], not all-string" = row_types_ok(raw$gpu_monthly[[1]], 2))
stopifnot("capacity.cpu.types rows must be [char,char,num,num,num], not all-string" =
  row_types_ok(raw$capacity$cpu$types[[1]], 2))
stopifnot("capacity.gpu.types rows must be [char,char,num,num,num], not all-string" =
  row_types_ok(raw$capacity$gpu$types[[1]], 2))
pass("cpu_monthly/gpu_monthly/capacity.types numeric fields are real JSON numbers, not strings")

# months exclude the current month
stopifnot("cur must not appear in months_cpu" = !(cur %in% out$meta$months_cpu))
stopifnot("cur must not appear in months_gpu" = !(cur %in% out$meta$months_gpu))
pass("current (in-progress) month is excluded from both month lists")

# no forbidden keys anywhere in the output
forbidden <- c("proj","user","host","code","codename")
stopifnot("no key of the output may be proj|user|host|code|codename" = !any(collect_keys(out) %in% forbidden))
pass("no proj|user|host|code|codename key anywhere in the output")

# capacity: retired rows skipped
stopifnot("cpu capacity must skip the retired row" = out$capacity$cpu$nodes == 2)
stopifnot("cpu cores must sum only the 2 active nodes" = as.numeric(out$capacity$cpu$cores) == 40)
stopifnot("cpu ram_gb must sum only the 2 active nodes" = as.numeric(out$capacity$cpu$ram_gb) == 200)
stopifnot("gpu capacity must skip the retired row" = out$capacity$gpu$nodes == 2)
stopifnot("gpu gpus must sum only the 2 active nodes" = as.numeric(out$capacity$gpu$gpus) == 8)
stopifnot("gpu vram_gb must sum only the 2 active nodes" = as.numeric(out$capacity$gpu$vram_gb) == 320)
pass("capacity counts skip retired rows")

cpu_types <- out$capacity$cpu$types
stopifnot("cpu types must have exactly 1 row (both active nodes are TypeA)" = nrow(cpu_types) == 1)
stopifnot("cpu types row must be [label,server,count,per_node,per_node_ram_gb]" =
  cpu_types[1, 1] == "TypeA" && cpu_types[1, 2] == "ModelX" &&
  as.numeric(cpu_types[1, 3]) == 2 && as.numeric(cpu_types[1, 4]) == 20 && as.numeric(cpu_types[1, 5]) == 100)
gpu_types <- out$capacity$gpu$types
stopifnot("gpu types must have exactly 1 row (both active nodes are L40S)" = nrow(gpu_types) == 1)
stopifnot("gpu types row must be [label,server,count,per_node,per_node_ram_gb]" =
  gpu_types[1, 1] == "L40S" && gpu_types[1, 2] == "GModelX" &&
  as.numeric(gpu_types[1, 3]) == 2 && as.numeric(gpu_types[1, 4]) == 4 && as.numeric(gpu_types[1, 5]) == 40)
pass("capacity types rows shaped [label, server, count, per_node, per_node_ram_gb]")

# cpu_monthly / gpu_monthly sums match the fixture by (month, class)
cm <- out$cpu_monthly
find_row <- function(mat, month, class) mat[mat[, 1] == month & mat[, 2] == class, , drop = FALSE]
r <- find_row(cm, prev2, "m1024");   stopifnot(as.numeric(r[1,3]) == 50  && as.numeric(r[1,4]) == 2)
r <- find_row(cm, prev2, "standard");stopifnot(as.numeric(r[1,3]) == 100 && as.numeric(r[1,4]) == 5)
r <- find_row(cm, prev1, "m1024");   stopifnot(as.numeric(r[1,3]) == 60  && as.numeric(r[1,4]) == 3)
r <- find_row(cm, prev1, "standard");stopifnot(as.numeric(r[1,3]) == 110 && as.numeric(r[1,4]) == 6)
stopifnot("cpu_monthly must not include the current month" = nrow(cm) == 4)
pass("cpu_monthly sums match the fixture by (month, class); current month dropped")

gm <- out$gpu_monthly
r <- find_row(gm, prev2, "H200"); stopifnot(as.numeric(r[1,3]) == 300 && as.numeric(r[1,4]) == 20)
r <- find_row(gm, prev2, "L40S"); stopifnot(as.numeric(r[1,3]) == 200 && as.numeric(r[1,4]) == 10)
r <- find_row(gm, prev1, "H200"); stopifnot(as.numeric(r[1,3]) == 310 && as.numeric(r[1,4]) == 21)
r <- find_row(gm, prev1, "L40S"); stopifnot(as.numeric(r[1,3]) == 210 && as.numeric(r[1,4]) == 11)
stopifnot("gpu_monthly must not include the current month" = nrow(gm) == 4)
pass("gpu_monthly sums match the fixture by (month, card); current month dropped")

# headline = cpu+gpu held/njobs summed over the trailing complete (intersection) months
stopifnot("headline$cpu_core_h must sum the 2 complete cpu months" = as.numeric(out$headline$cpu_core_h) == 320)
stopifnot("headline$gpu_h must sum the 2 complete gpu months" = as.numeric(out$headline$gpu_h) == 1020)
stopifnot("headline$jobs must be cpu+gpu njobs over the trailing complete months" = as.numeric(out$headline$jobs) == 78)
pass("headline sums cpu+gpu held/njobs over the trailing complete months")

# =====================================================================
# 2) Refuses identified input
# =====================================================================
f2 <- make_fixture(cpu_meta_over = list(identified = TRUE))
r2 <- run_script(f2)
stopifnot("identified:true CPU input must make the script stop() (nonzero exit)" = r2$status != 0)
pass("identified:true CPU input is refused")

# =====================================================================
# 3) Refuses stale CPU input (> 48h)
# =====================================================================
f3 <- make_fixture(cpu_meta_over = list(generated_epoch = as.numeric(Sys.time()) - 3 * 86400))
r3 <- run_script(f3)
stopifnot("CPU input 3 days old must make the script stop() (48h freshness limit)" = r3$status != 0)
pass("stale (3-day-old) CPU input is refused (48h limit)")

# =====================================================================
# 4) Refuses stale GPU input (> 35 days)
# =====================================================================
f4 <- make_fixture(gpu_meta_over = list(generated_epoch = as.numeric(Sys.time()) - 36 * 86400))
r4 <- run_script(f4)
stopifnot("GPU input 36 days old must make the script stop() (35d freshness limit)" = r4$status != 0)
pass("stale (36-day-old) GPU input is refused (35d limit)")

cat("\nALL TESTS PASSED\n")
