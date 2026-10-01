# California Communicable Disease Explorer
# ---------------------------------------------------------------------------
# A Shiny app that queries Databricks live, as the person viewing it.
#
# Locally / on Workbench: queries run as you (Workbench-managed credentials
#   or the Databricks CLI).
# On Posit Connect: add the Databricks OAuth integration to this content
#   (Access > Integrations) and every viewer queries Databricks as
#   themselves. Unity Catalog permissions and masks apply per viewer.
#
# Required environment variables (set in Connect under "Vars"):
#   DATABRICKS_HOST       e.g. https://adb-1234567890.12.azuredatabricks.net
#   DATABRICKS_HTTP_PATH  e.g. /sql/1.0/warehouses/abc123

library(shiny)
library(bslib)
library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(dbplyr, warn.conflicts = FALSE)
library(plotly, warn.conflicts = FALSE)
library(reactable)
library(connectcreds) # supplies viewer credentials when running on Connect

source_table <- I("public_health_demo.surveillance.infectious_disease_cases")
unmasked_group <- "phi_unmasked"

posit_blue <- "#447099"
posit_orange <- "#EE6331"
posit_gray <- "#404041"

theme <- bs_theme(
  version = 5,
  primary = posit_blue,
  secondary = posit_gray,
  fg = posit_gray,
  bg = "#FFFFFF",
  base_font = font_google("Open Sans", wght = c(300, 400, 700)),
  code_font = font_google("Source Code Pro"),
  "headings-font-weight" = 300
)

ui <- page_sidebar(
  title = "California communicable disease explorer",
  theme = theme,
  fillable = TRUE,
  sidebar = sidebar(
    width = 300,
    selectInput("disease", "Disease", choices = NULL),
    selectInput("county", "County", choices = NULL),
    sliderInput(
      "years", "Years",
      min = 2001, max = 2023, value = c(2010, 2023), sep = "", step = 1
    ),
    hr(),
    uiOutput("identity")
  ),
  layout_columns(
    fill = FALSE,
    value_box(
      title = textOutput("latest_year_label", inline = TRUE),
      value = textOutput("latest_cases"),
      showcase = bsicons::bs_icon("clipboard2-pulse"),
      theme = value_box_theme(bg = "#FFFFFF", fg = posit_gray),
      p(textOutput("latest_rate", inline = TRUE))
    ),
    value_box(
      title = "Change vs. 5 years earlier",
      value = textOutput("rate_change"),
      showcase = bsicons::bs_icon("graph-up-arrow"),
      theme = value_box_theme(bg = "#FFFFFF", fg = posit_gray),
      p("Incidence rate per 100,000")
    ),
    value_box(
      title = "Suppressed cells in view",
      value = textOutput("suppressed_count"),
      showcase = bsicons::bs_icon("shield-lock"),
      theme = value_box_theme(bg = "#FFFFFF", fg = posit_gray),
      p("Counts of 1-10 (and their rates) hidden by Unity Catalog")
    )
  ),
  layout_columns(
    col_widths = c(7, 5),
    card(
      full_screen = TRUE,
      card_header(textOutput("trend_title", inline = TRUE)),
      plotlyOutput("trend_plot")
    ),
    card(
      full_screen = TRUE,
      card_header("Counties, most recent year selected"),
      reactableOutput("county_table")
    )
  ),
  tags$footer(
    class = "text-muted small px-1",
    "Source: CDPH Infectious Diseases Branch, CHHS Open Data Portal. ",
    "Unstable rates have a relative standard error of 23% or more."
  )
)

