# =============================================================================
# Survey submission monitoring - progress towards targets by cluster
#
# Public bodies must fill in a national online survey. This script combines:
#   - a registry Excel file (one row per body: cluster, area, contact info);
#   - report 1 (CSV export from the CRM): survey status of each body;
#   - report 2 (CSV export from the CRM): last contact with each body;
# and computes, for each cluster of bodies, how many surveys were sent or are
# still in draft, compared with the cluster's target.
#
# Output: one Excel file with three sheets (body-level detail, target
# monitoring by cluster, target monitoring by area and cluster).
#
# This R script was the base for the data manipulation; the interactive app
# (see demo screenshot) reproduces the same logic in Python.
#
# Anonymized and generalized version of a script used in production.
# Data are not included for confidentiality reasons; target values are
# placeholders.
# =============================================================================

library(dplyr)
library(stringr)
library(forcats)
library(lubridate)
library(readr)
library(readxl)
library(openxlsx)


# Registry ---------------------------------------------------------------------
# Bodies exempt from the survey are moved to the "Other" cluster.
# The exemption column is filled in by hand, so several spellings are accepted.

registry <- read_excel("./input/registry.xlsx") %>%
    mutate(Cluster = case_when(
      str_detect(`Is the body exempt from the survey?`, "YES") |
        str_detect(`Is the body exempt from the survey?`, "Yes") |
        str_detect(`Is the body exempt from the survey?`, "yes") ~ "Other",
      TRUE ~ Cluster)) %>%
  select(`Org code` = Code,
         Organization = `Organization name`,
         Cluster,
         `Account manager` = `Account Manager`,
         `Technical support`,
         Area,
         `Invitation sent on`,
         `Invitation received` = `Did the body receive the invitation? (YES/NO)`,
         `Registry notes` = `NOTES on the body's survey completion`)


# Report 1: survey status ------------------------------------------------------
# A body may have more than one record: keep the most advanced status.

report1 <- read_csv2("./input/report_1.csv", locale=locale(encoding="latin1")) %>%
  select(`Org code` = `Account: Org code`,
         Status) %>%
  mutate(Status = fct_relevel(Status, "Not started", "Draft", "Sent")) %>%
  group_by(`Org code`) %>%
  arrange(desc(Status)) %>%
  distinct(`Org code`, .keep_all = T) %>%
  ungroup()


# Report 2: contacts -----------------------------------------------------------
# Keep only the most recent contact with each body.

report2 <- read_csv2("./input/report_2.csv", locale=locale(encoding="latin1")) %>%
  select(`Last contact date` = Date,
         Organization = `Organization name`,
         `Meeting title`,
         Comments) %>%
  mutate(`Last contact date` = dmy(`Last contact date`)) %>%
  group_by(Organization) %>%
  arrange(desc(`Last contact date`)) %>%
  distinct(Organization, .keep_all = T) %>%
  ungroup()


# Body-level monitoring --------------------------------------------------------
# Bodies with no record in report 1 never opened the survey.

detailed_monitoring <- registry %>%
  left_join(report1, by = "Org code") %>%
  left_join(report2, by = "Organization") %>%
  mutate(Status = case_when(
    is.na(Status) ~ "Not opened",
    TRUE ~ Status))



# Targets: % of bodies in each cluster that must send the survey (placeholders)
target_regional_bodies <- 85
target_health_authorities <- 88
target_national_large <- 65
target_national_small <- 45
target_large_cities <- 80
target_medium_cities <- 75
target_small_cities <- 55
target_schools <- 35
target_universities <- 60


# Progress calculation -----------------------------------------------------------
# Takes the body-level data already grouped (by cluster, or by area and cluster)
# and returns sent, drafts, totals and progress towards the cluster target.
# Same logic as _aggregate() in the Python app.

summarise_progress <- function(grouped_df) {
  grouped_df %>%
    summarise(`Total sent` = as.integer(sum(Sent)), `Total drafts` = as.integer(sum(Drafts)), `Total` = n()) %>%
    ungroup() %>%
    mutate(`Percentage sent` = round(((`Total sent`/Total)*100), digits = 2),
           `Target percentage` = case_when(
             Cluster == "Large cities" ~ target_large_cities,
             Cluster == "Medium cities" ~ target_medium_cities,
             Cluster == "Small cities" ~ target_small_cities,
             Cluster == "Regional bodies" ~ target_regional_bodies,
             Cluster == "Health authorities" ~ target_health_authorities,
             Cluster == "National agencies (large)" ~ target_national_large,
             Cluster == "National agencies (small)" ~ target_national_small,
             Cluster == "Schools" ~ target_schools,
             Cluster == "Universities" ~ target_universities),
           `Target total` = round((`Target percentage`/100)*`Total`, digits = 2),
           `Progress percentage` = round((`Total sent`/`Target total`)*100, digits = 2)) %>%
    select(
      any_of("Area"),
      Cluster,
      `Total sent`,
      `Total drafts`,
      `Target - total to send` = `Target total`,
      `Target - % reached` = `Progress percentage`,
      `Target - % to reach` = `Target percentage`,
      `Overall - total to send` = `Total`,
      `Overall - % reached` = `Percentage sent`
    )
}


# one flag per body (sent / draft) and clusters in display order
monitoring_flags <- detailed_monitoring %>%
  mutate(Sent = case_when(
    Status == "Sent" ~ 1,
    TRUE ~ 0),
  Drafts = case_when(
    Status == "Draft" ~ 1,
    TRUE ~ 0)) %>%
  select(Cluster, Area, Sent, Drafts) %>%
  mutate(Cluster = fct_relevel(Cluster, "Large cities", "Medium cities",
                               "Small cities", "Micro cities",
                               "Regional bodies", "Health authorities", "National agencies (large)", "National agencies (small)", "Schools", "Universities", "Other"))


# Progress by cluster ----------------------------------------------------------

target_monitoring <- monitoring_flags %>%
  group_by(Cluster) %>%
  summarise_progress()


# Clusters have two deadlines: July and October
target_monitoring_july <- target_monitoring %>% filter(!Cluster %in% c("Schools", "Universities", "Other"))
target_monitoring_october <- target_monitoring %>% filter(Cluster %in% c("Schools", "Universities"))


# Totals to display
total_sent_all <- sum(target_monitoring$`Total sent`)
total_drafts_all <- sum(target_monitoring$`Total drafts`)
total_sent_july <- sum(target_monitoring_july$`Total sent`)
total_drafts_july <- sum(target_monitoring_july$`Total drafts`)
total_sent_october <- sum(target_monitoring_october$`Total sent`)
total_drafts_october <- sum(target_monitoring_october$`Total drafts`)


# Progress by area and cluster -------------------------------------------------
# National agencies are not assigned to areas, so they are excluded here.

area_monitoring <- monitoring_flags %>%
  filter(!str_detect(Cluster, "National agencies")) %>%
  group_by(Area, Cluster) %>%
  summarise_progress() %>%
  filter(!is.na(Area))


# Export -----------------------------------------------------------------------

l <- list("Detailed monitoring" = detailed_monitoring, "Target monitoring" = target_monitoring, "Area monitoring" = area_monitoring)


write.xlsx(l, str_c("./output/", today(), "_survey_monitoring.xlsx"), colWidths="auto")
