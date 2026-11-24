# =============================================================================
# Participant data consolidation - multi-provider social inclusion programme
#
# Each service provider ("lot") reports its participants in its own Excel file,
# filled in by hand. Files differ in column names, header rows and date formats.
# This script:
#   1. reads and harmonizes all provider files into one standard structure;
#   2. collapses participants seen by more than one provider into a single row
#      (earliest entry date, latest exit date);
#   3. updates the previous year's final file with the current year's data
#      (exit date only for returning participants, full row for new ones);
#   4. exports the final file plus a list of cases for manual review.
#
# Anonymized and generalized version of a script used in production.
# Data are not included for confidentiality reasons.
# =============================================================================

library(tidyverse)
library(readxl)
library(openxlsx)
library(lubridate)


# Helper functions -------------------------------------------------------------

# Normalizes any date column to "dd/mm/yyyy" text, whatever readxl returned
normalize_date <- function(x) {

  # 1. Column already read as Date
  if (inherits(x, "Date")) {
    return(format(x, "%d/%m/%Y"))
  }

  # 2. Column read as date-time, frequent with readxl
  if (inherits(x, c("POSIXct", "POSIXlt"))) {
    return(format(as.Date(x), "%d/%m/%Y"))
  }

  # 3. Numeric column: Excel serial numbers or NA
  if (is.numeric(x)) {

    converted_date <- suppressWarnings(
      as_date(x, origin = "1899-12-30")
    )

    return(
      if_else(
        is.na(x),
        NA_character_,
        format(converted_date, "%d/%m/%Y")
      )
    )
  }

  # 4. Character column
  original <- str_trim(as.character(x))

  # Empty cells and original NAs
  empty <- is.na(original) | original == ""

  # Detects Excel serial numbers stored as text
  excel_number <- str_detect(
    original,
    "^\\d+(?:[.,]\\d+)?$"
  )

  number <- suppressWarnings(
    as.numeric(str_replace(original, ",", "."))
  )

  # Converts Excel serial numbers
  from_excel <- suppressWarnings(
    as_date(number, origin = "1899-12-30")
  )

  # Tries to parse dates already written as text
  from_text <- suppressWarnings(
    parse_date_time(
      original,
      orders = c(
        "dmy",
        "dmY",
        "Ymd",
        "ymd",
        "d-m-Y",
        "d/m/Y",
        "Y-m-d",
        "d.m.Y"
      ),
      exact = FALSE,
      quiet = TRUE
    )
  )

  case_when(
    empty ~ NA_character_,

    excel_number & !is.na(from_excel) ~
      format(from_excel, "%d/%m/%Y"),

    !excel_number & !is.na(from_text) ~
      format(as.Date(from_text), "%d/%m/%Y"),

    TRUE ~ "INVALID DATE"
  )
}


# Manual data entry often uses an apostrophe instead of an accented vowel
# (e.g. "a'" instead of "à"): this restores the correct character
fix_accented_vowels <- function(text) {
  str_replace_all(
    text,
    c(
      "a['’]" = "à",
      "e['’]" = "è",
      "i['’]" = "ì",
      "o['’]" = "ò",
      "u['’]" = "ù",
      "A['’]" = "À",
      "E['’]" = "È",
      "I['’]" = "Ì",
      "O['’]" = "Ò",
      "U['’]" = "Ù"
    )
  )
}


# Shared standardization step --------------------------------------------------
# Every provider file goes through the same cleaning steps once its own columns
# have been renamed to the standard names (entry_date, exit_date, birth_date,
# birth_place, tax_id) and its lot assigned. Code columns (entry_code,
# exit_code...) are left empty: they are filled in later, according to the
# national reporting specifications.

standardize_lot <- function(df) {
  df %>%
    mutate(entry_date = normalize_date(entry_date),
           exit_date = normalize_date(exit_date),
           birth_date = normalize_date(birth_date),
           participant_status = "Active",
           gender = case_when(
             str_starts(GENDER, "M") ~ "Male",
             str_starts(GENDER, "F") ~ "Female",
             TRUE ~ GENDER),
           citizenship = str_to_title(CITIZENSHIP) %>% fix_accented_vowels(),
           birth_municipality = birth_place %>%
             str_remove_all("\\s*\\([^)]*\\)") %>%
             str_trim() %>%
             str_to_upper() %>%
             fix_accented_vowels(),
           full_name = str_c(NAME, " ", SURNAME),
           entry_code_table = "",
           entry_code = "",
           exit_code = "",
           exit_code_reclassified = "") %>%
    select(entry_date,
           exit_date,
           participant_status,
           gender,
           citizenship,
           birth_municipality,
           birth_date,
           employment_status = `EMPLOYMENT STATUS`,
           education = EDUCATION,
           disadvantage = `DISADVANTAGE CONDITION`,
           entry_code_table,
           entry_code,
           exit_code,
           exit_code_reclassified,
           notes = NOTES,
           full_name,
           tax_id,
           lot) %>%
    filter(!is.na(tax_id))
}


