# Builds the commons agent. Sourced by app.R (once per Shiny session) and by
# deploy.R (to prewarm the context index before deploying).
#
# Both the SQL connection and the LLM authenticate the same way as the rest of
# this repo, with no secrets in code:
#   Posit Connect   -> the viewer's Databricks OAuth token (connectcreds)
#   Posit Workbench -> Workbench-managed Databricks credentials
#   Laptop          -> the Databricks CLI
#
# The LLM is Claude, served by Databricks Model Serving in the same workspace,
# so prompts and query results stay inside the Databricks governance boundary.

library(connectcreds)

options(commons.context_cache = "commons-cache")

build_agent <- function(log = FALSE) {
  con <- DBI::dbConnect(
    odbc::databricks(),
    httpPath = Sys.getenv("DATABRICKS_HTTP_PATH"),
    bigint = "numeric"
  )

  client <- ellmer::chat_databricks(
    model = Sys.getenv("COMMONS_MODEL", "databricks-claude-sonnet-5-5"),
    api_args = list(thinking = list(type = "adaptive"))
  )

  commons::commons(
    client = client,
    data_sources = list(
      surveillance = commons::data_source(
        con,
        tables = "public_health_demo.surveillance.infectious_disease_cases",
        dictionary = "dictionaries/surveillance.yaml"
      )
    ),
    semantic_layer = commons::semantic_layer("measures"),
    context_layer = commons::context_layer(
      files = list.files("context", pattern = "\\.md$", full.names = TRUE)
    ),
    log = log
  )
}
