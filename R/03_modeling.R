# ==============================================================================
# 03_modeling.R — Data splitting, recipe, 4 models, cross-validation + tuning
# ==============================================================================

library(tidymodels)
library(glmnet)
library(ranger)
library(xgboost)
library(vip)
library(here)

tidymodels_prefer()
set.seed(SEED)

# (clean_data, TARGET, numeric_preds, factor_preds are in the environment)

# ==============================================================================
# 1. DATA SPLITTING — stratified on the outcome
# ==============================================================================
data_split <- initial_split(clean_data, prop = TRAIN_PROP, strata = all_of(TARGET))
train_data <- training(data_split)
test_data  <- testing(data_split)

cat(">> Training set:", nrow(train_data), "rows\n")
cat(">> Test set:    ", nrow(test_data), "rows\n")
cat(">> Training outcome distribution:\n")
print(table(train_data[[TARGET]]))

# ==============================================================================
# 2. CROSS-VALIDATION FOLDS (on training data only)
# ==============================================================================
set.seed(SEED)
cv_folds <- vfold_cv(train_data, v = CV_FOLDS, strata = all_of(TARGET))
cat(">> Created", CV_FOLDS, "-fold stratified CV\n")

# ==============================================================================
# 3. PREPROCESSING RECIPE
# ==============================================================================
model_formula <- as.formula(paste(TARGET, "~ ."))

base_recipe <- recipe(model_formula, data = train_data) %>%
  step_impute_median(all_numeric_predictors()) %>%
  step_impute_mode(all_nominal_predictors()) %>%
  step_dummy(all_nominal_predictors(), one_hot = FALSE) %>%
  step_zv(all_predictors()) %>%
  step_corr(all_numeric_predictors(), threshold = 0.90) %>%
  step_normalize(all_numeric_predictors())

cat(">> Recipe created: impute -> dummy -> zv -> corr(0.90) -> normalize\n")

# ==============================================================================
# 4. MODEL SPECIFICATIONS (4 models required by rubric)
# ==============================================================================

# Model 1: Standard logistic regression (no tuning)
logistic_spec <- logistic_reg() %>%
  set_engine("glm") %>%
  set_mode("classification")

# Model 2: Regularized logistic regression (tune penalty + mixture)
glmnet_spec <- logistic_reg(
  penalty = tune(),
  mixture = tune()
) %>%
  set_engine("glmnet") %>%
  set_mode("classification")

# Model 3: Random forest (tune mtry + min_n)
rf_spec <- rand_forest(
  mtry  = tune(),
  min_n = tune(),
  trees = RF_TREES
) %>%
  set_engine("ranger", importance = "impurity") %>%
  set_mode("classification")

# Model 4: Boosted trees / XGBoost (tune trees, learn_rate, tree_depth)
xgb_spec <- boost_tree(
  trees      = tune(),
  learn_rate = tune(),
  tree_depth = tune(),
  min_n      = tune()
) %>%
  set_engine("xgboost") %>%
  set_mode("classification")

# ==============================================================================
# 5. WORKFLOWS
# ==============================================================================
logistic_wf <- workflow() %>% add_recipe(base_recipe) %>% add_model(logistic_spec)
glmnet_wf   <- workflow() %>% add_recipe(base_recipe) %>% add_model(glmnet_spec)
rf_wf       <- workflow() %>% add_recipe(base_recipe) %>% add_model(rf_spec)
xgb_wf      <- workflow() %>% add_recipe(base_recipe) %>% add_model(xgb_spec)

# ==============================================================================
# 6. EVALUATION METRICS
# ==============================================================================
class_metrics <- metric_set(accuracy, roc_auc, sensitivity, specificity)

# ==============================================================================
# 7. FIT / TUNE MODELS VIA CROSS-VALIDATION
# ==============================================================================

# 7a. Logistic regression (no tuning)
cat("\n>> [1/4] Fitting logistic regression via CV...\n")
set.seed(SEED)
logistic_cv <- fit_resamples(
  logistic_wf,
  resamples = cv_folds,
  metrics   = class_metrics,
  control   = control_resamples(save_pred = TRUE)
)

