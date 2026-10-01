# Communicable disease data agent, built with commons
# ---------------------------------------------------------------------------
# Ask questions in plain language. Answers that come from trusted code are
# marked "Verified"; answers the agent had to write new code for are marked
# "Cited" or "Untrusted", so you always know how much to trust a result.
#
# Required environment variables (set in Connect under "Vars"):
#   DATABRICKS_HOST       e.g. https://adb-1234567890.12.azuredatabricks.net
#   DATABRICKS_HTTP_PATH  e.g. /sql/1.0/warehouses/abc123
# Optional:
#   COMMONS_MODEL         Databricks serving endpoint (default databricks-claude-sonnet-5-5)

source("agent.R", local = TRUE)

greeting <- paste(
  "Ask about reported communicable disease cases and rates in California,",
  "2001 to 2023, by county. Answers are labeled by how they were produced.",
  "\n\nTry one of these questions:\n\n",
  "- <span class='suggestion'>How has the Valley Fever rate in Kern County changed since 2010, compared with the state?</span>\n",
  "- <span class='suggestion'>Which counties had the highest Salmonellosis rates in 2023?</span>\n",
  "- <span class='suggestion'>Which diseases were most elevated in Fresno County compared with the state in 2022?</span>\n",
  "- <span class='suggestion'>Which disease has grown fastest statewide over the last ten years?</span>"
)

ui <- shinychat::page_chat(
  "California communicable disease agent",
  id = "chat",
  greeting = greeting,
  theme = commons::commons_theme()
)

server <- function(input, output, session) {
  # A fresh agent, with its own Databricks connection, for every session.
  # On Connect, that connection and the LLM calls run as the viewer.
  agent <- build_agent()
  commons::commons_server("chat", agent)
}

shiny::shinyApp(ui, server)
