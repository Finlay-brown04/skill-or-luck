# run_all.R  (lives in the project root, next to the .Rproj file)
# Runs the whole "Skill or Luck?" pipeline, from the raw download to the figures.
#
# How to use:
#   1. Open the R Project (the .Rproj file) so the working directory is the project root.
#   2. Session > Restart R  (gives you a clean session).
#   3. In the Console, run:  source("run_all.R")
#
# Every simulation seed is set inside the numbered scripts, so a clean run should
# reproduce the same detection rates every time.

started <- Sys.time()

# 1. Check we are in the project root ----------------------------------------
if (!dir.exists("scripts") || !file.exists("scripts/2_sim_functions.R")) {
  stop("Run this from the project root (open the .Rproj file first). ",
       "Current working directory: ", getwd(), call. = FALSE)
}

# 2. Check the packages are installed -----------------------------------------
needed <- c("ggplot2", "dplyr")
missing_pkgs <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  stop("Install these packages once, in the Console: install.packages(c(",
       paste0('"', missing_pkgs, '"', collapse = ", "), "))", call. = FALSE)
}

# 3. Create folders that Git does not store (Git ignores empty folders) -------
for (d in c("data/raw", "data/processed", "outputs/tables", "outputs/figures")) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# 4. The pipeline --------------------------------------------------------------
# 2_sim_functions.R only defines shared functions; the other scripts load it themselves.
# 3_pilot.R is a small debugging pilot. Set run_pilot <- TRUE to include it.
run_pilot <- FALSE

steps <- c(
  "scripts/1_download_data.R",
  "scripts/4_run_simulation.R",
  "scripts/5_extra_validation.R",
  "scripts/6_heatmap.R",
  "scripts/7_alpha_distribution.R"
)
if (run_pilot) {
  steps <- c(steps[1], "scripts/3_pilot.R", steps[-1])
}

for (s in steps) {
  cat("\n=== Running", s, "===\n")
  t0 <- Sys.time()
  tryCatch(
    # Each script runs in its own environment, so nothing leaks between steps.
    # print.eval = TRUE shows tables that a script prints by naming an object.
    source(s, local = new.env(parent = globalenv()), echo = FALSE, print.eval = TRUE),
    error = function(e) stop("Step failed: ", s, "\n", conditionMessage(e), call. = FALSE)
  )
  cat(sprintf("--- finished %s in %.1f seconds\n", s,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  if (s == steps[1] && !file.exists("data/processed/mkt_excess_2015_2024.csv")) {
    stop("The first step did not create data/processed/mkt_excess_2015_2024.csv. ",
         "If cleaning is a separate script, add it to 'steps' after the download.",
         call. = FALSE)
  }
}

# 5. Check the expected outputs exist ------------------------------------------
expected <- c(
  "data/processed/mkt_excess_2015_2024.csv",
  "data/processed/simulation_replications.csv",
  "outputs/tables/scenario_summary.csv",
  "outputs/tables/power_vs_theory.csv",
  "outputs/tables/zero_alpha_calibration_check.csv",
  "outputs/figures/heatmap_detection_rates_wide.png",
  "outputs/figures/heatmap_detection_rates_portrait.png",
  "outputs/figures/alpha_distribution_sd4_wide.png",
  "outputs/figures/alpha_distribution_sd4_portrait.png"
)
found <- file.exists(expected)
cat("\n=== Output check ===\n")
for (i in seq_along(expected)) {
  cat(if (found[i]) "OK      " else "MISSING ", expected[i], "\n", sep = "")
}

if (file.exists("outputs/tables/scenario_summary.csv")) {
  n_rows <- nrow(read.csv("outputs/tables/scenario_summary.csv"))
  cat("Rows in scenario_summary.csv:", n_rows, "(expected 27, one per scenario)\n")
}

if (!all(found)) {
  stop("Some expected outputs are missing. See the list above.", call. = FALSE)
}

cat(sprintf("\nAll steps finished in %.1f minutes.\n",
            as.numeric(difftime(Sys.time(), started, units = "mins"))))
cat("Now compare outputs/tables/scenario_summary.csv with your earlier copy: ",
    "the detection rates should be identical.\n", sep = "")