# 7b. Regularized logistic regression (tune penalty + mixture)
cat(">> [2/4] Tuning elastic net (glmnet)...\n")
set.seed(SEED)
glmnet_grid <- grid_latin_hypercube(
  penalty(),
  mixture(),
  size = GLMNET_GRID_SIZE
)

set.seed(SEED)
glmnet_tune <- tune_grid(
  glmnet_wf,
  resamples = cv_folds,
  grid      = glmnet_grid,
  metrics   = class_metrics,
  control   = control_grid(save_pred = TRUE)
)

# 7c. Random forest (tune mtry + min_n)
cat(">> [3/4] Tuning random forest (ranger)...\n")
prepped <- prep(base_recipe)
n_preds <- ncol(bake(prepped, new_data = NULL)) - 1

set.seed(SEED)
rf_grid <- grid_latin_hypercube(
  mtry(range = c(2L, max(2L, n_preds))),
  min_n(),
  size = RF_GRID_SIZE
)

set.seed(SEED)
rf_tune <- tune_grid(
  rf_wf,
  resamples = cv_folds,
  grid      = rf_grid,
  metrics   = class_metrics,
  control   = control_grid(save_pred = TRUE)
)

# 7d. XGBoost (tune trees, learn_rate, tree_depth, min_n)
cat(">> [4/4] Tuning XGBoost...\n")
set.seed(SEED)
xgb_grid <- grid_latin_hypercube(
  trees(range = c(100L, 800L)),
  learn_rate(range = c(-3, -1)),   # 0.001 to 0.1
  tree_depth(range = c(3L, 10L)),
  min_n(range = c(5L, 40L)),
  size = XGB_GRID_SIZE
)

set.seed(SEED)
xgb_tune <- tune_grid(
  xgb_wf,
  resamples = cv_folds,
  grid      = xgb_grid,
  metrics   = class_metrics,
  control   = control_grid(save_pred = TRUE)
)

# ==============================================================================
# 8. COLLECT AND COMPARE CV RESULTS
# ==============================================================================

# Helper: extract best metric row for tuned models
best_metric_row <- function(tune_result, model_name) {
  metrics <- c("roc_auc", "accuracy", "sensitivity", "specificity")
  map_dfr(metrics, ~ show_best(tune_result, metric = .x, n = 1)) %>%
    distinct(.metric, .keep_all = TRUE) %>%
    mutate(model = model_name)
}

logistic_metrics <- collect_metrics(logistic_cv) %>%
  mutate(model = "Logistic Regression")
glmnet_metrics  <- best_metric_row(glmnet_tune, "Elastic Net")
rf_metrics      <- best_metric_row(rf_tune, "Random Forest")
xgb_metrics     <- best_metric_row(xgb_tune, "XGBoost")

cv_comparison <- bind_rows(
  logistic_metrics %>% select(model, .metric, mean, std_err),
  glmnet_metrics  %>% select(model, .metric, mean, std_err),
  rf_metrics      %>% select(model, .metric, mean, std_err),
  xgb_metrics     %>% select(model, .metric, mean, std_err)
) %>%
  distinct(model, .metric, .keep_all = TRUE) %>%
  arrange(.metric, desc(mean))

cat("\n>> Cross-Validation Results Summary:\n")
print(as.data.frame(cv_comparison))
write_csv(cv_comparison, file.path(OUTPUT_DIR, "cv_comparison.csv"))

# ==============================================================================
# 9. CV COMPARISON PLOT
# ==============================================================================
p_cv <- cv_comparison %>%
  ggplot(aes(x = reorder(model, mean), y = mean, fill = model)) +
  geom_col(alpha = 0.8, show.legend = FALSE) +
  geom_errorbar(aes(ymin = mean - std_err, ymax = mean + std_err), width = 0.2) +
  facet_wrap(~ .metric, scales = "free_y", ncol = 2) +
  coord_flip() +
  scale_fill_manual(values = c("#2166AC", "#4393C3", "#D6604D", "#F4A582")) +
  labs(title = "Cross-Validation Performance Comparison (4 Models)",
       x = NULL, y = "Metric Value") +
  theme_minimal(base_size = 12)

ggsave(file.path(OUTPUT_DIR, "plot_cv_comparison.png"),
       p_cv, width = 10, height = 7, dpi = 150)

cat("\n>> 03_modeling.R complete.\n")
