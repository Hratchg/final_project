# ==============================================================================
# run_all.R — Renders the report (all code is inside the Rmd)
# ==============================================================================
# USAGE:
#   1. Open final_project.Rproj in RStudio
#   2. Install packages if needed (see setup_renv.R)
#   3. source("run_all.R")
# ==============================================================================

library(here)

cat("================================================================\n")
cat("  FINAL PROJECT — Rendering Report\n")
cat("================================================================\n\n")

# Render HTML
cat(">> Rendering HTML...\n")
rmarkdown::render(
  input         = here("report", "final_report.Rmd"),
  output_format = "html_document",
  output_file   = here("report", "final_report.html"),
  quiet         = FALSE
)
cat(">> HTML saved to report/final_report.html\n")

# Render PDF
cat("\n>> Rendering PDF...\n")
tryCatch({
  rmarkdown::render(
    input         = here("report", "final_report.Rmd"),
    output_format = "pdf_document",
    output_file   = here("report", "final_report.pdf"),
    quiet         = TRUE
  )
  cat(">> PDF saved to report/final_report.pdf\n")
}, error = function(e) {
  cat(">> PDF failed:", conditionMessage(e), "\n")
  cat(">> Fix: run tinytex::install_tinytex() then re-run.\n")
})

# Render codebook
cat("\n>> Rendering codebook...\n")
rmarkdown::render(
  input       = here("codebook", "codebook.Rmd"),
  output_file = here("codebook", "codebook.html"),
  quiet       = TRUE
)
cat(">> Codebook saved to codebook/codebook.html\n")

cat("\n================================================================\n")
cat("  DONE — Check report/ and codebook/ folders\n")
cat("================================================================\n")
