# =============================================================================
# 04_pilot.R
#check the simulation functions on a few scenarios before the full run. Pilot results are for DEBUGGING ONLY and are not reported as findings.
# =============================================================================

source("2_sim_functions.R") # loads the functions (nothing runs yet)

mkt <- read.csv("data/processed/mkt_excess_2015_2024.csv")
stopifnot(nrow(mkt) == 120, !anyNA(mkt$mkt_excess))
market_full <- mkt$mkt_excess # 120 monthly market excess returns (decimals)

# Check 1: does the function reproduce single-fund result? 
# Same seed, same settings as 03_one_fund.R (alpha 0.004, SD 0.04, T = 120).
set.seed(2026)
chk <- simulate_one_fund(true_alpha = 0.004, true_beta = 1, resid_sd = 0.04,
                         T_months = 120, market_full = market_full)
print(round(chk, 6)) # compare with alpha_hat, alpha_se, t_alpha, p_one, beta_hat from step 03

# Check 2: same seed gives identical results (reproducibility)
set.seed(1); a <- simulate_one_fund(0.002, 1, 0.04, 60, market_full)
set.seed(1); b <- simulate_one_fund(0.002, 1, 0.04, 60, market_full)
identical(a, b) # expect TRUE

#Check 3: small pilot
pilot_grid <- data.frame(
  scenario_id = 1:4,
  true_alpha  = c(0,    0,    0.004, 0.004),
  resid_sd    = c(0.04, 0.06, 0.02,  0.06),
  T_months    = c(120,  36,   120,   36)
)
pilot_grid

pilot_seed <- 1001  # pilot only; the full run will have its own recorded seed
n_reps     <- 200

set.seed(pilot_seed)
timing <- system.time(
  pilot <- run_grid(pilot_grid, n_reps = n_reps, market_full = market_full)
)
timing["elapsed"] # seconds taken

# Structure and logic checks 
dim(pilot)  # expect 800 rows (4 scenarios x 200) and 12 columns
head(pilot, 3)
anyNA(pilot)  # expect FALSE
table(pilot$scenario_id)  # expect 200 per scenario

# Detection should be exactly "t above the one-sided 5% critical value"
crit <- qt(0.95, df = pilot$T_months - 2)
stopifnot(all(pilot$detected == (pilot$t_alpha > crit)))

# Summary by scenario 
pilot_summary <- summarise_scenarios(pilot, market_full)
print(pilot_summary, digits = 3)

