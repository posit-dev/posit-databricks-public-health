# Trusted calculations from the county communicable disease snapshot report
# (reports/disease-snapshot.qmd).

#' County disease profile compared with the state
#'
#' Every reportable disease with at least one case (or a suppressed count) in a
#' county for one year, with the county's published rate, the statewide rate,
#' and the ratio of the two. This is the main table of the county snapshot
#' report.
#'
#' @param county `string` County name, e.g. "Kern".
#' @param year `integer` Year between 2001 and 2023.
#' @return One row per disease: disease, cases, rate_per_100k, rate_unstable,
#'   state_rate, and county_to_state_ratio, highest county rate first.
#' @provenance reports/disease-snapshot.qmd#L40-L54 (retrieved 2026-10-01)
#' @measure
county_disease_profile <- function(county, year, surveillance) {
  cases <- dplyr::tbl(
    surveillance,
    I("public_health_demo.surveillance.infectious_disease_cases")
  ) |>
    dplyr::filter(sex == "Total")

  county_year <- cases |>
    dplyr::filter(county == !!county, year == !!as.integer(year)) |>
    dplyr::select(disease, cases, rate_per_100k, rate_unstable)

  state_year <- cases |>
    dplyr::filter(is_statewide, year == !!as.integer(year)) |>
    dplyr::select(disease, state_rate = rate_per_100k)

  county_year |>
    dplyr::left_join(state_year, by = "disease") |>
    dplyr::filter(is.na(cases) | cases > 0) |>
    dplyr::arrange(dplyr::desc(rate_per_100k)) |>
    dplyr::collect() |>
    dplyr::mutate(county_to_state_ratio = rate_per_100k / state_rate)
}
