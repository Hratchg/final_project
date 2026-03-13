# ==============================================================================
# 00_prepare_data.R — Merge raw Kaggle files into one analysis-ready dataset
# ==============================================================================
#
# The Kaggle "League of Legends Ranked Matches" dataset is distributed across
# six CSV files, each at a different level of aggregation and using different
# keys. A substantial portion of this project's work is combining them into a
# single, clean modeling table.
#
# Raw files:
#   matches.csv       — match metadata (id, duration, season, version)
#   teamstats.csv     — team-level first-objective flags + objective counts
#                        (keyed by matchid + teamid: 100 or 200)
#   participants.csv  — links players to matches (id, matchid, player 1-10)
#   stats1.csv        — per-player stats (first half)
#   stats2.csv        — per-player stats (second half, same columns)
#   champs.csv        — champion id-to-name lookup (not used in modeling)
#   teambans.csv      — ban data (not used in modeling)
#
# Join logic:
#   1. Combine stats1 + stats2 (same schema, just split for file size)
#   2. Join stats to participants on: participants.id = stats.id
#      This gives us per-player stats with matchid and player number.
#   3. Derive teamid from player number: players 1-5 = team 100, 6-10 = team 200
#   4. Extract win/loss from the per-player stats (win column: 0 or 1)
#   5. Aggregate player stats to team level (sum kills, gold, etc.)
#   6. Join with teamstats on (matchid, teamid) for objective data
#   7. Join with matches on matchid for duration/season metadata
#   8. Drop identifiers (matchid, teamid) — they are not predictors
#
# Output: data/prepared_data.csv — one row per team per match
# ==============================================================================

library(tidyverse)
library(here)

source(here("config.R"))

