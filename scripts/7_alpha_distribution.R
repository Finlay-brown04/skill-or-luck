# =============================================================================
# 08_alpha_distribution.R
# Purpose: compare the distribution of ESTIMATED monthly alpha for zero-alpha
#          and positive-alpha SIMULATED funds, same track record and volatility.
# Input:  data/processed/simulation_replications.csv (from 05_run_simulation.R)
# Output: outputs/figures/alpha_distribution_sd<SD>_wide.png and _portrait.png
# =============================================================================

library(ggplot2)
library(dplyr)       # R may print a note that filter/lag mask stats functions: harmless

# ---- 1. Choices (change sd_chosen to 0.02 or 0.06 to see other volatilities) -
sd_chosen   <- 0.04
alpha_skill <- 0.004
sd_pct      <- round(100 * sd_chosen)

sim <- read.csv("data/processed/simulation_replications.csv")
stopifnot(nrow(sim) == 27000)

group_levels <- c("True alpha = 0% (no skill)",
                  "True alpha = 0.4% a month (skilled in this model)")

# ---- 2. Select the funds to plot --------------------------------------------
dat <- sim |>
  filter(round(resid_sd, 6) == sd_chosen,
         round(true_alpha, 6) %in% c(0, alpha_skill)) |>
  mutate(
    alpha_hat_pct = 100 * alpha_hat,     # estimated alpha in % per month
    group   = factor(ifelse(round(true_alpha, 6) == 0, group_levels[1],
                            group_levels[2]), levels = group_levels),
    T_label = factor(paste0(T_months, "-month record"),
                     levels = paste0(c(36, 60, 120), "-month record"))
  )
stopifnot(nrow(dat) == 6000)             # 3 lengths x 2 alphas x 1,000 funds
stopifnot(!anyNA(dat$group), !anyNA(dat$T_label))

# ---- 3. Numbers behind the picture ------------------------------------------
spread <- dat |>
  group_by(T_months, group) |>
  summarise(n = n(),
            mean_alpha_pct = mean(alpha_hat_pct),
            sd_alpha_pct   = sd(alpha_hat_pct),
            .groups = "drop")
print(as.data.frame(spread), digits = 3)

# How much do the two groups overlap?
overlap <- dat |>
  group_by(T_months) |>
  summarise(
    skilled_negative_estimate = mean(alpha_hat[round(true_alpha, 6) == alpha_skill] < 0),
    noskill_estimate_above_04 = mean(alpha_hat[round(true_alpha, 6) == 0] >= alpha_skill),
    .groups = "drop")
print(as.data.frame(overlap), digits = 3)

# ---- 4. Chart ---------------------------------------------------------------
cols <- c("#7A7A7A", "#08519C")
names(cols) <- group_levels

truth <- data.frame(group = factor(group_levels, levels = group_levels),
                    true_alpha_pct = c(0, 100 * alpha_skill))

caption_text <- sprintf(paste(
  "SIMULATED fund returns: fund excess return = alpha + 1 x market excess return + normal error",
  "(monthly; residual SD %d%% a month).",
  "Historical input: US market excess return (Fama/French Mkt-RF), final T months of",
  "Jan 2015 - Dec 2024; source: Kenneth R. French Data Library.",
  "Each curve is a smoothed distribution of 1,000 estimated alphas (OLS intercepts);",
  "dashed lines mark the true alpha used to simulate each group.",
  "Monthly alpha, not annualised. Seed 20261101."), sd_pct)

make_dist_chart <- function(ncol_panels, wrap_width) {
  ggplot(dat, aes(x = alpha_hat_pct, fill = group, colour = group)) +
    geom_density(alpha = 0.35, linewidth = 0.6) +
    geom_vline(data = truth, aes(xintercept = true_alpha_pct, colour = group),
               linetype = "dashed", linewidth = 0.8, show.legend = FALSE) +
    scale_fill_manual(values = cols, name = NULL) +
    scale_colour_manual(values = cols, name = NULL) +
    scale_x_continuous(labels = function(x) paste0(x, "%")) +
    facet_wrap(~ T_label, ncol = ncol_panels) +
    labs(
      title    = "Simulated fund returns: estimated monthly alpha, with and without true skill",
      subtitle = sprintf("1,000 simulated funds per group; residual SD %d%% a month; dashed lines = true alpha", sd_pct),
      x        = "Estimated monthly alpha (% per month)",
      y        = "Relative frequency of simulated funds",
      caption  = paste(strwrap(caption_text, width = wrap_width), collapse = "\n")
    ) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "bottom",
          axis.text.y     = element_blank(),
          panel.grid.minor = element_blank(),
          plot.caption    = element_text(hjust = 0, size = 8),
          plot.title      = element_text(face = "bold"),
          strip.text      = element_text(face = "bold"))
}

p_wide     <- make_dist_chart(ncol_panels = 3, wrap_width = 140)
p_portrait <- make_dist_chart(ncol_panels = 1, wrap_width = 75)

ggsave(sprintf("outputs/figures/alpha_distribution_sd%d_wide.png", sd_pct),
       p_wide, width = 12, height = 5, dpi = 300, bg = "white")
ggsave(sprintf("outputs/figures/alpha_distribution_sd%d_portrait.png", sd_pct),
       p_portrait, width = 8, height = 10, dpi = 300, bg = "white")

p_wide