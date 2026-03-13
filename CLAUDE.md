# PSTAT 131/231 Final Project — League of Legends Match Prediction

## Project Overview
Binary classification project predicting League of Legends ranked match outcomes (Win/Loss) using in-game performance statistics. Built with R and the tidymodels framework.

## Sole Deliverable
**`report/final_report.Rmd`** is the only file being submitted. It is fully self-contained — it does NOT depend on `config.R` or any R scripts in `R/`. It defines its own config, loads raw CSVs, and runs all 4 models internally.

## Models (4 total)
1. Logistic Regression (baseline)
2. Elastic Net (regularized logistic regression, `glmnet`)
3. Random Forest (`ranger`, 500 trees)
4. XGBoost (`xgboost`)

All use 10-fold cross-validation with stratified sampling. Hyperparameter tuning via `tune_grid()`.

## Key Configuration (in final_report.Rmd)
- `SEED = 42`
- `TRAIN_PROP = 0.75`
- `CV_FOLDS = 10`
- `GLMNET_GRID = 20`, `RF_GRID = 15`, `XGB_GRID = 20`
- `SAMPLE_N = NULL` (uses all ~360K rows for final run)

## Project Structure
```
final_project/
├── report/
│   └── final_report.Rmd    # SOLE DELIVERABLE — self-contained
├── data/
│   ├── matches.csv          # Raw Kaggle files (6 CSVs)
│   ├── participants.csv
│   ├── stats1.csv
│   ├── stats2.csv
│   ├── teambans.csv
│   ├── teamstats.csv
│   ├── champs.csv
│   └── prepared_data.csv    # Cached merged dataset
├── R/                       # Standalone scripts (NOT submitted)
│   ├── 00_prepare_data.R
│   ├── 01_load_clean.R
│   ├── 02_eda.R
│   ├── 03_modeling.R
│   └── 04_eval.R
├── config.R                 # Central config (used by R/ scripts only)
├── output/                  # EDA plots and summaries
├── renv/                    # R package management
├── renv.lock
├── final_project.Rproj
└── CLAUDE.md
```

## Data Source
> Paololol. (2018). *League of Legends Ranked Matches.* Kaggle.
> https://www.kaggle.com/datasets/paololol/league-of-legends-ranked-matches

## Required R Packages
tidyverse, tidymodels, glmnet, ranger, xgboost, vip, corrplot, here, rmarkdown, knitr

## How to Knit
1. Open `final_project.Rproj` in RStudio
2. Install packages: `install.packages(c("tidyverse", "tidymodels", "glmnet", "ranger", "xgboost", "vip", "corrplot", "here", "rmarkdown", "knitr"))`
3. Knit: `rmarkdown::render("report/final_report.Rmd")`
4. Output: `report/final_report.html`
