# =====================================================================
# test_cluster_data.R — fixture-driven tests for 50_cluster_data.R.
#
# Builds fake CPU/GPU sibling clones under tempdir() (JSON + inventory
# CSVs), runs 50_cluster_data.R against them as a subprocess (so its own
# stop()-on-bad-input paths are exercised for real, exit code and all),
# and checks the emitted output/cluster_data.json.
#
# Contract v2 (design revision of 2026-08-31): cpu_monthly rows widen to
# [month,node_class,held_h,utilized_h,fail_h,wkill_h,njobs,wa_used_h,wa_req_h];
# gpu_monthly rows widen to
# [month,card,held_h,real_h,residle_h,kwh,vram_h,fail_h,wkill_h,njobs];
# meta.window3 (trailing 3 complete months common to both pools) replaces
# window6; headline sums over window3.
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
# Copied verbatim from the real $PUB_GPU_CLONE/output/public_data.json "Fcols" (2026-08-31).
GPU_FCOLS <- c("pt","p","card","held","real","residle_h","vram_h","full_h","kwh",
               "fail_h","wkill_h","njobs","peakvram","peak_gb","nwait","w0","w1","w2","w3","w4")

# cols defaults to the full real column list; pass a subset (e.g. setdiff(GPU_FCOLS, "kwh"))
# to build a fixture missing a required field, for the fail-closed test below.
build_cpu_json <- function(rows, months = months3, meta_over = list(), cols = CPU_FCOLS) {
  meta <- modifyList(list(generated_epoch = as.numeric(Sys.time()), deid = TRUE, identified = FALSE), meta_over)
  n <- nrow(rows)
  F <- matrix("0", nrow = n, ncol = length(cols)); colnames(F) <- cols
  if ("pt" %in% cols)    F[, "pt"]    <- "M"
  if ("proj" %in% cols)  F[, "proj"]  <- "proj1"
  if ("user" %in% cols)  F[, "user"]  <- "u-0000"
  if ("queue" %in% cols) F[, "queue"] <- "owner"
  for (col in names(rows)) if (col %in% cols) F[, col] <- as.character(rows[[col]])
  list(meta = meta, periods = list(M = I(months), W = character(0), D = character(0)),
       Fcols = cols, F = unname(F))
}

build_gpu_json <- function(rows, months = months3, meta_over = list(), cols = GPU_FCOLS) {
  meta <- modifyList(list(generated_epoch = as.numeric(Sys.time()), public = TRUE,
                           identified = FALSE, deid = TRUE), meta_over)
  n <- nrow(rows)
  F <- matrix("0", nrow = n, ncol = length(cols)); colnames(F) <- cols
  if ("pt" %in% cols) F[, "pt"] <- "M"
  for (col in names(rows)) if (col %in% cols) F[, col] <- as.character(rows[[col]])
  list(meta = meta, periods = list(M = I(months), W = character(0), D = character(0)),
       Fcols = cols, F = unname(F))
}

