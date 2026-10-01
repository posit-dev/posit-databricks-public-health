# Trusted calculations from the R walkthrough (demo/r/01-explore-dbplyr.R).

#' Pooled county incidence rates over a period
#'
#' Total cases, total person-years, and the pooled incidence rate per 100,000
#' for every county for one disease across a range of years, all sexes
#' combined, highest rate first. Use this to compare counties over several
#' years instead of averaging annual rates.
#'
#' @param disease `string` Exact disease name, e.g. "Coccidioidomycosis".
#' @param start_year `integer` First year, 2001 or later.
#' @param end_year `integer` Last year, 2023 or earlier.
#' @return One row per county: county, cases, person_years, rate_per_100k.
#'   Suppressed counts are excluded from the sums, so counties with suppressed
#'   years have rates that are lower bounds.
#' @provenance demo/r/01-explore-dbplyr.R#L76-L89 (retrieved 2026-10-01)
#' @measure
county_pooled_rates <- function(disease, start_year, end_year, surveillance) {
  dplyr::tbl(
    surveillance,
    I("public_health_demo.surveillance.infectious_disease_cases")
  ) |>
    dplyr::filter(
      disease == !!disease,
      sex == "Total",
      !is_statewide,
      dplyr::between(year, !!as.integer(start_year), !!as.integer(end_year))
    ) |>
    dplyr::summarise(
      cases = sum(cases, na.rm = TRUE),
      person_years = sum(population, na.rm = TRUE),
      .by = county
    ) |>
    dplyr::mutate(rate_per_100k = cases / person_years * 100000) |>
    dplyr::arrange(dplyr::desc(rate_per_100k)) |>
    dplyr::collect()
}
