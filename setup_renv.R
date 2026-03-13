# ==============================================================================
# setup_renv.R — Run ONCE to initialize renv and install all packages
# ==============================================================================
#
# USAGE: Open final_project.Rproj, then:
#   source("setup_renv.R")
# ==============================================================================

if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
renv::init(bare = TRUE)

packages <- c(
  "tidyverse",
  "tidymodels",
  "glmnet",
  "ranger",
  "xgboost",
  "vip",
  "corrplot",
  "here",
  "rmarkdown",
  "knitr",
  "tinytex"
)

renv::install(packages)
renv::snapshot()

if (!tinytex::is_tinytex()) {
  cat("\n>> Installing TinyTeX for PDF rendering (may take a few minutes)...\n")
  tinytex::install_tinytex()
} else {
  cat(">> TinyTeX is already installed.\n")
}

cat("\n======================================================\n")
cat("  Setup complete! Now run:\n")
cat("    source('run_all.R')\n")
cat("======================================================\n")
