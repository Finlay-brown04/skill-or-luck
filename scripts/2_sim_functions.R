# =============================================================================
# sim_functions.R
# Reusable functions for the "Skill or Luck?" Monte Carlo simulation.
# Model: fund excess return = alpha + beta * market excess return + error
# All returns are MONTHLY and in DECIMALS (0.01 = 1%).
# =============================================================================

#Simulate ONE fund and test its alpha
simulate_one_fund <- function(true_alpha, true_beta = 1, resid_sd, T_months,
                              market_full) {
  stopifnot(T_months <= length(market_full), resid_sd > 0)
  
  market <- tail(market_full, T_months)       # final T_months of market history
  eps    <- rnorm(T_months, mean = 0, sd = resid_sd)   # independent normal errors
  
  fund_excess <- true_alpha + true_beta * market + eps
  
  fit <- lm(fund_excess ~ market)             # OLS with an intercept
  cf  <- coef(summary(fit))
  
  t_alpha <- cf["(Intercept)", "t value"]
  df      <- df.residual(fit)                 # equals T_months - 2
  
  # One-sided p-value for H1: alpha > 0 (upper tail of the t distribution).
  # Correct for BOTH signs of t; never just halve the two-sided p-value.
  p_one <- pt(t_alpha, df = df, lower.tail = FALSE)
  
  c(alpha_hat   = cf["(Intercept)", "Estimate"],
    alpha_se    = cf["(Intercept)", "Std. Error"],
    t_alpha     = t_alpha,
    p_one_sided = p_one,
    beta_hat    = cf["market", "Estimate"])
}

#Run ONE scenario for n_reps repetitions
run_scenario <- function(true_alpha, true_beta = 1, resid_sd, T_months, n_reps,
                         market_full, scenario_id = NA, alpha_level = 0.05) {
  # vapply() repeats the function n_reps times and stacks the results as columns
  out <- vapply(
    seq_len(n_reps),
    function(r) simulate_one_fund(true_alpha = true_alpha, true_beta = true_beta,
                                  resid_sd = resid_sd, T_months = T_months,
                                  market_full = market_full),
    FUN.VALUE = numeric(5)
  )
  out <- as.data.frame(t(out))                # t() flips so each row is one fund
  
  data.frame(
    scenario_id = scenario_id,
    true_alpha  = true_alpha,
    true_beta   = true_beta,
    resid_sd    = resid_sd,
    T_months    = T_months,
    replication = seq_len(n_reps),
    out,
    detected    = out$p_one_sided < alpha_level
  )
}

#Run every row of a scenario grid
run_grid <- function(grid, n_reps, market_full) {
  pieces <- lapply(seq_len(nrow(grid)), function(i) {
    run_scenario(true_alpha  = grid$true_alpha[i],
                 resid_sd    = grid$resid_sd[i],
                 T_months    = grid$T_months[i],
                 n_reps      = n_reps,
                 market_full = market_full,
                 scenario_id = grid$scenario_id[i])
  })
  do.call(rbind, pieces) # stack all scenarios into one table
}

#Theoretical standard error of alpha-hat
theory_alpha_se <- function(resid_sd, T_months, market_full) {
  m <- tail(market_full, T_months)
  resid_sd * sqrt(1 / T_months + mean(m)^2 / sum((m - mean(m))^2))
}

#Summarise results by scenario
summarise_scenarios <- function(results, market_full) {
  pieces <- lapply(split(results, results$scenario_id), function(d) {
    n <- nrow(d)
    p <- mean(d$detected)
    data.frame(
      scenario_id     = d$scenario_id[1],
      true_alpha      = d$true_alpha[1],
      resid_sd        = d$resid_sd[1],
      T_months        = d$T_months[1],
      n_reps          = n,
      measure         = ifelse(d$true_alpha[1] == 0, "false-positive rate", "power"),
      detection_rate  = p,
      mc_se           = sqrt(p * (1 - p) / n),# Monte Carlo SE of the proportion
      mean_alpha_hat  = mean(d$alpha_hat),
      sd_alpha_hat    = sd(d$alpha_hat), # spread of estimates across funds
      mean_alpha_se   = mean(d$alpha_se), # average reported standard error
      theory_alpha_se = theory_alpha_se(d$resid_sd[1], d$T_months[1], market_full)
    )
  })
  out <- do.call(rbind, pieces)
  rownames(out) <- NULL
  out
}