server <- function(input, output, session) {
  # One connection per session, opened inside server(): on Connect each
  # viewer gets a connection authenticated as *them*. Never open a
  # viewer-credential connection at the top level of app.R.
  con <- dbConnect(
    odbc::databricks(),
    httpPath = Sys.getenv("DATABRICKS_HTTP_PATH"),
    bigint = "numeric"
  )
  session$onSessionEnded(function() dbDisconnect(con))

  cases <- tbl(con, source_table) |> filter(sex == "Total")

  who <- dbGetQuery(
    con,
    sprintf(
      "SELECT current_user() AS user, is_member('%s') AS unmasked",
      unmasked_group
    )
  )

  output$identity <- renderUI({
    tagList(
      div(class = "text-uppercase small text-muted", "Querying Databricks as"),
      div(tags$strong(who$user)),
      div(
        class = "small mt-2",
        if (isTRUE(who$unmasked)) {
          "Small-cell suppression: off (authorized)"
        } else {
          "Small-cell suppression: on"
        }
      )
    )
  })

  # Populate inputs from the data, in the warehouse
  diseases <- cases |> distinct(disease) |> arrange(disease) |> pull()
  counties <- cases |> distinct(county) |> arrange(county) |> pull()
  updateSelectInput(session, "disease", choices = diseases, selected = "Coccidioidomycosis")
  updateSelectInput(
    session, "county",
    choices = c("California (statewide)" = "California", setdiff(counties, "California")),
    selected = "Kern"
  )

  # Time series for the selected county and the state: ~50 rows come back
  trend <- reactive({
    req(input$disease, input$county)
    cases |>
      filter(
        disease == !!input$disease,
        county %in% !!unique(c(input$county, "California")),
        between(year, !!input$years[1], !!input$years[2])
      ) |>
      select(county, year, cases, population, rate_per_100k, rate_unstable) |>
      arrange(year) |>
      collect()
  })

  # County snapshot for the last selected year: 58 rows come back
  snapshot <- reactive({
    req(input$disease)
    cases |>
      filter(
        disease == !!input$disease,
        !is_statewide,
        year == !!input$years[2]
      ) |>
      select(county, cases, rate_per_100k, rate_unstable) |>
      arrange(desc(rate_per_100k)) |>
      collect()
  })

  selected <- reactive(filter(trend(), county == input$county))

  output$latest_year_label <- renderText({
    paste0("Reported cases, ", input$years[2])
  })

  output$latest_cases <- renderText({
    latest <- filter(selected(), year == max(year))
    if (nrow(latest) == 0) return("-")
    if (is.na(latest$cases)) "Suppressed" else format(latest$cases, big.mark = ",")
  })

  output$latest_rate <- renderText({
    latest <- filter(selected(), year == max(year))
    if (nrow(latest) == 0) return("")
    if (is.na(latest$cases)) return("1-10 cases; rate also suppressed")
    if (is.na(latest$rate_per_100k)) return("Rate not calculated")
    paste0(
      format(round(latest$rate_per_100k, 1), nsmall = 1), " per 100,000",
      if (isTRUE(latest$rate_unstable)) " (unstable)" else ""
    )
  })

  output$rate_change <- renderText({
    d <- selected()
    end <- max(d$year)
    now <- d$rate_per_100k[d$year == end]
    before <- d$rate_per_100k[d$year == end - 5]
    if (length(now) == 0 || length(before) == 0 || is.na(before) || before == 0) {
      return("-")
    }
    sprintf("%+.0f%%", (now / before - 1) * 100)
  })

  output$suppressed_count <- renderText({
    format(sum(is.na(snapshot()$cases)) + sum(is.na(selected()$cases)), big.mark = ",")
  })

  output$trend_title <- renderText({
    paste(input$disease, "incidence per 100,000")
  })

  output$trend_plot <- renderPlotly({
    d <- trend() |>
      mutate(
        series = if_else(county == "California", "California (statewide)", county),
        label = paste0(
          series, ", ", year, "<br>",
          "Rate: ", if_else(is.na(rate_per_100k), "suppressed", as.character(round(rate_per_100k, 2))),
          if_else(rate_unstable, " (unstable)", ""),
          "<br>Cases: ", if_else(is.na(cases), "1-10 (suppressed)", format(cases, big.mark = ","))
        )
      )
    colors <- c(posit_blue, posit_orange)
    names(colors) <- c(
      if_else(input$county == "California", "California (statewide)", input$county),
      "California (statewide)"
    )
    plot_ly(
      d,
      x = ~year, y = ~rate_per_100k, color = ~series, colors = colors,
      type = "scatter", mode = "lines+markers",
      text = ~label, hoverinfo = "text"
    ) |>
      layout(
        xaxis = list(title = ""),
        yaxis = list(title = "Rate per 100,000", rangemode = "tozero"),
        legend = list(orientation = "h", y = -0.15),
        font = list(family = "Open Sans", color = posit_gray)
      ) |>
      config(displayModeBar = FALSE)
  })

  output$county_table <- renderReactable({
    reactable(
      snapshot(),
      compact = TRUE,
      searchable = TRUE,
      pagination = FALSE,
      height = 420,
      columns = list(
        county = colDef(name = "County"),
        cases = colDef(
          name = "Cases",
          na = "1-10",
          style = function(value) if (is.na(value)) list(color = "#717171", fontStyle = "italic")
        ),
        rate_per_100k = colDef(
          name = "Rate",
          na = "-",
          format = colFormat(digits = 1)
        ),
        rate_unstable = colDef(
          name = "Unstable",
          cell = function(value) if (isTRUE(value)) "Yes" else ""
        )
      )
    )
  })
}

shinyApp(ui, server)
