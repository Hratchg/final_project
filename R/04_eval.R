# ==============================================================================
# 04_eval.R — Select best model, evaluate on test set, interpretation
# ==============================================================================
# RUBRIC NOTE: Only the best 1-2 models should predict the test set.
# ==============================================================================

library(tidymodels)
library(vip)
library(here)

# (All objects from 01–03 are in the environment)

# ==============================================================================
# 1. SELECT BEST MODEL based on ROC AUC from CV
# ==============================================================================
best_roc <- cv_comparison %>%
  filter(.metric == "roc_auc") %>%
  arrange(desc(mean))

cat("\n>> CV ROC AUC ranking:\n")
print(as.data.frame(best_roc))

best_model_name   <- best_roc$model[1]
second_model_name <- best_roc$model[2]
cat("\n>> Best model:   ", best_model_name, "\n")
cat(">> Second best:  ", second_model_name, "\n")

# ==============================================================================
# 2. FINALIZE BEST MODEL AND FIT ON FULL TRAINING, EVALUATE ON TEST
# ==============================================================================
finalize_and_evaluate <- function(model_name) {
  if (model_name == "Logistic Regression") {
    wf <- logistic_wf
    fit <- last_fit(wf, split = data_split, metrics = class_metrics)
  } else if (model_name == "Elastic Net (glmnet)") {
    best_params <- select_best(glmnet_tune, metric = "roc_auc")
    wf <- finalize_workflow(glmnet_wf, best_params)
    cat(">> glmnet best params — penalty:", best_params$penalty,
        " mixture:", best_params$mixture, "\n")
    fit <- last_fit(wf, split = data_split, metrics = class_metrics)
  } else if (model_name == "Random Forest") {
    best_params <- select_best(rf_tune, metric = "roc_auc")
    wf <- finalize_workflow(rf_wf, best_params)
    cat(">> RF best params — mtry:", best_params$mtry,
        " min_n:", best_params$min_n, "\n")
    fit <- last_fit(wf, split = data_split, metrics = class_metrics)
  } else if (model_name == "XGBoost") {
    best_params <- select_best(xgb_tune, metric = "roc_auc")
    wf <- finalize_workflow(xgb_wf, best_params)
    cat(">> XGB best params — trees:", best_params$trees,
        " learn_rate:", best_params$learn_rate,
        " tree_depth:", best_params$tree_depth,
        " min_n:", best_params$min_n, "\n")
    fit <- last_fit(wf, split = data_split, metrics = class_metrics)
  }
  return(fit)
}

# Evaluate ONLY the best model on the test set (per rubric: best 1-2)
cat("\n>> Evaluating best model on test set...\n")
final_fit <- finalize_and_evaluate(best_model_name)

# ==============================================================================
# 3. TEST SET PERFORMANCE
# ==============================================================================
test_metrics <- collect_metrics(final_fit)
cat("\n>> Test Set Performance (", best_model_name, "):\n")
print(as.data.frame(test_metrics))
write_csv(test_metrics, file.path(OUTPUT_DIR, "test_set_metrics.csv"))

# Also evaluate the second-best model for comparison
cat("\n>> Evaluating second-best model on test set...\n")
second_fit <- finalize_and_evaluate(second_model_name)
second_test_metrics <- collect_metrics(second_fit)
cat("\n>> Test Set Performance (", second_model_name, "):\n")
print(as.data.frame(second_test_metrics))

# Combined test results (only best 2 models, per rubric)
test_comparison <- bind_rows(
  test_metrics %>% mutate(model = best_model_name),
  second_test_metrics %>% mutate(model = second_model_name)
) %>%
  select(model, .metric, .estimate)

test_comparison_wide <- test_comparison %>%
  pivot_wider(names_from = .metric, values_from = .estimate)

cat("\n>> Test Set Comparison (Top 2 Models):\n")
print(as.data.frame(test_comparison_wide))
write_csv(test_comparison_wide, file.path(OUTPUT_DIR, "test_comparison_top2.csv"))