# --- Check if prepared data already exists ------------------------------------
if (file.exists(PREPARED_FILE)) {
  cat(">> Prepared data already exists at:", PREPARED_FILE, "\n")
  cat(">> To regenerate, delete it and re-run this script.\n")
  prepared_data <- read_csv(PREPARED_FILE, show_col_types = FALSE)
  cat(">> Loaded:", nrow(prepared_data), "rows x", ncol(prepared_data), "cols.\n")

} else {

  # ============================================================================
  # STEP 0: Verify all required raw files are present
  # ============================================================================
  stats1_file <- file.path(DATA_DIR, "stats1.csv")
  stats2_file <- file.path(DATA_DIR, "stats2.csv")

  required <- c(MATCHES_FILE, TEAMSTATS_FILE, PARTICIPANTS_FILE, stats1_file)
  missing  <- required[!file.exists(required)]
  if (length(missing) > 0) {
    stop(
      "\n>> MISSING FILES:\n", paste("  ", missing, collapse = "\n"),
      "\n\n>> Download from:\n",
      "   https://www.kaggle.com/datasets/paololol/league-of-legends-ranked-matches\n",
      ">> Extract all CSVs into the data/ folder.\n"
    )
  }

  # ============================================================================
  # STEP 1: Load all raw files
  # ============================================================================
  cat(">> [Step 1/7] Loading raw files...\n")

  matches <- read_csv(MATCHES_FILE, show_col_types = FALSE)
  cat("   matches.csv:      ", nrow(matches), "rows x", ncol(matches), "cols\n")
  cat("   Columns:", paste(names(matches), collapse = ", "), "\n")

  teamstats <- read_csv(TEAMSTATS_FILE, show_col_types = FALSE)
  cat("   teamstats.csv:    ", nrow(teamstats), "rows x", ncol(teamstats), "cols\n")
  cat("   Columns:", paste(names(teamstats), collapse = ", "), "\n")

  participants <- read_csv(PARTICIPANTS_FILE, show_col_types = FALSE)
  cat("   participants.csv: ", nrow(participants), "rows x", ncol(participants), "cols\n")

  stats1 <- read_csv(stats1_file, show_col_types = FALSE)
  cat("   stats1.csv:       ", nrow(stats1), "rows x", ncol(stats1), "cols\n")

  stats2 <- NULL
  if (file.exists(stats2_file)) {
    stats2 <- read_csv(stats2_file, show_col_types = FALSE)
    cat("   stats2.csv:       ", nrow(stats2), "rows x", ncol(stats2), "cols\n")
  }

  # ============================================================================
  # STEP 2: Combine stats1 + stats2
  # ============================================================================
  # The two stats files have identical schemas but were split for file size.
  # Some columns may have been inferred as different types (e.g., a column that
  # is all-numeric in stats1 may have a stray non-numeric value in stats2,
  # causing readr to parse it as character). We coerce to match stats1 types.
  cat("\n>> [Step 2/7] Combining stats files...\n")

  if (!is.null(stats2)) {
    shared_cols <- intersect(names(stats1), names(stats2))
    mismatches <- c()
    for (col in shared_cols) {
      if (is.numeric(stats1[[col]]) && !is.numeric(stats2[[col]])) {
        stats2[[col]] <- suppressWarnings(as.numeric(stats2[[col]]))
        mismatches <- c(mismatches, col)
      } else if (is.character(stats1[[col]]) && !is.character(stats2[[col]])) {
        stats2[[col]] <- as.character(stats2[[col]])
        mismatches <- c(mismatches, col)
      }
    }
    if (length(mismatches) > 0) {
      cat("   Fixed type mismatches in:", paste(mismatches, collapse = ", "), "\n")
    }
    stats_all <- bind_rows(stats1, stats2)
  } else {
    stats_all <- stats1
  }

  cat("   Combined stats:", nrow(stats_all), "rows x", ncol(stats_all), "cols\n")
  rm(stats1, stats2); gc()

  # ============================================================================
  # STEP 3: Join stats to participants
  # ============================================================================
  # participants.id = stats.id (each row in participants has a matching stats row)
  # This gives us per-player stats with matchid and player number.
  cat("\n>> [Step 3/7] Joining stats to participants...\n")

  player_data <- participants %>%
    select(id, matchid, player) %>%
    inner_join(stats_all, by = "id")

  cat("   Joined:", nrow(player_data), "player-match rows\n")
  cat("   Unique matches:", n_distinct(player_data$matchid), "\n")

  # Check for join quality
  unmatched_participants <- nrow(participants) - nrow(player_data)
  if (unmatched_participants > 0) {
    cat("   WARNING:", unmatched_participants,
        "participants had no matching stats row (dropped).\n")
  }

  rm(stats_all, participants); gc()

  # ============================================================================
  # STEP 4: Assign team IDs and extract win/loss
  # ============================================================================
  # Convention: players 1-5 = team 100 (blue side), 6-10 = team 200 (red side)
  # The "win" column in stats is 0/1 per player; all 5 on a team share the value.
  cat("\n>> [Step 4/7] Assigning teams and extracting outcome...\n")

  player_data <- player_data %>%
    mutate(teamid = if_else(player <= 5, 100L, 200L))

  # Verify: each team in each match should have 5 players
  team_sizes <- player_data %>%
    count(matchid, teamid, name = "n_players")

  incomplete <- team_sizes %>% filter(n_players != 5)
  if (nrow(incomplete) > 0) {
    cat("   WARNING:", nrow(incomplete),
        "team-match combos don't have exactly 5 players.\n")
    cat("   Dropping incomplete teams...\n")
    valid_teams <- team_sizes %>% filter(n_players == 5)
    player_data <- player_data %>%
      semi_join(valid_teams, by = c("matchid", "teamid"))
  }

  # Extract team-level win (take max — all 5 should agree)
  team_win <- player_data %>%
    group_by(matchid, teamid) %>%
    summarise(win = max(win, na.rm = TRUE), .groups = "drop")

  cat("   Teams with outcome:", nrow(team_win), "\n")
  cat("   Win distribution:", sum(team_win$win == 1), "wins,",
      sum(team_win$win == 0), "losses\n")

  # ============================================================================
  # STEP 5: Aggregate player stats to team level
  # ============================================================================
  cat("\n>> [Step 5/7] Aggregating player stats to team level...\n")

  # Select meaningful numeric columns to sum across the 5 players
  # (exclude id, matchid, player, teamid, win, item columns, trinket)
  exclude_cols <- c("id", "matchid", "player", "teamid", "win",
                    "item1", "item2", "item3", "item4", "item5", "item6",
                    "trinket", "firstblood")
  agg_cols <- names(player_data)[
    sapply(player_data, is.numeric) &
    !names(player_data) %in% exclude_cols
  ]

  cat("   Aggregating", length(agg_cols), "stat columns:",
      paste(head(agg_cols, 8), collapse = ", "), "...\n")

  team_agg <- player_data %>%
    group_by(matchid, teamid) %>%
    summarise(
      across(all_of(agg_cols), ~ sum(., na.rm = TRUE), .names = "team_{.col}"),
      avg_champlvl = if ("champlvl" %in% agg_cols)
                       mean(champlvl, na.rm = TRUE) else NA_real_,
      .groups = "drop"
    )

  cat("   Aggregated:", nrow(team_agg), "team-match rows\n")
  rm(player_data, team_sizes); gc()

  # ============================================================================
  # STEP 6: Join match metadata and team stats
  # ============================================================================
  cat("\n>> [Step 6/7] Joining match metadata and team objective stats...\n")

  # From matches: keep duration and seasonid (useful predictors)
  # Drop platformid, queueid, gameid, creation, version (identifiers, not predictors)
  match_info <- matches %>%
    select(matchid = id, duration, seasonid)

  cat("   matches columns used: duration, seasonid\n")
  cat("   teamstats columns:", paste(names(teamstats), collapse = ", "), "\n")

  # Merge all pieces together
  prepared_data <- team_win %>%
    left_join(match_info, by = "matchid") %>%
    left_join(teamstats, by = c("matchid", "teamid")) %>%
    left_join(team_agg, by = c("matchid", "teamid"))

  n_before_merge <- nrow(team_win)
  cat("   Merged:", nrow(prepared_data), "rows x", ncol(prepared_data), "cols\n")

  # Check for NAs introduced by joins
  na_cols <- colSums(is.na(prepared_data))
  na_cols <- na_cols[na_cols > 0]
  if (length(na_cols) > 0) {
    cat("   Columns with NAs after merge:\n")
    print(na_cols)
  } else {
    cat("   No NAs introduced by merging.\n")
  }

  # ============================================================================
  # STEP 7: Final cleanup and save
  # ============================================================================
  cat("\n>> [Step 7/7] Final cleanup...\n")

  # Drop identifiers — matchid and teamid are not predictors
  prepared_data <- prepared_data %>%
    select(-matchid, -teamid)

  # Drop rows with missing outcome (shouldn't happen, but safety)
  n_before <- nrow(prepared_data)
  prepared_data <- prepared_data %>% filter(!is.na(win))
  dropped <- n_before - nrow(prepared_data)
  if (dropped > 0) cat("   Dropped", dropped, "rows with missing outcome.\n")

  # Save
  write_csv(prepared_data, PREPARED_FILE)
  cat("\n>> SAVED prepared dataset to:", PREPARED_FILE, "\n")
  cat(">> Final dimensions:", nrow(prepared_data), "rows x",
      ncol(prepared_data), "columns\n")

  rm(matches, teamstats, match_info, team_win, team_agg); gc()
}

cat("\n>> Prepared data columns:\n")
cat(paste(" ", names(prepared_data)), sep = "\n")
cat("\n>> 00_prepare_data.R complete.\n")
