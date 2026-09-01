# =====================================================================
# week_helpers.R — calendar helpers shared by 50_cluster_data.R and its
# tests (sourced relative to the script; no side effects, base R only).
# =====================================================================
month_start <- function(m) as.Date(paste0(m, "-01"))
month_end   <- function(m) seq(month_start(m), by = "1 month", length.out = 2)[2] - 1

# ISO week key "YYYY-Www" -> that week's Monday. ISO week 1 is the week that
# contains 4 January, so its Monday is the Monday on or before Jan 4; week w
# starts 7*(w-1) days later. Vectorised over `key`.
iso_monday <- function(key) {
  y <- as.integer(substr(key, 1, 4)); w <- as.integer(sub("^\\d{4}-W", "", key))
  jan4 <- as.Date(sprintf("%d-01-04", y))
  mon1 <- jan4 - (as.integer(format(jan4, "%u")) - 1L)
  mon1 + 7L * (w - 1L)
}

# Complete weeks inside a run of published months: every Monday from the
# first Monday >= the first day of months[1] to the last Monday whose Sunday
# <= the last day of the final month (R6.3). Empty when no whole week fits.
week_mondays <- function(months) {
  if (!length(months)) return(as.Date(character(0)))
  first <- month_start(months[1]); last <- month_end(months[length(months)])
  m0 <- first + ((8L - as.integer(format(first, "%u"))) %% 7L)            # next Monday on/after `first`
  m1 <- last - 6L; m1 <- m1 - ((as.integer(format(m1, "%u")) - 1L) %% 7L)   # last Monday whose Sunday <= `last`
  if (m1 < m0) return(as.Date(character(0)))
  seq(m0, m1, by = "7 days")
}