# Reading provider files -------------------------------------------------------
# Provider-specific steps only: file, sheet, header rows, column names and any
# special rule. Each file is checked by hand before being added here.

lot1 <- read_excel("input/MONITORING_LOT 1_ 2026.xlsx") %>%
  rename(entry_date = `ENTRY DATE`,
         exit_date = `EXIT DATE`,
         birth_date = `DATE OF BIRTH`,
         birth_place = `PLACE OF BIRTH (MUNICIPALITY or  ABROAD)`,
         tax_id = `TAX CODE`) %>%
  mutate(lot = "Lot 1") %>%
  standardize_lot()


lot2 <- read_excel("input/MONITORING_LOT 2_ 2026.xlsx") %>%
  rename(entry_date = `ENTRY DATE`,
         exit_date = `EXIT DATE`,
         birth_date = `DATE OF BIRTH`,
         birth_place = `PLACE OF BIRTH (MUNICIPALITY or  ABROAD)`,
         tax_id = `TAX CODE`) %>%
  mutate(lot = "Lot 2") %>%
  standardize_lot()


# Lot 3 uses a different template: other sheet, one extra header row and
# column names with line breaks and filling instructions
lot3 <- read_excel("input/LOT 3_2025 _PARTICIPANT MONITORING SHEET_.xlsx", sheet = "TOT 2026", skip = 1) %>%
  rename(entry_date = `ENTRY DATE / FIRST SERVICE IN THE YEAR\r\nDOUBLE CLICK ON CELL FOR CALENDAR`,
         exit_date = `EXIT DATE\r\nDOUBLE CLICK ON CELL FOR CALENDAR`,
         birth_date = `DATE OF BIRTH DOUBLE CLICK ON CELL FOR CALENDAR`,
         birth_place = `PLACE OF BIRTH\r\nMUNICIPALITY`,
         tax_id = `TAX CODE\r\nIF RED = DUPLICATE CODE`) %>%
  mutate(lot = "Lot 3") %>%
  standardize_lot()


lot4 <- read_excel("input/MONITORING_LOT 4_ 2026.xlsx") %>%
  rename(entry_date = `ENTRY DATE`,
         exit_date = `EXIT DATE`,
         birth_date = `DATE OF BIRTH`,
         birth_place = `PLACE OF BIRTH (MUNICIPALITY or  ABROAD)`,
         tax_id = `TAX CODE`) %>%
  mutate(lot = "Lot 4") %>%
  standardize_lot()


lot5 <- read_excel("input/MONITORING_LOT 5_ 2026.xlsx") %>%
  rename(entry_date = `ENTRY DATE`,
         exit_date = `EXIT DATE`,
         birth_date = `DATE OF BIRTH`,
         birth_place = `PLACE OF BIRTH (MUNICIPALITY or  ABROAD)`,
         tax_id = `TAX CODE`) %>%
  mutate(lot = "Lot 5") %>%
  standardize_lot()


lot6 <- read_excel("input/MONITORING_LOT 6_ 2026.xlsx") %>%
  rename(entry_date = `ENTRY DATE`,
         exit_date = `EXIT DATE`,
         birth_date = `DATE OF BIRTH`,
         birth_place = `PLACE OF BIRTH (MUNICIPALITY or  ABROAD)`,
         tax_id = `TAX CODE`) %>%
  mutate(lot = "Lot 6") %>%
  standardize_lot()


# Lot 9 file also tracks participants who moved on to Lot 10 (sport activity):
# for them, the exit date is the Lot 10 one and they are assigned to Lot 10.
# Two header rows to skip.
lot9 <- read_excel("input/MONITORING_LOT 9_ 2026.xlsx", skip = 2) %>%
  rename(entry_date = `ENTRY DATE LOT 9`,
         birth_date = `DATE OF BIRTH`,
         birth_place = `PLACE OF BIRTH (MUNICIPALITY or  ABROAD)`,
         tax_id = `TAX CODE`) %>%
  mutate(exit_date = case_when(
           !is.na(`ENTRY LOT 10`) ~ `EXIT DATE LOT 10`,
           is.na(`ENTRY LOT 10`) ~ `EXIT DATE LOT 9`),
         lot = case_when(
           !is.na(`ENTRY LOT 10`) ~ "Lot 10 - sport",
           is.na(`ENTRY LOT 10`) ~ "Lot 9")) %>%
  standardize_lot()


lot10 <- read_excel("input/MONITORING_LOT 10_ 2026.xlsx") %>%
  rename(entry_date = `ENTRY DATE`,
         exit_date = `EXIT DATE`,
         birth_date = `DATE OF BIRTH`,
         birth_place = `PLACE OF BIRTH (MUNICIPALITY or  ABROAD)`,
         tax_id = `TAX CODE`) %>%
  mutate(lot = "Lot 10 - housing") %>%
  standardize_lot()


# Consolidation ----------------------------------------------------------------

# All passages through any provider: one row per participant per provider
lots2026_passages <- bind_rows(lot1, lot2, lot3, lot4, lot5, lot6, lot9, lot10) %>%
  mutate(entry_date = dmy(entry_date),
         exit_date = dmy(exit_date),
         birth_date = dmy(birth_date))

