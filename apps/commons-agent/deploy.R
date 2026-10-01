# Prewarm the context index, then deploy to Posit Connect.
# Run from this directory: Rscript deploy.R
#
# After the first deploy, in the content settings on Connect:
#   - Vars: DATABRICKS_HOST and DATABRICKS_HTTP_PATH
#   - Access > Integrations: add the Databricks viewer integration. Its scopes
#     must cover SQL and model serving (for example, "all-apis").

source("agent.R", local = TRUE)
agent <- build_agent()
agent$prewarm()

app_files <- c(
  "app.R",
  "agent.R",
  "DESCRIPTION",
  list.files("dictionaries", full.names = TRUE),
  list.files("measures", full.names = TRUE),
  list.files("context", full.names = TRUE),
  list.files("commons-cache", recursive = TRUE, full.names = TRUE)
)

rsconnect::deployApp(
  appDir = ".",
  appFiles = app_files,
  appPrimaryDoc = "app.R",
  appTitle = "California communicable disease agent"
)
