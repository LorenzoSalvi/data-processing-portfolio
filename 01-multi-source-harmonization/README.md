# 1 · Multi-source harmonization

**R script** that consolidates the participant data of a multi-provider social inclusion programme and produces the yearly file for national reporting.

> Anonymized and generalized version of a script used in production. No data is included. Provider files, column names and labels are generic. See the [main README](../README.md).

---

## The problem

Participants are followed by several service providers ("lots"). Each provider reports its participants in an **Excel file filled in by hand**, and no two files are alike:

- **different column names** for the same information, sometimes with line breaks and filling instructions inside the header;
- **different layouts**: other sheet names, extra header rows to skip;
- **dates in every possible format**: real dates, date-times, Excel serial numbers stored as numbers or as text, dates typed as text in several orders;
- **manual-entry habits**, e.g. an apostrophe instead of an accented vowel (`Citta'` for `Città`);
- **special cases**: one provider's file also tracks participants who moved on to another lot.

The same person can be followed by more than one provider during the year. The national reporting format, however, requires **one record per person**, consistent with the previous year's file.

## What the script does

```
8 provider files ──► harmonize ──► one row per passage ──► one row per person ──► update last year's file ──► final file + review list
```

1. **Harmonize each file.** For every provider, a short explicit block handles only what is specific to that file: file name, sheet, rows to skip, its column names, any special rule. The block then calls `standardize_lot()`, which applies the steps shared by all files: date normalization, gender and citizenship cleaning, place of birth cleaning, standard column set.
2. **Bind all passages** into one table.
3. **Collapse to one row per person** (key: tax ID). The entry date is the earliest one and the exit date the latest one. A missing exit date means the person is still active. A missing entry date is kept as missing on purpose, so it can be checked by hand.
4. **Update the previous year's final file.** People already present get **only their exit date** updated. New people are added as full rows. The output keeps exactly the previous year's format and column order.
5. **Run consistency tests.** Duplicate IDs and row counts that do not add up stop the script with an explicit error.
6. **Export** an Excel file with the final data, the new participants and a **"To review" sheet**: missing entry dates, people who had exited and came back, exit dates before entry dates.

## Technical choices

- **`normalize_date()`** turns any date representation `readxl` may return (Date, POSIXct, Excel serial number, text in several orders) into one format. Unparseable values are labelled `INVALID DATE` rather than silently becoming missing.
- **Shared steps in a function, file-specific steps in plain sight.** Every input file is checked by hand when it arrives. Keeping each provider's adjustments in its own short block makes them easy to review and to change when a provider modifies its template.
- **The exit-date update does not use `coalesce()`.** A missing exit date in the new year means "still active" and must overwrite the old value.
- **Fail loudly.** `stop()` tests on uniqueness and row counts prevent a wrong file from being sent on.

## Requirements

R with `tidyverse`, `readxl`, `openxlsx`, `lubridate`.
