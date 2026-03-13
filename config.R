# ==============================================================================
# config.R — Central configuration for the entire project
# ==============================================================================
# Change settings here; every script and the Rmd source this file.

# --- Reproducibility seed (used everywhere) ----------------------------------
SEED <- 42
set.seed(SEED)

# --- File paths ---------------------------------------------------------------
DATA_DIR    <- here::here("data")
OUTPUT_DIR  <- here::here("output")
REPORT_DIR  <- here::here("report")

# Raw Kaggle files (place these in /data after downloading)
MATCHES_FILE    <- file.path(DATA_DIR, "matches.csv")
TEAMSTATS_FILE  <- file.path(DATA_DIR, "teamstats.csv")
STATS1_FILE     <- file.path(DATA_DIR, "stats1.csv")
STATS2_FILE     <- file.path(DATA_DIR, "stats2.csv")
PARTICIPANTS_FILE <- file.path(DATA_DIR, "participants.csv")
CHAMPS_FILE     <- file.path(DATA_DIR, "champs.csv")

# Prepared (merged) dataset — created by 00_prepare_data.R
PREPARED_FILE   <- file.path(DATA_DIR, "prepared_data.csv")

# --- Target column ------------------------------------------------------------
# The outcome column in the prepared dataset.
# After merging, each row is one team in one match, and "win" is 1/0.
TARGET_COL <- "win"

# --- Columns to EXCLUDE (potential data-leakage proxies) ----------------------
# These are removed AFTER merging to prevent leakage.
LEAKAGE_COLS <- c()

# --- Sampling (for large datasets) --------------------------------------------
# Set to NULL to use all data, or a number (e.g., 50000) for faster runs.
# The full dataset is ~360K rows. Using all data gives best results but tuning
# 4 models with 10-fold CV can take 30-60+ minutes on a laptop.
# Recommendation: set to 50000 for testing, NULL for the final submission run.
SAMPLE_N <- NULL

# --- Modeling settings --------------------------------------------------------
TRAIN_PROP  <- 0.75        # proportion for training split
CV_FOLDS    <- 10          # number of cross-validation folds
RF_TREES    <- 500         # number of trees for random forest
XGB_TREES   <- 500         # number of trees for xgboost

# --- Tuning grid sizes --------------------------------------------------------
GLMNET_GRID_SIZE <- 20     # grid points for regularized logistic regression
RF_GRID_SIZE     <- 15     # grid points for random forest
XGB_GRID_SIZE    <- 20     # grid points for xgboost

cat(">> config.R loaded successfully.\n")