passage_counts <- lots2026_passages %>%
  count(tax_id)


# One row per participant: earliest entry, latest exit.
# na.rm = FALSE is intentional: a missing exit date means the participant is
# still active; a missing entry date is kept as NA and checked by hand.
lots2026_aggregated <- lots2026_passages %>%
  group_by(tax_id) %>%
  summarise(
    entry_date = min(entry_date, na.rm = FALSE),
    exit_date = max(exit_date, na.rm = FALSE),
    participant_status = min(participant_status),
    gender = min(gender),
    citizenship = min(citizenship),
    birth_municipality = min(birth_municipality),
    birth_date = min(birth_date, na.rm = FALSE),
    employment_status = min(employment_status),
    education = min(education),
    disadvantage = min(disadvantage),
    entry_code_table = min(entry_code_table),
    entry_code = min(entry_code),
    exit_code = min(exit_code),
    exit_code_reclassified = min(exit_code_reclassified),
    notes = min(notes),
    full_name = min(full_name),
    tax_id = min(tax_id),
    lot = min(lot)) %>%
  ungroup()


# Previous year's final file, already in the national data-entry format
final_file_2025 <- read_excel("final_files_2025/final_file_2025.xlsx")


# =============================================================================
# UPDATE OF THE 2025 FINAL FILE WITH 2026 DATA
# Key: tax_id. The 2025 file has the same columns as lots2026_aggregated.
# =============================================================================


# 0. Same data type for dates in both years ------------------------------------
# (normalize_date handles Date, text and Excel serial numbers alike)

final_file_2025 <- final_file_2025 %>%
  mutate(across(c(entry_date, exit_date, birth_date),
                ~ dmy(normalize_date(.x))))


# 1. Preliminary checks: one record per participant ----------------------------

if (anyDuplicated(final_file_2025$tax_id) > 0) {
  stop("Duplicate tax IDs in the 2025 final file")
} else {
  print("Test unique tax IDs 2025 OK")
}

if (anyDuplicated(lots2026_aggregated$tax_id) > 0) {
  stop("Duplicate tax IDs in the 2026 aggregated data")
} else {
  print("Test unique tax IDs 2026 OK")
}


# 2. Participants already in 2025: update the exit date ONLY -------------------
# A missing 2026 exit date means the participant is still active, so it
# overwrites the 2025 value anyway (coalesce() would keep the old date).

exits_26 <- lots2026_aggregated %>%
  select(tax_id, exit_date_26 = exit_date)

updated_25 <- final_file_2025 %>%
  left_join(exits_26, by = "tax_id") %>%
  mutate(present_26 = tax_id %in% lots2026_aggregated$tax_id,
         exit_date_25 = exit_date,
         exit_date = if_else(present_26, exit_date_26, exit_date)) %>%
  select(-exit_date_26)


# 3. New participants ("only 2026"): full row ----------------------------------

only26 <- lots2026_aggregated %>%
  anti_join(final_file_2025, by = "tax_id")


# 4. 2026 final file, same format (and column order) as 2025 -------------------

final_file_2026 <- bind_rows(updated_25, only26) %>%
  select(all_of(names(final_file_2025)))


# 5. Row count consistency tests -----------------------------------------------

n_updated <- sum(updated_25$present_26)

if (nrow(final_file_2026) == nrow(final_file_2025) + nrow(only26)) {
  print("Test final rows OK")
} else {
  stop("Final rows differ from 2025 rows + new 2026 participants")
}

if (n_updated + nrow(only26) == nrow(lots2026_aggregated)) {
  print("Test 2026 coverage OK")
} else {
  stop("Not all 2026 participants were assigned (updated or new)")
}


# 6. Cases for manual review ---------------------------------------------------

# only the columns needed for the check are kept in each part, so that columns
# with different types in the two years (e.g. an empty notes column) do not
# prevent binding the rows
review_cols <- c("reason", "tax_id", "full_name", "lot", "entry_date", "exit_date", "exit_date_25")

to_review <- bind_rows(

  # missing or invalid entry date in 2026 data
  only26 %>%
    filter(is.na(entry_date)) %>%
    mutate(reason = "New in 2026: missing or invalid entry date") %>%
    select(any_of(review_cols)),

  # already exited in 2025 but present again in 2026 (re-entry?)
  updated_25 %>%
    filter(present_26 & !is.na(exit_date_25)) %>%
    mutate(reason = "Exit already recorded in 2025 but present in 2026") %>%
    select(any_of(review_cols)),

  # exit before entry
  final_file_2026 %>%
    filter(!is.na(exit_date) & !is.na(entry_date) & exit_date < entry_date) %>%
    mutate(reason = "Exit date before entry date") %>%
    select(any_of(review_cols))
)


# 7. Export --------------------------------------------------------------------

l <- list("Final 2026" = final_file_2026,
          "New 2026" = only26,
          "To review" = to_review)

write.xlsx(l, str_c("./output/", today(), "_final_file_2026.xlsx"), colWidths = "auto")
