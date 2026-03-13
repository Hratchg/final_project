# ==============================================================================
# 01_load_clean.R — Load prepared data, validate outcome, clean, report missing
# ==============================================================================

library(tidyverse)
library(here)

source(here("config.R"))

# --- 1. Load prepared data ----------------------------------------------------
if (!file.exists(PREPARED_FILE)) {
  stop("Prepared data not found at: ", PREPARED_FILE,
       "\nRun R/00_prepare_data.R first (or run_all.R).")
}

clean_data <- read_csv(PREPARED_FILE, show_col_types = FALSE)
cat("\n>> Dataset loaded:", nrow(clean_data), "rows x", ncol(clean_data), "columns.\n")

# Optional: sample down for faster runs (set SAMPLE_N in config.R)
if (!is.null(SAMPLE_N) && SAMPLE_N < nrow(clean_data)) {
  set.seed(SEED)
  clean_data <- clean_data %>% slice_sample(n = SAMPLE_N)
  cat(">> Sampled down to", SAMPLE_N, "rows (set SAMPLE_N <- NULL for full data).\n")
}

cat(">> Column names:\n")
cat(paste(" ", names(clean_data)), sep = "\n")

# --- 2. Validate the target column exists -------------------------------------
TARGET <- TARGET_COL
if (!TARGET %in% names(clean_data)) {
  # Fallback: auto-detect
  candidates <- c("win", "won", "victory", "result", "outcome",
                   "bluewins", "redwins", "team_win", "blueWins")
  col_lower <- tolower(names(clean_data))
  matches <- which(col_lower %in% tolower(candidates))
  if (length(matches) > 0) {
    TARGET <- names(clean_data)[matches[1]]
    cat("\n>> Auto-detected target column:", TARGET, "\n")
  } else {
    stop("Target column '", TARGET_COL, "' not found. Available columns:\n",
         paste(names(clean_data), collapse = ", "))
  }
}

# --- 3. Convert outcome to factor ---------------------------------------------
outcome_vals <- unique(na.omit(clean_data[[TARGET]]))
cat("\n>> Outcome unique values:", paste(sort(outcome_vals), collapse = ", "), "\n")

if (is.numeric(clean_data[[TARGET]])) {
  clean_data <- clean_data %>%
    mutate(!!TARGET := factor(
      .data[[TARGET]],
      levels = c(1, 0),
      labels = c("Win", "Loss")
    ))
}

cat(">> Outcome distribution:\n")
print(table(clean_data[[TARGET]]))

# --- 4. Remove potential leakage columns --------------------------------------
# Auto-detect columns that look like outcome proxies
suspect_leak <- grep("win|loss|result|victory|defeat", names(clean_data),
                     ignore.case = TRUE, value = TRUE)
suspect_leak <- setdiff(suspect_leak, TARGET)

# Also remove user-specified leakage columns
suspect_leak <- union(suspect_leak, LEAKAGE_COLS)

if (length(suspect_leak) > 0) {
  cat("\n>> Removing potential leakage columns:", paste(suspect_leak, collapse = ", "), "\n")
  clean_data <- clean_data %>% select(-all_of(intersect(suspect_leak, names(clean_data))))
}

# --- 5. Remove ID-like columns ------------------------------------------------
id_cols <- names(clean_data)[sapply(clean_data, function(x) {
  is.character(x) && n_distinct(x) > 0.9 * nrow(clean_data)
})]
if (length(id_cols) > 0) {
  cat(">> Dropping ID-like columns:", paste(id_cols, collapse = ", "), "\n")
  clean_data <- clean_data %>% select(-all_of(id_cols))
}

# Convert low-cardinality character columns to factors
clean_data <- clean_data %>%
  mutate(across(where(~ is.character(.) && n_distinct(.) <= 30), as.factor))

# --- 6. Report missingness ----------------------------------------------------
miss_summary <- clean_data %>%
  summarise(across(everything(), ~ sum(is.na(.)))) %>%
  pivot_longer(everything(), names_to = "column", values_to = "n_missing") %>%
  mutate(pct_missing = round(100 * n_missing / nrow(clean_data), 2)) %>%
  filter(n_missing > 0) %>%
  arrange(desc(n_missing))

if (nrow(miss_summary) == 0) {
  cat("\n>> No missing values detected in any column.\n")
} else {
  cat("\n>> Missingness report:\n")
  print(as.data.frame(miss_summary))
}

# --- 7. Summary ---------------------------------------------------------------
cat("\n>> Cleaned dataset:", nrow(clean_data), "rows x", ncol(clean_data), "columns.\n")
pred_cols <- setdiff(names(clean_data), TARGET)
cat(">> Predictor count:", length(pred_cols), "\n")

cat("\n>> 01_load_clean.R complete.\n")
