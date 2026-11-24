# Data Processing Portfolio

**Lorenzo Salvi** – Operations & Data Specialist
PMO · Data Analysis · Monitoring & Evaluation · Process Automation

This repository collects three data-processing projects I designed and wrote for my work in public administration. They cover the full chain of administrative data: collecting files filled in by many different bodies, cleaning and harmonizing them, validating them against rules and targets, and turning them into monitoring tools that non-technical colleagues can use.

---

## About this code: real projects, anonymized

These scripts are **anonymized and generalized versions of tools I built and used in production**, in real monitoring and reporting processes.

Because the original data and context are confidential, I have:

- **removed all data**: no real dataset is included or referenced;
- **renamed** programmes, measures, areas, organizations, statuses and column names with generic labels (e.g. "Measure A", "Area B", "Lot 3");
- **replaced all targets and thresholds** with placeholder values;
- **translated** code and comments into English.

The **logic, structure and data-quality checks are the ones used in the real projects**. Only names and values have changed. The screenshots show the real layouts with sample data only.

Synthetic datasets can be provided for testing on request.

---

## Projects

| # | Project | What it shows | Stack |
|---|---|---|---|
| 1 | [**Multi-source harmonization**](01-multi-source-harmonization/) | Reading and cleaning Excel files filled in by hand by 8 providers, each with its own layout; one record per person across providers; updating the previous year's file with the new year's data; validation tests and a review list | R (tidyverse, readxl, lubridate) |
| 2 | [**Target tracking dashboard**](02-target-tracking-dashboard/) | Joining several CRM exports, classifying each application's progress, splitting national targets across 6 areas with consistency tests, flagging ambiguous records, an interactive dashboard for 7 measures | R Markdown, flexdashboard, ggplot2, DT |
| 3 | [**Submission monitoring app**](03-submission-monitoring-app/) | Monitoring a national survey: status of each body, progress towards targets by cluster and area, Excel export. Same logic in R and in a desktop app with upload, gauges and download | R (dplyr) · Python (pandas, NiceGUI, Plotly) |

Common threads:

- **Data quality first.** Inconsistent dates, formats and column names are normalized explicitly. Records that do not fit the rules are flagged, not silently dropped ("Needs review", "To review" sheets, `stop()` tests on totals).
- **Readable, maintainable code.** Steps shared by all inputs live in functions. Source-specific adjustments stay explicit, so each one can be checked.
- **Tools for non-specialists.** Outputs are dashboards, apps and Excel files that colleagues use without touching the code.

---

## Repository structure

```
├── helpers.R                          shared functions (chart theme, tables, numeric cleaning)
├── 01-multi-source-harmonization/
│   └── participants_consolidation.R
├── 02-target-tracking-dashboard/
│   ├── target_tracking_dashboard.Rmd
│   └── screenshots/
└── 03-submission-monitoring-app/
    ├── survey_monitoring.R
    ├── app/                           Python desktop app
    └── screenshots/
```

Each project folder has its own README with context, logic and technical choices.
