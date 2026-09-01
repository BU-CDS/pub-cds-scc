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
# Contract v3 (design revision of 2026-09-01) adds a third sibling input --
# the GPU internal de-identified emit ($PUB_GPU_CLONE/output/portal_data.json,
# same F/Fcols idiom as the CPU internal emit, accepted iff meta.deid is TRUE
# and meta.identified is FALSE, freshness <= 48h) -- read ONLY for pt=="M"
# rows' (p, user, proj) columns, joined with the CPU internal emit's own
# (p, user, proj) columns for month-grain community membership. New outputs:
# `community` rows [window_key, pool, users, groups] (window_key one of
# "M:YYYY-MM" for each month in the union of months_cpu/months_gpu, "P3"
# (=meta.window3), "P6" (trailing 6 of that union), "ALL" (the whole union) --
# exactly the windows build_cluster_page.R itself uses); `capacity_monthly`
# rows [month, pool, cap_h] (nominal units x hours in month, prorated by
# install_date/retired -- CPU units = cores, GPU units = gpus -- emitted per
# pool over that pool's own already-published month list, matching
# cpu_monthly/gpu_monthly's coverage); `capacity.{cpu,gpu}.added_12m`
# (nominal units installed in the 12 months ending on the run date, not
# retired); meta.contract = 3.
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
prev3_d <- seq(prev2_d, by = "-1 month", length.out = 2)[2]
cur     <- format(cur_d,   "%Y-%m")
prev1   <- format(prev1_d, "%Y-%m")
prev2   <- format(prev2_d, "%Y-%m")
prev3   <- format(prev3_d, "%Y-%m")
months3 <- c(prev2, prev1, cur)
months4 <- c(prev3, prev2, prev1, cur)   # 3 complete months once cur is dropped

# calendar helpers for the proration/added_12m fixtures below
month_start   <- function(m) as.Date(paste0(m, "-01"))
month_end     <- function(m) seq(month_start(m), by = "1 month", length.out = 2)[2] - 1
days_in_month <- function(m) as.integer(format(month_end(m), "%d"))

# ---- fixture builders --------------------------------------------------
# Copied verbatim from the real $PUB_CPU_CLONE/output/portal_data.json "Fcols" (2026-08-31).
CPU_FCOLS <- c("pt","p","proj","user","node_class","queue","held","utilized","runtime_h",
               "fail_h","wkill_h","njobs","peakmem_gb","fitn","m1024n","nwait",
               "w0","w1","w2","w3","w4","d0","d1","d2","d3","d4","wa_n","wa_used_h","wa_req_h")
# Copied verbatim from the real $PUB_GPU_CLONE/output/public_data.json "Fcols" (2026-08-31).
GPU_FCOLS <- c("pt","p","card","held","real","residle_h","vram_h","full_h","kwh",
               "fail_h","wkill_h","njobs","peakvram","peak_gb","nwait","w0","w1","w2","w3","w4")
# Copied verbatim from the real $PUB_GPU_CLONE/output/portal_data.json "Fcols" (2026-09-01,
# the NEW GPU internal de-identified emit contract v3 reads for community membership).
GPU_INTERNAL_FCOLS <- c("pt","p","proj","user","card","queue","held","real","residle_h","vram_h",
                         "full_h","kwh","fail_h","wkill_h","njobs","peakvram","peak_gb","nwait",
                         "w0","w1","w2","w3","w4")

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

# CPU inventory: 3 rows, 1 retired. install_date is long before any test month
# so the default fixture's capacity_monthly proration is a no-op (full month).
cpu_inv <- data.frame(
  host = c("nodeA","nodeB","nodeC"), server_model = c("ModelX","ModelX","ModelY"),
  cpu_type = c("TypeA","TypeA","TypeB"), ncpu = c(20,20,32), mem_gb = c(100,100,200),
  install_date = c("2015-01-01","2015-01-01","2015-01-01"),
  retired = c("","","2020-01-01"), stringsAsFactors = FALSE
)
# GPU inventory: 3 rows, 1 retired. Same install_date convention as cpu_inv.
gpu_inv <- data.frame(
  host = c("g1","g2","g3"), server_model = c("GModelX","GModelX","GModelY"),
  gpu_type = c("L40S","L40S","H200"), gpus = c(4,4,2), gpu_mem_gb = c(40,40,80),
  install_date = c("2015-01-01","2015-01-01","2015-01-01"),
  retired = c("","","2020-01-01"), stringsAsFactors = FALSE
)

