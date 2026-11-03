# =============================================================================
# 05_run_simulation.R
# Full Monte Carlo: 27 scenarios x 1,000 simulated funds each.
# Model: fund excess return = alpha + beta * market excess return + error
# All returns are MONTHLY and in DECIMALS. Fund returns are SIMULATED;
# only the market excess returns are historical (Fama/French Mkt-RF).
# =============================================================================

source("scripts/2_sim_functions.R")

# 1. Settings (fixed before running; not changed after seeing results) 
master_seed   <- 20261101
n_reps        <- 1000
alphas        <- c(0, 0.002, 0.004)  # monthly alpha: 0%, 0.2%, 0.4%
resid_sds     <- c(0.02, 0.04, 0.06)# monthly residual SD: 2%, 4%, 6%
track_lengths <- c(36, 60, 120) # months

grid <- expand.grid(true_alpha = alphas, resid_sd = resid_sds,
                    T_months = track_lengths)
grid$scenario_id <- seq_len(nrow(grid))
grid <- grid[, c("scenario_id", "true_alpha", "resid_sd", "T_months")]
stopifnot(nrow(grid) == 27)
print(grid)

# 2. Load the historical market data 
mkt <- read.csv("data/processed/mkt_excess_2015_2024.csv")
stopifnot(nrow(mkt) == 120, !anyNA(mkt$mkt_excess))
market_full <- mkt$mkt_excess

# 3. Run the simulation 
set.seed(master_seed)   # one seed for the whole run; scenarios run in grid order
run_time <- system.time(
  results <- run_grid(grid, n_reps = n_reps, market_full = market_full)
)
run_time["elapsed"] # seconds taken

write.csv(results, "data/processed/simulation_replications.csv", row.names = FALSE)

# 4. Structure checks 
dim(results) # expect 27000 rows, 12 columns
anyNA(results)  # expect FALSE
table(results$scenario_id)   # expect 1000 for each of the 27 scenarios
stopifnot(nrow(results) == 27 * n_reps,
          !anyNA(results),
          !anyDuplicated(results[, c("scenario_id", "replication")]))

crit <- qt(0.95, df = results$T_months - 2)     # one-sided 5% critical values
stopifnot(all(results$detected == (results$t_alpha > crit)))

#5. Scenario summary 
summ <- summarise_scenarios(results, market_full)

summ$bias                 <- summ$mean_alpha_hat - summ$true_alpha
summ$mc_se_mean_alpha_hat <- summ$sd_alpha_hat / sqrt(summ$n_reps)
summ$z_bias               <- summ$bias / summ$mc_se_mean_alpha_hat
summ$sd_ratio             <- summ$sd_alpha_hat / summ$theory_alpha_se

write.csv(summ, "outputs/tables/scenario_summary.csv", row.names = FALSE)

print(summ[, c("scenario_id", "true_alpha", "resid_sd", "T_months", "measure",
               "detection_rate", "mc_se")], digits = 3)

# 6. Validation A: is estimated alpha centred on true alpha? 
print(summ[, c("scenario_id", "true_alpha", "mean_alpha_hat", "bias",
               "mc_se_mean_alpha_hat", "z_bias")], digits = 3)

# 7. Validation B: zero-alpha rejection rates vs 5% 
zero <- summ[summ$true_alpha == 0, ]
zero$z_vs_5pct <- (zero$detection_rate - 0.05) / sqrt(0.05 * 0.95 / zero$n_reps)
print(zero[, c("scenario_id", "resid_sd", "T_months", "detection_rate",
               "mc_se", "z_vs_5pct")], digits = 3)

# If the test is calibrated, zero-alpha p-values are spread evenly over 0 to 1,
# so P(p < 1%), P(p < 5%), P(p < 10%) should be about 1%, 5%, 10%.
zero_p <- results$p_one_sided[results$true_alpha == 0]
length(zero_p)            # expect 9000
c(below_1pct = mean(zero_p < 0.01),
  below_5pct = mean(zero_p < 0.05),
  below_10pct = mean(zero_p < 0.10))

# 8. Validation C: does the spread of estimates match theory? 
print(summ[, c("scenario_id", "resid_sd", "T_months", "sd_alpha_hat",
               "mean_alpha_se", "theory_alpha_se", "sd_ratio")], digits = 3)
range(summ$sd_ratio)

# 9. Pattern check: detection rate by scenario 
# Rows: residual SD and true alpha. Columns: track record (months).
ftable(xtabs(round(detection_rate, 3) ~ resid_sd + true_alpha + T_months,
             data = summ))

# 10. Record the run for reproducibility 
run_info <- c(
  "Skill or Luck? simulation run",
  paste("Run completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste("Random seed:", master_seed),
  paste("Random number generator:", paste(RNGkind(), collapse = ", ")),
  paste("Repetitions per scenario:", n_reps),
  "Scenarios: 27 = alpha (0, 0.002, 0.004) x residual SD (0.02, 0.04, 0.06) x track record (36, 60, 120 months)",
  "Market input: final T months of Jan 2015 - Dec 2024 Fama/French Mkt-RF (monthly, decimals)",
  "Fund returns: SIMULATED. Beta = 1, errors independent normal, mean zero",
  "Test: one-sided 5% t-test of H0 alpha <= 0 vs H1 alpha > 0, df = T - 2, conventional OLS SEs",
  paste("R version:", R.version.string),
  paste("Elapsed seconds:", round(run_time["elapsed"], 1))
)
writeLines(run_info, "outputs/tables/run_metadata.txt")
writeLines(capture.output(sessionInfo()), "outputs/sessionInfo.txt")
cat(run_info, sep = "\n")
