# =============================================================================
# 07_heatmap.R
# Purpose: heatmap of detection rates (false-positive rate / power) by true
#          alpha, track-record length and residual volatility.
# Input:  outputs/tables/scenario_summary.csv  (made by 05_run_simulation.R)
# Output: outputs/figures/heatmap_detection_rates_wide.png and _portrait.png
# =============================================================================

library(ggplot2)# drawing charts
library(dplyr)# mutate() and the |> pipe helpers

summ <- read.csv("outputs/tables/scenario_summary.csv")
stopifnot(nrow(summ) == 27, !anyNA(summ$detection_rate))

# 1. Prepare labels
sd_levels <- sprintf("Residual SD: %d%% per month", c(2, 4, 6))

plot_data <- summ |>
  mutate(
    alpha_label = factor(sprintf("%.1f%%", 100 * true_alpha),
                         levels = c("0.0%", "0.2%", "0.4%")),
    T_label     = factor(T_months, levels = c(36, 60, 120)),
    sd_label    = factor(sprintf("Residual SD: %d%% per month",
                                 round(100 * resid_sd)), levels = sd_levels),
    rate_label  = sprintf("%.1f%%", 100 * detection_rate)
  )

# Quick check: 27 rows, no missing labels
stopifnot(!anyNA(plot_data$alpha_label), !anyNA(plot_data$T_label),
          !anyNA(plot_data$sd_label))

# Plot-building function
caption_text <- paste(
  "SIMULATED fund returns: fund excess return = alpha + 1 x market excess return + normal error (all monthly).",
  "Historical input: US market excess return (Fama/French Mkt-RF), final T months of Jan 2015 - Dec 2024;",
  "source: Kenneth R. French Data Library.",
  "Test: one-sided 5% t-test of H0 alpha <= 0, conventional OLS standard errors.",
  "Bottom row (alpha = 0) shows false-positive rates; other rows show power.",
  "Each cell = 1,000 simulated funds (Monte Carlo SE up to about 1.6 percentage points). Seed 20261101."
)

make_heatmap <- function(ncol_panels, wrap_width) {
  ggplot(plot_data, aes(x = T_label, y = alpha_label, fill = detection_rate)) +
    geom_tile(colour = "white", linewidth = 0.8) +
    geom_text(aes(label = rate_label, colour = detection_rate > 0.45), size = 4) +
    scale_colour_manual(values = c("TRUE" = "white", "FALSE" = "black"),
                        guide = "none") +
    scale_fill_gradient(low = "#deebf7", high = "#08519C", limits = c(0, 1),
                        labels = scales::percent,
                        name = "Share of funds\nflagged as skilled") +
    facet_wrap(~ sd_label, ncol = ncol_panels) +
    labs(
      title    = "Simulated fund returns: how often a 5% one-sided test detects positive alpha",
      subtitle = "By true monthly alpha, track-record length and fund-specific volatility",
      x        = "Track record (months)",
      y        = "True monthly alpha",
      caption  = paste(strwrap(caption_text, width = wrap_width), collapse = "\n")
    ) +
    theme_minimal(base_size = 12) +
    theme(panel.grid   = element_blank(),
          plot.caption = element_text(hjust = 0, size = 8),
          plot.title   = element_text(face = "bold"))
}

# Build and save two layouts 
p_wide     <- make_heatmap(ncol_panels = 3, wrap_width = 140)   # for reports
p_portrait <- make_heatmap(ncol_panels = 1, wrap_width = 75)    # for a carousel slide

ggsave("outputs/figures/heatmap_detection_rates_wide.png", p_wide,
       width = 12, height = 5.5, dpi = 300, bg = "white")
ggsave("outputs/figures/heatmap_detection_rates_portrait.png", p_portrait,
       width = 8, height = 10, dpi = 300, bg = "white")

p_wide      # shows the wide version in the RStudio Plots pane