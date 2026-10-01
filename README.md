# Posit + Databricks for public health

This repository has the materials from a Posit webinar for the California Department of Public Health. It shows good practices for R and Python work with Databricks in Posit Workbench and Posit Connect.

All R code works the same in RStudio and in Positron.

## The main ideas

- **No credentials in code.** Posit Workbench and Posit Connect sign in to Databricks for you, with short-lived tokens.
- **Databricks does the work.** dbplyr (R) and ibis (Python) change your data frame code into SQL. Only small results come back to your session.
- **Rules live in the data platform.** Unity Catalog permissions and masks apply to each person, in every tool.

## What is in this repository

| Folder | Contents |
|---|---|
| `slides/` | The webinar slides, made with Quarto. |
| `setup/` | A script and SQL files that load the demo data into Unity Catalog. |
| `demo/r/` | An R walkthrough with DBI, odbc, and dbplyr. |
| `demo/python/` | A Python walkthrough with ibis. |
| `apps/shiny-dashboard/` | A Shiny dashboard. On Connect, it reads data as the person who views it. |
| `apps/commons-agent/` | An AI data agent made with [commons](https://posit-dev.github.io/commons/). |
| `reports/` | A Quarto report for scheduled runs on Connect. |

## The data

The demo uses the public CDPH dataset [Infectious Diseases by Disease, County, Year, and Sex](https://data.chhs.ca.gov/dataset/infectious-disease), 2001 to 2023. It comes from the CHHS Open Data Portal.

The setup adds a small-cell rule to this data. For most users, counts from 1 to 10 show as empty. The rates for these counts also show as empty. Only members of the `phi_unmasked` group see these values.

The data is already public. The rule is an example of what you can do with sensitive data. In production, use account-level groups from your identity provider, with `is_account_group_member()`.

## How sign-in works

The connection code is the same everywhere:

```r
con <- DBI::dbConnect(
  odbc::databricks(),
  httpPath = Sys.getenv("DATABRICKS_HTTP_PATH")
)
```

Databricks sees a different identity in each place:

| Where the code runs | Who Databricks sees | How |
|---|---|---|
| Posit Workbench | You | Workbench-managed Databricks credentials |
| Posit Connect, interactive app | Each viewer | A Databricks **viewer** OAuth integration |
| Posit Connect, scheduled report | A service principal | A Databricks **service account** OAuth integration |
| Your laptop | You | The Databricks CLI (`databricks auth login`) |

In Python, the `databricks_config()` function from `posit-sdk` does the same job. The ibis walkthrough shows how to use it.

## Before you start

You need:

- A Databricks workspace with Unity Catalog and a SQL warehouse.
- Posit Workbench with Databricks managed credentials, or a laptop with the [Databricks CLI](https://docs.databricks.com/dev-tools/cli/).
- The Databricks ODBC driver. Most Posit Workbench and Posit Connect servers have it.
- R 4.3 or later, with odbc 1.7.0 or later. Older versions of odbc do not support service accounts on Connect.
- Python 3.11 or later, with [uv](https://docs.astral.sh/uv/).

## Set up

1. Copy the example environment file:

   ```bash
   cp .env.example .env
   ```

2. In `.env`, set `DATABRICKS_HTTP_PATH` to the HTTP path of your SQL warehouse. In Databricks, you can find it under **SQL Warehouses > Connection details**.

3. If you use a laptop, also add `DATABRICKS_HOST` to `.env`. On Posit Workbench, this value is already set.

4. Install the R packages:

   ```r
   install.packages(c(
     "DBI", "odbc", "dbplyr", "dplyr", "ggplot2", "connectcreds",
     "shiny", "bslib", "bsicons", "plotly", "reactable", "gt",
     "commons", "shinychat", "ellmer", "rsconnect"
   ))
   ```

5. Install the Python packages:

   ```bash
   uv sync
   ```

6. Load the demo data. You need permission to make a catalog. To use a catalog that you own, set `DEMO_CATALOG`.

   ```bash
   DATABRICKS_WAREHOUSE_ID=<warehouse-id> uv run setup/load_data.py
   ```

## Run the walkthroughs

Open the project folder in RStudio or Positron. The scripts read `.env` from the project folder.

- **R:** Open `demo/r/01-explore-dbplyr.R`. Run it one section at a time.
- **Python:** Open `demo/python/02-ibis-data-management.py`. Run it one cell (`# %%`) at a time.

## Publish to Posit Connect

An administrator sets up each Databricks integration on Connect one time. For the steps, read [Databricks configuration for Posit Workbench and Posit Connect](https://docs.posit.co/data-sources/admin/databricks.html).

### Shiny dashboard

1. Publish `apps/shiny-dashboard/`. Use the **Publish** button in RStudio or Positron, or `rsconnect::deployApp()`.
2. On Connect, open the content settings. Under **Vars**, add `DATABRICKS_HOST` and `DATABRICKS_HTTP_PATH`.
3. Under **Access > Integrations**, add the Databricks viewer integration.

The sidebar of the app shows the Databricks identity that runs the queries.

### Commons AI agent

1. In `apps/commons-agent/`, run `deploy.R`. This script prepares the agent and publishes it.
2. Add the same Vars and the same viewer integration as for the dashboard.

The agent uses Claude through Databricks Model Serving. Thus, it does not need a key from an AI provider. The viewer integration must give access to model serving and to SQL. To use a different model, set the `COMMONS_MODEL` variable to the name of a serving endpoint.

### Quarto report

1. Publish `reports/`, with the same Vars.
2. Under **Access > Integrations**, add a Databricks service account integration.
3. Set a schedule.

Give the service principal access only to data that all readers of the report can see. If your Connect server uses Kubernetes, use an image that has Quarto and the Databricks ODBC driver.

## Good practices in this code

- **One connection per Shiny session.** The dashboard connects inside `server()`. Thus, each viewer has a connection with their own identity.
- **Mask values that can show a hidden count.** A rate multiplied by its population gives the count. For this reason, the setup also masks rates when it masks a count.
- **Know who made a derived table.** A table that you make contains only the data that you can see.
- **Do not paste user input into SQL.** Use dbplyr, or use `DBI::sqlInterpolate()`.
- **Keep settings out of code.** The warehouse path is in `.env` on your computer, and in Vars on Connect.

## The commons agent

The agent answers questions about the data. It labels each answer to show how it got the result:

- **Verified:** The agent used a trusted measure. Each measure in `apps/commons-agent/measures/` comes from the dashboard, the report, or the R walkthrough.
- **Cited:** The agent wrote new SQL. The documentation in `dictionaries/` and `context/` supports the SQL.
- **Untrusted:** The agent found no trusted measure and no supporting documentation.

The agent uses the same type of connection as the dashboard. Thus, the Unity Catalog masks also apply to its answers.

## The slides

To show the slides, open `slides/index.html` in a web browser. Use the arrow keys to move between slides. Press `F` for full screen, and press `S` for the speaker view.

The slide source is `slides/index.qmd`. The Posit theme is `slides/posit.scss`. After you change these files, render the slides:

```bash
quarto render slides/index.qmd
```

## Known problems

- The ibis 12 Databricks backend does not work with sqlglot 30.18 or later. Thus, `pyproject.toml` keeps sqlglot below 30.18.
- commons identifies a Databricks connection by the name of the ODBC driver. Some servers have an older Simba Spark driver with the name "Databricks". With that driver, commons cannot use `definitions` in a data dictionary. For this reason, the agent does not use them.

## Learn more

- [Posit and Databricks connection patterns](https://docs.posit.co/data-sources/user/databricks/)
- [Workbench-managed Databricks credentials](https://docs.posit.co/ide/server-pro/user/posit-workbench/managed-credentials/databricks.html)
- [Posit Connect OAuth integrations](https://docs.posit.co/connect/user/oauth-integrations/)
- [Unity Catalog row filters and column masks](https://docs.databricks.com/en/tables/row-and-column-filters.html)
- [commons](https://posit-dev.github.io/commons/), [dbplyr](https://dbplyr.tidyverse.org/), and [ibis](https://ibis-project.org/)
