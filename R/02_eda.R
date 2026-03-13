# ==============================================================================
# 02_eda.R — Exploratory Data Analysis
# ==============================================================================

library(tidyverse)
library(corrplot)
library(here)

# (clean_data, TARGET, OUTPUT_DIR, miss_summary are in the environment)

if (!dir.exists(OUTPUT_DIR)) dir.create(OUTPUT_DIR, recursive = TRUE)

# --- Identify predictor types -------------------------------------------------
numeric_preds <- clean_data %>%
  select(-all_of(TARGET)) %>%
  select(where(is.numeric)) %>%
  names()

factor_preds <- clean_data %>%
  select(-all_of(TARGET)) %>%
  select(where(is.factor)) %>%
  names()

cat(">> Numeric predictors:", length(numeric_preds), "\n")
cat(">> Factor predictors:", length(factor_preds), "\n")

# ==============================================================================
# PLOT 1: Outcome class balance
# ==============================================================================
p_balance <- clean_data %>%
  ggplot(aes(x = .data[[TARGET]], fill = .data[[TARGET]])) +
  geom_bar(alpha = 0.85, show.legend = FALSE) +
  geom_text(stat = "count", aes(label = after_stat(count)), vjust = -0.5) +
  scale_fill_manual(values = c("#2166AC", "#B2182B")) +
  labs(
    title = "Outcome Class Balance",
    subtitle = paste("Target variable:", TARGET),
    x = TARGET, y = "Count"
  ) +
  theme_minimal(base_size = 13)

ggsave(file.path(OUTPUT_DIR, "plot_class_balance.png"),
       p_balance, width = 6, height = 4, dpi = 150)

# ==============================================================================
# PLOT 2: Distributions of key numeric predictors (top 8 by variance)
# ==============================================================================
if (length(numeric_preds) > 0) {
  top_vars <- clean_data %>%
    select(all_of(numeric_preds)) %>%
    summarise(across(everything(), ~ var(., na.rm = TRUE))) %>%
    pivot_longer(everything()) %>%
    arrange(desc(value)) %>%
    slice_head(n = min(8, length(numeric_preds))) %>%
    pull(name)

  p_dist <- clean_data %>%
    select(all_of(top_vars)) %>%
    pivot_longer(everything(), names_to = "variable", values_to = "value") %>%
    ggplot(aes(x = value)) +
    geom_histogram(bins = 30, fill = "#4393C3", color = "white", alpha = 0.8) +
    facet_wrap(~ variable, scales = "free", ncol = 2) +
    labs(title = "Distributions of Top Numeric Predictors (by Variance)",
         x = "Value", y = "Frequency") +
    theme_minimal(base_size = 11)

  ggsave(file.path(OUTPUT_DIR, "plot_distributions.png"),
         p_dist, width = 10, height = 8, dpi = 150)
}

# ==============================================================================
# PLOT 3: Correlation heatmap
# ==============================================================================
if (length(numeric_preds) >= 2) {
  corr_vars <- if (length(numeric_preds) > 20) {
    outcome_numeric <- as.numeric(clean_data[[TARGET]]) - 1
    cors <- sapply(numeric_preds, function(v) {
      abs(cor(clean_data[[v]], outcome_numeric, use = "complete.obs"))
    })
    names(sort(cors, decreasing = TRUE))[1:20]
  } else {
    numeric_preds
  }

  corr_mat <- clean_data %>%
    select(all_of(corr_vars)) %>%
    cor(use = "pairwise.complete.obs")

  png(file.path(OUTPUT_DIR, "plot_correlation_heatmap.png"),
      width = 900, height = 800, res = 120)
  corrplot(corr_mat, method = "color", type = "upper", order = "hclust",
           tl.cex = 0.7, tl.col = "black",
           title = "Correlation Heatmap (Numeric Predictors)",
           mar = c(0, 0, 2, 0))
  dev.off()
}

# ==============================================================================
# PLOT 4: Boxplots of top predictors by outcome
# ==============================================================================
if (length(numeric_preds) > 0) {
  outcome_numeric <- as.numeric(clean_data[[TARGET]]) - 1
  cors <- sapply(numeric_preds, function(v) {
    abs(cor(clean_data[[v]], outcome_numeric, use = "complete.obs"))
  })
  top6 <- names(sort(cors, decreasing = TRUE))[1:min(6, length(cors))]

  p_box <- clean_data %>%
    select(all_of(c(TARGET, top6))) %>%
    pivot_longer(-all_of(TARGET), names_to = "variable", values_to = "value") %>%
    ggplot(aes(x = .data[[TARGET]], y = value, fill = .data[[TARGET]])) +
    geom_boxplot(alpha = 0.7, outlier.size = 0.5) +
    scale_fill_manual(values = c("#2166AC", "#B2182B")) +
    facet_wrap(~ variable, scales = "free_y", ncol = 3) +
    labs(title = "Top Predictors by Outcome",
         subtitle = "Ranked by absolute correlation with outcome",
         x = TARGET, y = "Value") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "none")

  ggsave(file.path(OUTPUT_DIR, "plot_boxplots_by_outcome.png"),
         p_box, width = 10, height = 7, dpi = 150)
}

# ==============================================================================
# PLOT 5: Missingness visualization (if any)
# ==============================================================================
if (nrow(miss_summary) > 0) {
  p_miss <- miss_summary %>%
    ggplot(aes(x = reorder(column, n_missing), y = pct_missing)) +
    geom_col(fill = "#D6604D", alpha = 0.8) +
    coord_flip() +
    labs(title = "Percentage of Missing Values by Column",
         x = "Column", y = "% Missing") +
    theme_minimal(base_size = 12)

  ggsave(file.path(OUTPUT_DIR, "plot_missingness.png"),
         p_miss, width = 8, height = 5, dpi = 150)
}

# ==============================================================================
# TABLE: Summary statistics
# ==============================================================================
if (length(numeric_preds) > 0) {
  eda_summary_table <- clean_data %>%
    select(all_of(numeric_preds)) %>%
    pivot_longer(everything(), names_to = "Variable", values_to = "Value") %>%
    group_by(Variable) %>%
    summarise(
      Mean   = round(mean(Value, na.rm = TRUE), 2),
      SD     = round(sd(Value, na.rm = TRUE), 2),
      Median = round(median(Value, na.rm = TRUE), 2),
      Min    = round(min(Value, na.rm = TRUE), 2),
      Max    = round(max(Value, na.rm = TRUE), 2),
      N_Miss = sum(is.na(Value)),
      .groups = "drop"
    ) %>%
    arrange(Variable)

  write_csv(eda_summary_table, file.path(OUTPUT_DIR, "eda_summary_stats.csv"))
}

cat(">> 02_eda.R complete. Plots saved to", OUTPUT_DIR, "\n")
