# R + Databricks with DBI, odbc, and dbplyr
# ---------------------------------------------------------------------------
# Everything here runs the same in RStudio or Positron on Posit Workbench,
# or on your laptop. Nothing in this script depends on the IDE.
#
# Big ideas:
#   1. No credentials in code. Ever.
#   2. Write dplyr. Databricks does the work. Only results come back to R.
#   3. Governance lives in Unity Catalog, so it follows you into every tool.

library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(dbplyr, warn.conflicts = FALSE)
library(ggplot2)

# 1. Connect -----------------------------------------------------------------
# odbc::databricks() finds credentials for you, in this order:
#   - Posit Connect: the viewer's (or service account's) OAuth token
#   - Posit Workbench: your Workbench-managed Databricks credentials
#   - Laptop: DATABRICKS_TOKEN / client ID, or the Databricks CLI
#
# The workspace comes from DATABRICKS_HOST (set by Workbench). The SQL
# warehouse comes from DATABRICKS_HTTP_PATH, set once in ~/.Renviron.

con <- dbConnect(
  odbc::databricks(),
  httpPath = Sys.getenv("DATABRICKS_HTTP_PATH"),
  bigint = "numeric"
)

# Who does Databricks think I am?
dbGetQuery(con, "SELECT current_user() AS me")

# Tip: the Connections pane (RStudio and Positron) lets you browse
# catalogs, schemas, tables, and columns from here.

# 2. A lazy table --------------------------------------------------------------
cases <- tbl(con, in_catalog("public_health_demo", "surveillance", "infectious_disease_cases"))

# Printing shows a preview. R hasn't downloaded the table.
cases

# How many rows are we NOT pulling into R?
cases |> count() |> show_query()

# 3. Ask a question with dplyr -------------------------------------------------
# Coccidioidomycosis (Valley Fever): statewide incidence by year.
valley_fever <- cases |>
  filter(
    disease == "Coccidioidomycosis",
    sex == "Total",
    is_statewide
  ) |>
  select(year, cases, population, rate_per_100k) |>
  arrange(year)

# Still lazy. This is the SQL dbplyr will send to Databricks:
valley_fever |> show_query()

# collect() runs the query and returns a tibble with 23 rows.
valley_fever_df <- collect(valley_fever)
valley_fever_df

ggplot(valley_fever_df, aes(year, rate_per_100k)) +
  geom_line(linewidth = 1, color = "#447099") +
  geom_point(color = "#447099") +
  labs(
    title = "Valley Fever incidence in California, 2001-2023",
    x = NULL, y = "Cases per 100,000"
  ) +
  theme_minimal(base_size = 14)

# 4. Push the heavy lifting to the warehouse -----------------------------------
# Which counties carry the burden? Compute 5-year rates in Databricks.
county_rates <- cases |>
  filter(
    disease == "Coccidioidomycosis",
    sex == "Total",
    !is_statewide,
    between(year, 2019, 2023)
  ) |>
  summarise(
    cases = sum(cases, na.rm = TRUE),
    person_years = sum(population, na.rm = TRUE),
    .by = county
  ) |>
  mutate(rate_per_100k = cases / person_years * 100000) |>
  slice_max(rate_per_100k, n = 10)

county_rates |> show_query()
county_rates |> collect()

# 5. Governance follows the data -------------------------------------------
# Unity Catalog masks counts of 1-10 unless you are in the `phi_unmasked`
# group. This is not R code. It is the same rule for SQL, Python, notebooks,
# and published apps. Suppressed values come back to R as NA.
cases |>
  filter(sex == "Total", !is_statewide) |>
  summarise(
    rows = n(),
    suppressed = sum(as.integer(is.na(cases)), na.rm = TRUE)
  )

dbGetQuery(con, "SELECT is_member('phi_unmasked') AS can_see_small_cells")

# 6. When you need Databricks SQL, use it --------------------------------------
# dbplyr passes functions it doesn't know through to Databricks unchanged,
# so any Databricks SQL function works inside mutate()/filter().
cases |>
  filter(is_statewide, sex == "Total", year == 2023, cases > 0) |>
  mutate(disease_short = trim(regexp_extract(disease, "^[^,(]+", 0L))) |>
  select(disease_short, cases, rate_per_100k) |>
  arrange(desc(cases))

# Or write SQL directly. Let DBI quote values for you
# (never paste() user input into SQL).
top_counties_sql <- sqlInterpolate(
  con,
  "SELECT county, SUM(cases) AS cases
     FROM public_health_demo.surveillance.infectious_disease_cases
    WHERE disease = ?disease AND sex = 'Total' AND NOT is_statewide
      AND year >= ?since
    GROUP BY county ORDER BY cases DESC LIMIT 5",
  disease = "Salmonellosis",
  since = 2019L
)
dbGetQuery(con, top_counties_sql)

# 7. Clean up --------------------------------------------------------------------
dbDisconnect(con)