# CPU: 2 node classes x 3 months (current month must be dropped), all 7 v2 metric fields
cpu_rows <- data.frame(
  p          = c(prev2, prev2, prev1, prev1, cur, cur),
  node_class = c("m1024","standard","m1024","standard","m1024","standard"),
  held       = c(50,  100,  60,  110,  999, 999),
  utilized   = c(40,   90,  50,  100,  999, 999),
  fail_h     = c(2,     3,   2,    4,   99,  99),
  wkill_h    = c(1,     1,   1,    2,   99,  99),
  njobs      = c(2,     5,   3,    6,   99,  99),
  wa_used_h  = c(45,   95,  55,  105,  999, 999),
  wa_req_h   = c(48,   98,  58,  108,  999, 999),
  stringsAsFactors = FALSE
)
# GPU: 2 cards x 3 months (current month must be dropped), all 8 v2 metric fields
gpu_rows <- data.frame(
  p         = c(prev2, prev2, prev1, prev1, cur, cur),
  card      = c("H200","L40S","H200","L40S","H200","L40S"),
  held      = c(300,  200,  310,  210,  888, 888),
  real      = c(250,  150,  260,  160,  888, 888),
  residle_h = c(10,     8,   11,    9,   88,  88),
  kwh       = c(500,  300,  510,  310,  888, 888),
  vram_h    = c(280,  180,  290,  190,  888, 888),
  fail_h    = c(5,     3,    6,    4,   88,  88),
  wkill_h   = c(2,     1,    2,    1,   88,  88),
  njobs     = c(20,   10,   21,   11,   88,  88),
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
make_fixture <- function(cpu_meta_over = list(), gpu_meta_over = list(),
                          cpu_cols = CPU_FCOLS, gpu_cols = GPU_FCOLS,
                          cpu_rows_in = cpu_rows, gpu_rows_in = gpu_rows,
                          cpu_months = months3, gpu_months = months3) {
  fx <- tempfile("cluster_data_fixture_")
  dir.create(file.path(fx, "scripts"), recursive = TRUE)
  file.copy(SCRIPT, file.path(fx, "scripts", "50_cluster_data.R"))
  cpu_dir <- file.path(fx, "cpu-clone"); gpu_dir <- file.path(fx, "gpu-clone")
  dir.create(file.path(cpu_dir, "output"), recursive = TRUE)
  dir.create(file.path(cpu_dir, "config"), recursive = TRUE)
  dir.create(file.path(gpu_dir, "output"), recursive = TRUE)
  dir.create(file.path(gpu_dir, "config"), recursive = TRUE)
  writeLines(toJSON(build_cpu_json(cpu_rows_in, months = cpu_months, meta_over = cpu_meta_over, cols = cpu_cols), auto_unbox = TRUE),
             file.path(cpu_dir, "output", "portal_data.json"))
  writeLines(toJSON(build_gpu_json(gpu_rows_in, months = gpu_months, meta_over = gpu_meta_over, cols = gpu_cols), auto_unbox = TRUE),
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
stopifnot("cpu_monthly rows must have 9 elements (contract v2)" = length(raw$cpu_monthly[[1]]) == 9)
stopifnot("gpu_monthly rows must have 10 elements (contract v2)" = length(raw$gpu_monthly[[1]]) == 10)
stopifnot("cpu_monthly rows must be [char,char,7x num], not all-string" = row_types_ok(raw$cpu_monthly[[1]], 2))
stopifnot("gpu_monthly rows must be [char,char,8x num], not all-string" = row_types_ok(raw$gpu_monthly[[1]], 2))
stopifnot("capacity.cpu.types rows must be [char,char,num,num,num], not all-string" =
  row_types_ok(raw$capacity$cpu$types[[1]], 2))
stopifnot("capacity.gpu.types rows must be [char,char,num,num,num], not all-string" =
  row_types_ok(raw$capacity$gpu$types[[1]], 2))
pass("cpu_monthly/gpu_monthly/capacity.types numeric fields are real JSON numbers, not strings; widened row shapes correct")

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

# cpu_monthly rows: [month,node_class,held_h,utilized_h,fail_h,wkill_h,njobs,wa_used_h,wa_req_h]
# sums match the fixture by (month, class)
cm <- out$cpu_monthly
find_row <- function(mat, month, class) mat[mat[, 1] == month & mat[, 2] == class, , drop = FALSE]
check_cpu_row <- function(month, class, held, utilized, fail_h, wkill_h, njobs, wa_used_h, wa_req_h) {
  r <- find_row(cm, month, class)
  stopifnot(nrow(r) == 1)
  stopifnot(as.numeric(r[1,3]) == held && as.numeric(r[1,4]) == utilized && as.numeric(r[1,5]) == fail_h &&
            as.numeric(r[1,6]) == wkill_h && as.numeric(r[1,7]) == njobs &&
            as.numeric(r[1,8]) == wa_used_h && as.numeric(r[1,9]) == wa_req_h)
}
check_cpu_row(prev2, "m1024",    50,  40, 2, 1, 2,  45,  48)
check_cpu_row(prev2, "standard",100,  90, 3, 1, 5,  95,  98)
check_cpu_row(prev1, "m1024",    60,  50, 2, 1, 3,  55,  58)
check_cpu_row(prev1, "standard",110, 100, 4, 2, 6, 105, 108)
stopifnot("cpu_monthly must not include the current month" = nrow(cm) == 4)
pass("cpu_monthly widened rows [held_h,utilized_h,fail_h,wkill_h,njobs,wa_used_h,wa_req_h] match the fixture by (month, class); current month dropped")

# gpu_monthly rows: [month,card,held_h,real_h,residle_h,kwh,vram_h,fail_h,wkill_h,njobs]
gm <- out$gpu_monthly
check_gpu_row <- function(month, card, held, real_h, residle_h, kwh, vram_h, fail_h, wkill_h, njobs) {
  r <- find_row(gm, month, card)
  stopifnot(nrow(r) == 1)
  stopifnot(as.numeric(r[1,3]) == held && as.numeric(r[1,4]) == real_h && as.numeric(r[1,5]) == residle_h &&
            as.numeric(r[1,6]) == kwh && as.numeric(r[1,7]) == vram_h && as.numeric(r[1,8]) == fail_h &&
            as.numeric(r[1,9]) == wkill_h && as.numeric(r[1,10]) == njobs)
}
check_gpu_row(prev2, "H200", 300, 250, 10, 500, 280, 5, 2, 20)
check_gpu_row(prev2, "L40S", 200, 150,  8, 300, 180, 3, 1, 10)
check_gpu_row(prev1, "H200", 310, 260, 11, 510, 290, 6, 2, 21)
check_gpu_row(prev1, "L40S", 210, 160,  9, 310, 190, 4, 1, 11)
stopifnot("gpu_monthly must not include the current month" = nrow(gm) == 4)
pass("gpu_monthly widened rows [held_h,real_h,residle_h,kwh,vram_h,fail_h,wkill_h,njobs] match the fixture by (month, card); current month dropped")

# meta.window3 replaces window6: trailing 3 complete months common to both pools
# (only 2 months are complete in this fixture, so window3 has 2, not 3 -- exercises the
# "up to 3, however many are actually available" semantics, not a fixed width of 3)
stopifnot("meta must carry window3, not window6" = is.null(out$meta$window6) && !is.null(out$meta$window3))
stopifnot("window3 must be the 2 complete common months here" = setequal(out$meta$window3, c(prev2, prev1)))
pass("meta.window3 present (window6 gone), holding the complete common months")

# headline = cpu+gpu held/njobs summed over window3
stopifnot("headline$cpu_core_h must sum the complete cpu months in window3" = as.numeric(out$headline$cpu_core_h) == 320)
stopifnot("headline$gpu_h must sum the complete gpu months in window3" = as.numeric(out$headline$gpu_h) == 1020)
stopifnot("headline$jobs must be cpu+gpu njobs over window3" = as.numeric(out$headline$jobs) == 78)
pass("headline sums cpu+gpu held/njobs over window3")

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
# 4) GPU freshness ceiling widened to 100 days (quarterly cadence): a
#    40-day-old GPU input still passes; a 101-day-old one is refused.
# =====================================================================
f4a <- make_fixture(gpu_meta_over = list(generated_epoch = as.numeric(Sys.time()) - 40 * 86400))
r4a <- run_script(f4a)
stopifnot("GPU input 40 days old must still succeed (100d freshness limit)" = r4a$status == 0)
pass("40-day-old GPU input still succeeds (100d limit)")

f4b <- make_fixture(gpu_meta_over = list(generated_epoch = as.numeric(Sys.time()) - 101 * 86400))
r4b <- run_script(f4b)
stopifnot("GPU input 101 days old must make the script stop() (100d freshness limit)" = r4b$status != 0)
pass("stale (101-day-old) GPU input is refused (100d limit)")

# =====================================================================
# 5) Fail closed: a GPU fixture missing a required v2 column (kwh) must
#    stop() the build rather than silently emit zeros/garbage.
# =====================================================================
f5 <- make_fixture(gpu_cols = setdiff(GPU_FCOLS, "kwh"))
r5 <- run_script(f5)
stopifnot("GPU input missing required column kwh must make the script stop() (nonzero exit)" = r5$status != 0)
pass("GPU input missing a required v2 column (kwh) is refused (fail closed)")

# =====================================================================
# 6) window3 must end at the calendar month just closed, not merely
#    whatever the two emits happen to agree on. A GPU input whose own
#    history stops one extra month early (newest common month = 2 months
#    back, not 1) must stop(); the normal case -- newest common month is
#    1 month back, the happy path above (f1/r1) -- must pass.
# =====================================================================
gpu_lag_rows <- data.frame(
  p = c(prev2, prev2), card = c("H200", "L40S"),
  held = c(300, 200), real = c(250, 150), residle_h = c(10, 8), kwh = c(500, 300),
  vram_h = c(280, 180), fail_h = c(5, 3), wkill_h = c(2, 1), njobs = c(20, 10),
  stringsAsFactors = FALSE
)
f6 <- make_fixture(gpu_rows_in = gpu_lag_rows, gpu_months = c(prev2, cur))
r6 <- run_script(f6)
stopifnot("GPU input whose newest common month is 2 months back must stop() (window3 lag guard)" =
            r6$status != 0 && grepl("window3 lag", r6$output))
pass("window3 ending 2 months back (not the month just closed) is refused, naming both months")

stopifnot("happy-path fixture (newest common month = 1 month back, the month just closed) must pass the window3 lag guard" =
            r1$status == 0)
pass("window3 ending at the month just closed (1 month back) passes the lag guard")

cat("\nALL TESTS PASSED\n")
