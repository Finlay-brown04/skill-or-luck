# =============================================================================
# 06_extra_validation.R
# Purpose: (A) compare simulated detection rates with exact theoretical power
#              from the non-central t distribution, for all 27 scenarios;
#          (B) high-precision check of zero-alpha calibration (20,000 funds
#              per scenario, separate recorded seed).
# =============================================================================

source("scripts/2_sim_functions.R")

mkt <- read.csv("data/processed/mkt_excess_2015_2024.csv")
stopifnot(nrow(mkt) == 120, !anyNA(mkt$mkt_excess))
market_full <- mkt$mkt_excess

summ <- read.csv("outputs/tables/scenario_summary.csv")

# Exact theoretical power 
# With fixed regressors and normal errors, t = (Z + ncp) / sqrt(chi-sq / df),
# a NON-CENTRAL t with ncp = true alpha / true SE of alpha-hat.
# For true alpha = 0 the ncp is 0 and the rejection rate is exactly 5%.
df   <- summ$T_months - 2
crit <- qt(0.95, df = df)                          # one-sided 5% critical value
ncp  <- summ$true_alpha / summ$theory_alpha_se

summ$theory_power <- pt(crit, df = df, ncp = ncp, lower.tail = FALSE)

# z-score: how many Monte Carlo SEs is the simulated rate from theory?
summ$z_vs_theory <- (summ$detection_rate - summ$theory_power) /
  sqrt(summ$theory_power * (1 - summ$theory_power) / summ$n_reps)

print(summ[, c("scenario_id", "true_alpha", "resid_sd", "T_months",
               "detection_rate", "theory_power", "z_vs_theory")], digits = 3)

# If the simulation is right, these z-scores behave like standard normals:
# most within +/-2, almost none beyond +/-3, and the sum of squares near 27.
range(summ$z_vs_theory)
sum(summ$z_vs_theory^2)

write.csv(summ[, c("scenario_id", "true_alpha", "resid_sd", "T_months",
                   "detection_rate", "mc_se", "theory_power", "z_vs_theory")],
          "outputs/tables/power_vs_theory.csv", row.names = FALSE)

#B. High-precision zero-alpha calibration check 
check_seed <- 20261102      
check_reps <- 20000

zero_grid <- summ[summ$true_alpha == 0,
                  c("scenario_id", "true_alpha", "resid_sd", "T_months")]

set.seed(check_seed)
check_time <- system.time(
  chk <- run_grid(zero_grid, n_reps = check_reps, market_full = market_full)
)
check_time["elapsed"]     

chk_summ <- summarise_scenarios(chk, market_full)
chk_summ$z_vs_5pct <- (chk_summ$detection_rate - 0.05) /
  sqrt(0.05 * 0.95 / chk_summ$n_reps)

print(chk_summ[, c("scenario_id", "resid_sd", "T_months", "detection_rate",
                   "mc_se", "z_vs_5pct")], digits = 3)

# Pooled over all nine zero-alpha scenarios, and by track-record length
c(pooled_rate = mean(chk$detected), n = nrow(chk),
  mc_se = sqrt(0.05 * 0.95 / nrow(chk)))
tapply(chk$detected, chk$T_months, mean)

write.csv(chk_summ, "outputs/tables/zero_alpha_calibration_check.csv",
          row.names = FALSE)
writeLines(c(
  "Extra validation run (06_extra_validation.R)",
  paste("Run completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste("Seed:", check_seed),
  paste("Repetitions per zero-alpha scenario:", check_reps),
  "Purpose: check false-positive calibration; main results are unchanged."
), "outputs/tables/validation_check_metadata.txt")