# ==============================================================================
# 4. CONFUSION MATRIX (best model)
# ==============================================================================
test_preds <- collect_predictions(final_fit)
conf_mat_obj <- conf_mat(test_preds, truth = !!sym(TARGET), estimate = .pred_class)
cat("\n>> Confusion Matrix (Best Model — Test Set):\n")
print(conf_mat_obj)

p_conf <- autoplot(conf_mat_obj, type = "heatmap") +
  labs(title = paste("Confusion Matrix —", best_model_name, "(Test Set)")) +
  theme_minimal(base_size = 13)

ggsave(file.path(OUTPUT_DIR, "plot_confusion_matrix.png"),
       p_conf, width = 6, height = 5, dpi = 150)

# ==============================================================================
# 5. ROC CURVE (best model)
# ==============================================================================
pos_class <- levels(test_preds[[TARGET]])[1]
prob_col  <- paste0(".pred_", pos_class)

p_roc <- test_preds %>%
  roc_curve(truth = !!sym(TARGET), !!sym(prob_col)) %>%
  autoplot() +
  labs(title = paste("ROC Curve —", best_model_name, "(Test Set)"),
       subtitle = paste("Positive class:", pos_class)) +
  theme_minimal(base_size = 13)

ggsave(file.path(OUTPUT_DIR, "plot_roc_curve.png"),
       p_roc, width = 7, height = 5, dpi = 150)

# ==============================================================================
# 6. VARIABLE IMPORTANCE
# ==============================================================================
final_fitted <- extract_fit_parsnip(final_fit)

tryCatch({
  p_vip <- vip(final_fitted, num_features = 15) +
    labs(title = paste("Variable Importance —", best_model_name)) +
    theme_minimal(base_size = 12)

  ggsave(file.path(OUTPUT_DIR, "plot_variable_importance.png"),
         p_vip, width = 8, height = 6, dpi = 150)
  cat(">> Variable importance plot saved.\n")
}, error = function(e) {
  cat(">> Could not generate VIP plot:", conditionMessage(e), "\n")
})

# ==============================================================================
# 7. ODDS RATIOS (logistic models only)
# ==============================================================================
if (grepl("Logistic|glmnet|Elastic", best_model_name, ignore.case = TRUE)) {
  tryCatch({
    tidy_model <- tidy(final_fitted)
    odds_ratios <- tidy_model %>%
      mutate(odds_ratio = exp(estimate)) %>%
      arrange(desc(abs(estimate)))
    cat("\n>> Odds Ratios (top 15):\n")
    print(head(as.data.frame(odds_ratios), 15))
    write_csv(odds_ratios, file.path(OUTPUT_DIR, "odds_ratios.csv"))
  }, error = function(e) {
    cat(">> Could not compute odds ratios:", conditionMessage(e), "\n")
  })
}

# ==============================================================================
# 8. TEST SET COMPARISON PLOT (top 2 models only)
# ==============================================================================
p_test_compare <- test_comparison %>%
  ggplot(aes(x = reorder(model, .estimate), y = .estimate, fill = model)) +
  geom_col(alpha = 0.8, show.legend = FALSE) +
  facet_wrap(~ .metric, scales = "free_y", ncol = 2) +
  coord_flip() +
  scale_fill_manual(values = c("#2166AC", "#D6604D")) +
  labs(title = "Test Set Performance (Best Two Models)",
       x = NULL, y = "Metric Value") +
  theme_minimal(base_size = 12)

ggsave(file.path(OUTPUT_DIR, "plot_test_comparison.png"),
       p_test_compare, width = 10, height = 6, dpi = 150)

# ==============================================================================
# 9. SAVE FINAL MODEL OBJECT
# ==============================================================================
saveRDS(final_fit, file.path(OUTPUT_DIR, "final_model_fit.rds"))
cat(">> Final model object saved to output/final_model_fit.rds\n")

cat("\n>> 04_eval.R complete.\n")
