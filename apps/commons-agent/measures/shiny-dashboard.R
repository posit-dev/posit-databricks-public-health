# Trusted calculations from the California communicable disease explorer
# (apps/shiny-dashboard/app.R). `surveillance` is supplied by commons: it is the
# Databricks connection for the data source of the same name.

cases_table <- function(surveillance) {
  dplyr::tbl(surveillance, I("public_health_demo.surveillance.infectious_disease_cases"))
}

#' Disease incidence trend for a county and the state
#'
#' Annual reported cases and published incidence rates per 100,000 for one
#' disease, for one county alongside the statewide total, all sexes combined.
#' This is the trend chart in the communicable disease explorer dashboard.
#'
#' @param disease `string` Exact disease name, e.g. "Coccidioidomycosis" for Valley Fever.
#' @param county `string` County name, e.g. "Kern". Use "California" for the state only.
#' @param start_year `integer` First year, 2001 or later.
#' @param end_year `integer` Last year, 2023 or earlier.
#' @return One row per area and year: county, year, cases, population,
#'   rate_per_100k, and rate_unstable. NULL cases or rates are suppressed.
#' @provenance apps/shiny-dashboard/app.R#L148-L159 (retrieved 2026-10-01)
#' @measure
disease_incidence_trend <- function(disease, county, start_year = 2001L,
                                    end_year = 2023L, surveillance) {
  areas <- unique(c(county, "California"))
  cases_table(surveillance) |>
    dplyr::filter(
      sex == "Total",
      disease == !!disease,
      county %in% !!areas,
      dplyr::between(year, !!as.integer(start_year), !!as.integer(end_year))
    ) |>
    dplyr::select(county, year, cases, population, rate_per_100k, rate_unstable) |>
    dplyr::arrange(county, year) |>
    dplyr::collect()
}

#' County ranking for a disease in one year
#'
#' Reported cases and published incidence rates for every county for one
#' disease and year, all sexes combined, highest rate first. This is the
#' county table in the communicable disease explorer dashboard.
#'
#' @param disease `string` Exact disease name, e.g. "Salmonellosis".
#' @param year `integer` Year between 2001 and 2023.
#' @return One row per county: county, cases, rate_per_100k, rate_unstable.
#'   Suppressed counts and rates are NULL and sort last.
#' @provenance apps/shiny-dashboard/app.R#L162-L173 (retrieved 2026-10-01)
#' @measure
county_ranking <- function(disease, year, surveillance) {
  cases_table(surveillance) |>
    dplyr::filter(
      sex == "Total",
      disease == !!disease,
      !is_statewide,
      year == !!as.integer(year)
    ) |>
    dplyr::select(county, cases, rate_per_100k, rate_unstable) |>
    dplyr::arrange(dplyr::desc(rate_per_100k)) |>
    dplyr::collect()
}