# ---- build one fixture root + run 50_cluster_data.R against it --------
# gpu2_* params build the NEW GPU internal de-identified emit (contract v3):
# same F/Fcols idiom as the CPU internal emit (build_cpu_json is generic
# enough to reuse verbatim -- it only special-cases pt/proj/user/queue
# defaults, all of which GPU_INTERNAL_FCOLS also carries).
make_fixture <- function(cpu_meta_over = list(), gpu_meta_over = list(), gpu2_meta_over = list(),
                          cpu_cols = CPU_FCOLS, gpu_cols = GPU_FCOLS, gpu2_cols = GPU_INTERNAL_FCOLS,
                          cpu_rows_in = cpu_rows, gpu_rows_in = gpu_rows, gpu2_rows_in = gpu_rows,
                          cpu_months = months3, gpu_months = months3, gpu2_months = months3,
                          cpu_inv_in = cpu_inv, gpu_inv_in = gpu_inv) {
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
  writeLines(toJSON(build_cpu_json(gpu2_rows_in, months = gpu2_months, meta_over = gpu2_meta_over, cols = gpu2_cols), auto_unbox = TRUE),
             file.path(gpu_dir, "output", "portal_data.json"))
  write.csv(cpu_inv_in, file.path(cpu_dir, "config", "cds_cpu_inventory.csv"), row.names = FALSE, quote = FALSE)
  write.csv(gpu_inv_in, file.path(gpu_dir, "config", "gpu_inventory_history.csv"), row.names = FALSE, quote = FALSE)
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

# ---- contract v3 (happy path): meta.contract, community, capacity_monthly, added_12m ----
stopifnot("meta.contract must be 3" = !is.null(out$meta$contract) && as.numeric(out$meta$contract) == 3)
pass("meta.contract == 3")

stopifnot("community rows must have 4 elements (contract v3)" = length(raw$community[[1]]) == 4)
stopifnot("community rows must be [char,char,2x num], not all-string" = row_types_ok(raw$community[[1]], 2))
comm_keys <- unique(out$community[, 1])
expected_keys <- c(paste0("M:", c(prev2, prev1)), "P3", "P6", "ALL")
stopifnot("community window_key set must be M:<month> for each published month plus P3/P6/ALL" =
            setequal(comm_keys, expected_keys))
stopifnot("community pool set must be exactly {cpu, gpu}" = setequal(unique(out$community[, 2]), c("cpu", "gpu")))
stopifnot("community must have exactly one row per (window_key, pool)" =
            nrow(out$community) == length(expected_keys) * 2)
pass("community rows cover every M:/P3/P6/ALL window key for both pools, contract v3 shape")

stopifnot("capacity_monthly rows must have 3 elements (contract v3)" = length(raw$capacity_monthly[[1]]) == 3)
stopifnot("capacity_monthly rows must be [char,char,num], not all-string" = row_types_ok(raw$capacity_monthly[[1]], 2))
stopifnot("capacity_monthly must have one row per (month, pool), matching each pool's own published month list" =
            nrow(out$capacity_monthly) == 4)   # 2 cpu months + 2 gpu months (months3 minus cur)
cm <- out$capacity_monthly
find_cap <- function(mat, month, pool) mat[mat[, 1] == month & mat[, 2] == pool, , drop = FALSE]
expect_cpu_cap_h <- function(m) (20 + 20) * days_in_month(m) * 24   # nodeA+nodeB active, nodeC retired since 2020
expect_gpu_cap_h <- function(m) (4 + 4)   * days_in_month(m) * 24   # g1+g2 active, g3 retired since 2020
for (m in c(prev2, prev1)) {
  r_cpu <- find_cap(cm, m, "cpu"); stopifnot(nrow(r_cpu) == 1)
  stopifnot(abs(as.numeric(r_cpu[1, 3]) - expect_cpu_cap_h(m)) < 0.01)
  r_gpu <- find_cap(cm, m, "gpu"); stopifnot(nrow(r_gpu) == 1)
  stopifnot(abs(as.numeric(r_gpu[1, 3]) - expect_gpu_cap_h(m)) < 0.01)
}
pass("capacity_monthly cap_h matches nominal active units x hours-in-month for the default (unprorated, all install dates old) fixture")

stopifnot("capacity.cpu.added_12m must be present and 0 (all install dates are old in the default fixture)" =
            !is.null(out$capacity$cpu$added_12m) && as.integer(out$capacity$cpu$added_12m) == 0)
stopifnot("capacity.gpu.added_12m must be present and 0 (all install dates are old in the default fixture)" =
            !is.null(out$capacity$gpu$added_12m) && as.integer(out$capacity$gpu$added_12m) == 0)
pass("capacity.{cpu,gpu}.added_12m present and 0 for the default (old-install) fixture")

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

# =====================================================================
# 7) Community membership (contract v3): distinct users/groups per
#    (M:, P3, P6, ALL) window key, for both pools -- CPU from its own
#    internal emit's (p, user, proj) columns, GPU from the NEW internal
#    de-identified emit's (p, user, proj) columns. Three complete months
#    (prev3, prev2, prev1; cur dropped), overlapping user codes and
#    projects across months so per-month counts differ from the
#    combined-window counts.
# =====================================================================
community_cpu_rows <- data.frame(
  p          = c(prev3, prev3, prev2, prev2, prev1, prev1),
  node_class = c("m1024","standard","m1024","standard","m1024","standard"),
  user       = c("u-1001","u-1002","u-1002","u-1003","u-1001","u-1004"),
  proj       = c("alpha","beta","beta","gamma","alpha","delta"),
  held = c(10,10,10,10,10,10), utilized = c(5,5,5,5,5,5),
  fail_h = c(0,0,0,0,0,0), wkill_h = c(0,0,0,0,0,0), njobs = c(1,1,1,1,1,1),
  wa_used_h = c(5,5,5,5,5,5), wa_req_h = c(6,6,6,6,6,6),
  stringsAsFactors = FALSE
)
gpu_pub_rows4 <- data.frame(
  p         = c(prev3, prev3, prev2, prev2, prev1, prev1),
  card      = c("H200","L40S","H200","L40S","H200","L40S"),
  held = c(300,200,300,200,310,210), real = c(250,150,250,150,260,160),
  residle_h = c(10,8,10,8,11,9), kwh = c(500,300,500,300,510,310),
  vram_h = c(280,180,280,180,290,190), fail_h = c(5,3,5,3,6,4),
  wkill_h = c(2,1,2,1,2,1), njobs = c(20,10,20,10,21,11),
  stringsAsFactors = FALSE
)
community_gpu2_rows <- data.frame(
  p     = c(prev3, prev3, prev3, prev2, prev1, prev1),
  card  = c("H200","H200","H200","H200","H200","H200"),
  user  = c("u-2001","u-2002","u-2003","u-2001","u-2001","u-2004"),
  proj  = c("g-one","g-two","g-three","g-one","g-one","g-four"),
  held = c(1,1,1,1,1,1), real = c(1,1,1,1,1,1), residle_h = c(0,0,0,0,0,0),
  kwh = c(1,1,1,1,1,1), vram_h = c(1,1,1,1,1,1), fail_h = c(0,0,0,0,0,0),
  wkill_h = c(0,0,0,0,0,0), njobs = c(1,1,1,1,1,1),
  stringsAsFactors = FALSE
)
f7 <- make_fixture(cpu_rows_in = community_cpu_rows, cpu_months = months4,
                    gpu_rows_in = gpu_pub_rows4, gpu_months = months4,
                    gpu2_rows_in = community_gpu2_rows, gpu2_months = months4)
r7 <- run_script(f7)
stopifnot("community fixture run must exit 0" = r7$status == 0)
out7 <- fromJSON(file.path(f7$fx, "output", "cluster_data.json"), simplifyVector = TRUE, simplifyMatrix = TRUE)
comm7 <- out7$community
find_comm <- function(mat, key, pool) mat[mat[, 1] == key & mat[, 2] == pool, , drop = FALSE]
check_comm <- function(key, pool, users, groups) {
  r <- find_comm(comm7, key, pool)
  stopifnot(nrow(r) == 1)
  stopifnot(as.numeric(r[1, 3]) == users && as.numeric(r[1, 4]) == groups)
}
check_comm(paste0("M:", prev3), "cpu", 2, 2)   # {u-1001,u-1002} / {alpha,beta}
check_comm(paste0("M:", prev2), "cpu", 2, 2)   # {u-1002,u-1003} / {beta,gamma}
check_comm(paste0("M:", prev1), "cpu", 2, 2)   # {u-1001,u-1004} / {alpha,delta}
check_comm("P3",  "cpu", 4, 4)                 # union across the 3 months
check_comm("P6",  "cpu", 4, 4)                 # only 3 months exist -> same as P3/ALL
check_comm("ALL", "cpu", 4, 4)
check_comm(paste0("M:", prev3), "gpu", 3, 3)   # {u-2001,u-2002,u-2003} / {g-one,g-two,g-three}
check_comm(paste0("M:", prev2), "gpu", 1, 1)   # {u-2001} / {g-one}
check_comm(paste0("M:", prev1), "gpu", 2, 2)   # {u-2001,u-2004} / {g-one,g-four}
check_comm("P3",  "gpu", 4, 4)
check_comm("P6",  "gpu", 4, 4)
check_comm("ALL", "gpu", 4, 4)
pass("community distinct users/groups match the overlapping fixture per M:/P3/P6/ALL window key, for both pools")

# no fixture user code or project name may leak into the emitted JSON text
raw7 <- paste(readLines(file.path(f7$fx, "output", "cluster_data.json"), warn = FALSE), collapse = "\n")
leaked <- c("u-1001","u-1002","u-1003","u-1004","alpha","beta","gamma","delta",
            "u-2001","u-2002","u-2003","u-2004","g-one","g-two","g-three","g-four")
stopifnot("no fixture user code or project name may appear in the emitted JSON text" =
            !any(vapply(leaked, function(s) grepl(s, raw7, fixed = TRUE), logical(1))))
pass("no fixture user code or project name leaks into the emitted cluster_data.json text")

# =====================================================================
# 8) capacity_monthly: cap_h prorated by days for a unit installed
#    mid-month and a unit retired mid-month, alongside an always-on unit
#    and units wholly outside the month (before install / already
#    retired) that must contribute zero. Checked against prev1 (part of
#    the default months3 window).
# =====================================================================
dim1 <- days_in_month(prev1)
mid_install     <- format(month_start(prev1) + 10, "%Y-%m-%d")   # 11th day of prev1
mid_retire      <- format(month_start(prev1) + 15, "%Y-%m-%d")   # active through the 15th day
future_install  <- format(month_end(prev1)   + 5,  "%Y-%m-%d")   # installed after prev1 ends

prorate_cpu_inv <- data.frame(
  host = c("full","mid-install","mid-retire","future","long-retired"),
  server_model = rep("ModelX", 5), cpu_type = rep("TypeA", 5),
  ncpu = c(5, 10, 20, 999, 999), mem_gb = rep(100, 5),
  install_date = c("2015-01-01", mid_install, "2015-01-01", future_install, "2015-01-01"),
  retired      = c("",           "",           mid_retire,  "",             "2019-01-01"),
  stringsAsFactors = FALSE
)
mid_install_g <- format(month_start(prev1) + 5,  "%Y-%m-%d")
mid_retire_g  <- format(month_start(prev1) + 20, "%Y-%m-%d")
prorate_gpu_inv <- data.frame(
  host = c("full","mid-install","mid-retire"),
  server_model = rep("GModelX", 3), cpu_type = rep("TypeA", 3),
  gpu_type = rep("H200", 3), gpus = c(2, 4, 1), gpu_mem_gb = rep(80, 3),
  install_date = c("2015-01-01", mid_install_g, "2015-01-01"),
  retired      = c("",           "",             mid_retire_g),
  stringsAsFactors = FALSE
)
f8 <- make_fixture(cpu_inv_in = prorate_cpu_inv, gpu_inv_in = prorate_gpu_inv)
r8 <- run_script(f8)
stopifnot("proration fixture run must exit 0" = r8$status == 0)
out8 <- fromJSON(file.path(f8$fx, "output", "cluster_data.json"), simplifyVector = TRUE, simplifyMatrix = TRUE)
cm8 <- out8$capacity_monthly
r_cpu8 <- cm8[cm8[, 1] == prev1 & cm8[, 2] == "cpu", , drop = FALSE]
stopifnot(nrow(r_cpu8) == 1)
expect_cpu8 <- (dim1 * 5 * 24) + ((dim1 - 10) * 10 * 24) + (15 * 20 * 24)   # future/long-retired contribute 0
stopifnot("cpu capacity_monthly cap_h must prorate mid-month install/retire by days" =
            abs(as.numeric(r_cpu8[1, 3]) - expect_cpu8) < 0.01)
r_gpu8 <- cm8[cm8[, 1] == prev1 & cm8[, 2] == "gpu", , drop = FALSE]
stopifnot(nrow(r_gpu8) == 1)
expect_gpu8 <- (dim1 * 2 * 24) + ((dim1 - 5) * 4 * 24) + (20 * 1 * 24)
stopifnot("gpu capacity_monthly cap_h must prorate mid-month install/retire by days" =
            abs(as.numeric(r_gpu8[1, 3]) - expect_gpu8) < 0.01)
pass("capacity_monthly cap_h prorates mid-month install/retire dates by days; units before install or already retired contribute 0")

# =====================================================================
# 9) capacity.{cpu,gpu}.added_12m: nominal units (cores/gpus, not rows)
#    installed within the 12 months ending on the run date, excluding
#    retired units and units installed further back.
# =====================================================================
today       <- Sys.Date()
recent_in   <- format(today - 30,  "%Y-%m-%d")   # inside the 12mo window
recent_far  <- format(today - 400, "%Y-%m-%d")   # outside the 12mo window
recent_retd <- format(today - 60,  "%Y-%m-%d")   # inside the window but retired
retired_on  <- format(today - 10,  "%Y-%m-%d")
added12_cpu_inv <- data.frame(
  host = c("in-window","out-window","retired-in-window"),
  server_model = rep("ModelX", 3), cpu_type = rep("TypeA", 3),
  ncpu = c(10, 999, 999), mem_gb = rep(100, 3),
  install_date = c(recent_in, recent_far, recent_retd),
  retired      = c("",        "",         retired_on),
  stringsAsFactors = FALSE
)
added12_gpu_inv <- data.frame(
  host = c("in-window","out-window","retired-in-window"),
  server_model = rep("GModelX", 3), cpu_type = rep("TypeA", 3),
  gpu_type = rep("H200", 3), gpus = c(6, 888, 888), gpu_mem_gb = rep(80, 3),
  install_date = c(recent_in, recent_far, recent_retd),
  retired      = c("",        "",         retired_on),
  stringsAsFactors = FALSE
)
f9 <- make_fixture(cpu_inv_in = added12_cpu_inv, gpu_inv_in = added12_gpu_inv)
r9 <- run_script(f9)
stopifnot("added_12m fixture run must exit 0" = r9$status == 0)
out9 <- fromJSON(file.path(f9$fx, "output", "cluster_data.json"), simplifyVector = TRUE, simplifyMatrix = TRUE)
stopifnot("capacity.cpu.added_12m must count only the non-retired unit installed within 12 months (10 cores)" =
            !is.null(out9$capacity$cpu$added_12m) && as.integer(out9$capacity$cpu$added_12m) == 10)
stopifnot("capacity.gpu.added_12m must count only the non-retired unit installed within 12 months (6 gpus)" =
            !is.null(out9$capacity$gpu$added_12m) && as.integer(out9$capacity$gpu$added_12m) == 6)
pass("capacity.{cpu,gpu}.added_12m counts nominal units installed within the past 12 months, excluding retired and older units")

# =====================================================================
# 10) The NEW GPU internal de-identified emit must be refused if
#     identified, not marked deid, or stale (> 48h); a fresh (40h old)
#     one must still succeed.
# =====================================================================
f10a <- make_fixture(gpu2_meta_over = list(identified = TRUE))
r10a <- run_script(f10a)
stopifnot("identified:true GPU internal emit must make the script stop()" = r10a$status != 0)
pass("identified:true GPU internal emit is refused")

f10b <- make_fixture(gpu2_meta_over = list(deid = FALSE))
r10b <- run_script(f10b)
stopifnot("deid:false GPU internal emit must make the script stop()" = r10b$status != 0)
pass("deid:false GPU internal emit is refused")

f10c <- make_fixture(gpu2_meta_over = list(generated_epoch = as.numeric(Sys.time()) - 3 * 86400))
r10c <- run_script(f10c)
stopifnot("GPU internal emit 3 days old must make the script stop() (48h freshness limit)" = r10c$status != 0)
pass("stale (3-day-old) GPU internal emit is refused (48h limit)")

f10d <- make_fixture(gpu2_meta_over = list(generated_epoch = as.numeric(Sys.time()) - 40 * 3600))
r10d <- run_script(f10d)
stopifnot("GPU internal emit 40h old must still succeed (48h freshness limit)" = r10d$status == 0)
pass("40-hour-old GPU internal emit still succeeds (48h limit)")

cat("\nALL TESTS PASSED\n")
