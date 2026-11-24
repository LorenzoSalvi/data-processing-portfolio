# =============================================================================
# Shared helper functions
#
# A small personal library of functions written over time and reused across
# projects (charts, tables, data cleaning).
# Requires: dplyr, ggplot2, knitr and kableExtra (for styled_table).
# =============================================================================


# ggplot theme -----------------------------------------------------------------
# Built around a cadet-blue palette, but works with any colours.
# angle: rotation of the x-axis labels.

theme_tracker <- function(angle = 45) {
  theme(text = element_text(face = "bold",
                            colour = "black",
                            size = NULL),
        axis.text = element_text(face = "plain",
                                 colour = "black"),
        axis.text.x = element_text(angle = angle,
                                   hjust = 1),
        panel.background = element_rect(fill = "#f0f6f6",
                                        colour = "black",
                                        size = 0.5),
        panel.grid = element_blank(),
        legend.title = element_text(hjust = 0.5),
        legend.text = element_text(face = "plain"),
        plot.background = element_rect(fill = "white",
                                       colour = NULL,
                                       size = NULL),
        plot.title = element_text(hjust = 0.5),
        plot.subtitle = element_text(hjust = 0.5),
        strip.background = element_rect(fill = "black",
                                        colour = "black",
                                        size = 0.5),
        strip.text = element_text(face = "bold",
                                  colour = "#f0f6f6"))
}


# Styled HTML table ------------------------------------------------------------
# Arguments: the data frame, the vector of column names, the box height.

styled_table <- function(df, cols = NA, height = "100%") {
  kable(df, col.names = cols) %>%
    kable_styling(bootstrap_options = "striped",
                  full_width = FALSE) %>%
    row_spec(0, bold = T, background = "#5f9ea0", color = "white") %>%
    scroll_box(height = height, width = "100%")
}


# Number columns to numeric ----------------------------------------------------
# Converts the selected columns to numeric, optionally from the Italian/European
# format (decimal comma) and optionally replacing NAs with 0.
# Arguments: the data frame, the column indexes, decimal comma (T/F), NA to 0 (T/F)

to_numeric_cols <- function(table, columns, decimal_comma = TRUE, na.clean = TRUE) {

  tablen <- select(table, columns)
  tables <- select(table, -columns)

  if(decimal_comma == TRUE) {

    tablen1 <- as.data.frame(lapply(tablen, as.character), stringsAsFactors=FALSE)

    tablen2 <- as.data.frame(lapply(tablen1, sub, pattern = ",", replacement = ".", fixed = TRUE))

    tablen3 <- as.data.frame(lapply(tablen2, as.character), stringsAsFactors=FALSE)

    tablen4 <- as.data.frame(sapply(tablen3, FUN = as.numeric), stringsAsFactors=FALSE)

  } else {

    tablen3 <- as.data.frame(lapply(tablen, as.character), stringsAsFactors=FALSE)

    tablen4 <- as.data.frame(sapply(tablen3, FUN = as.numeric), stringsAsFactors=FALSE)

  }


  if(na.clean == TRUE) {

    tablen5 <- tablen4 %>% mutate_all(~replace(., is.na(.), 0))

    tablereturn <- bind_cols(tables, tablen5, .id = NULL)

  } else {

    tablereturn <- bind_cols(tables, tablen4, .id = NULL)

  }

  return(tablereturn)
}


# Row and column totals --------------------------------------------------------
# Adds a TOTAL column (row sums), a final TOTAL row (column sums) and a PCT
# column (each row's share of the grand total).
# Arguments: the data frame and the indexes of the columns to sum.

add_totals <- function(table, columns) {

  tablen <- select(table, columns)
  tablec <- select(table, -columns)

  tablen0 <- lapply(tablen, as.character, stringsAsFactors=FALSE)
  tablen1 <- as.data.frame(sapply(tablen0, FUN = as.numeric), stringsAsFactors=FALSE)

  tablen2 <- tablen1 %>%
    mutate(TOTAL = rowSums(tablen1))

  tablenlow <- summarise_all(tablen2, sum)

  tablen3 <- bind_rows(tablen2, tablenlow, .id = NULL)

  tablen4 <- tablen3 %>%
    mutate(PCT = as.numeric(TOTAL) / as.numeric(tail(tablen3$TOTAL, n = 1)) * 100) %>%
    mutate(PCT = round(PCT, digits = 2))

  tablec1 <- add_row(tablec) %>%
    lapply(as.character, stringsAsFactors=FALSE) %>%
    as.data.frame(stringsAsFactors = FALSE)

  coord <- dim(tablec1)
  coord1 <- coord[1]
  coord2 <- coord[2]

  "TOTAL" -> tablec1[coord1,coord2]

  tablereturn <- bind_cols(tablec1, tablen4, .id = NULL)

  # with a single numeric column, the TOTAL column would just repeat it
  tablereturn2 <- select(tablereturn, -TOTAL)

  if (identical(tablen3[,1], tablereturn[,"TOTAL"])) {

    return(tablereturn2)

  } else {

    return(tablereturn)

  }
}


# Number to percentage string ---------------------------------------------------
# e.g. 0.12345 -> "12.35%"

to_percent <- function(x) {
  paste0(100*round(x, digits = 4), "%")
}
