# Posit + Databricks: secure, governed analytics for public health

Materials from the Posit webinar for the California Department of Public Health. The repo shows best practices for working with Databricks from **R and Python** on **Posit Workbench**, and for publishing data products to **Posit Connect**:

- **No credentials in code.** Workbench-managed credentials and Connect OAuth integrations replace personal access tokens.
- **Let the warehouse do the work.** `dbplyr` (R) and `ibis` (Python) turn dataframe code into SQL that runs in a Databricks SQL warehouse.
- **Govern the data, not every app.** Unity Catalog grants and masks apply to whoever runs the query, in every tool.
- **Viewer identity for apps, service accounts for schedules.**

All R code runs the same in **RStudio** and **Positron**. The Python code runs in Positron, VS Code, or Jupyter.

The demo data is CDPH's public [Infectious Diseases by Disease, County, Year, and Sex](https://data.chhs.ca.gov/dataset/infectious-disease) dataset (2001 to 2023) from the CHHS Open Data Portal.

## What's in the repo

| Path | What it is |
|---|---|
| `slides/index.html` | Webinar slides. Open in a browser. Use the arrow keys to move between slides, `F` for full screen, and `N` for speaker notes. |
| `setup/load_data.py` | Loads the demo data into Unity Catalog and runs the SQL in `setup/sql/` |
| `setup/sql/` | Schema, curated table with column comments and tags, small-cell suppression masks, and grants |
| `demo/r/01-explore-dbplyr.R` | R walkthrough: connect, explore lazily, `show_query()`, collect small results, governance |
| `demo/python/02-ibis-data-management.py` | Python walkthrough: the same analysis in ibis, data validation checks, and publishing a derived table |
| `apps/shiny-dashboard/` | Shiny dashboard that queries Databricks as the viewer on Posit Connect |
| `reports/disease-snapshot.qmd` | Parameterized Quarto report for scheduled rendering with a service account |
| `apps/commons-agent/` | AI data agent built with [commons](https://posit-dev.github.io/commons/). It answers questions from trusted measures, with a model served by Databricks |

## How credentials work

The same connection code authenticates correctly in every environment, with no secrets in the code:

```r
con <- DBI::dbConnect(
  odbc::databricks(),
  httpPath = Sys.getenv("DATABRICKS_HTTP_PATH")
)
```

| Where it runs | Databricks sees | How |
|---|---|---|
| Posit Workbench | You | Workbench-managed Databricks credentials (select Databricks when you start a session) |
| Posit Connect: interactive app | Each viewer | Databricks **viewer** OAuth integration, attached to the content |
| Posit Connect: scheduled report | A service principal | Databricks **service account** OAuth integration |
| Laptop | You | `databricks auth login` (Databricks CLI) |

In R, `odbc::databricks()` checks these in order, and `library(connectcreds)` supplies the Connect token. In Python, `posit-sdk`'s `databricks_config()` does the same thing with explicit strategies (see the ibis script).

## Getting started

### 1. Prerequisites

- A Databricks workspace with Unity Catalog and a SQL warehouse
- Posit Workbench with Databricks managed credentials, or a laptop with the [Databricks CLI](https://docs.databricks.com/dev-tools/cli/)
- The Databricks ODBC driver. It is preinstalled on most Posit Workbench installations. Otherwise, see [Posit's Databricks ODBC guidance](https://docs.posit.co/data-sources/user/databricks/).
- R 4.3 or later, and Python 3.11 or later with [uv](https://docs.astral.sh/uv/)
- **odbc 1.7.0 or later.** Earlier versions of `odbc::databricks()` pick up Connect *viewer* credentials but not *service account* credentials.

### 2. Configure

```bash
cp .Renviron.example ~/.Renviron
```

Edit `DATABRICKS_HTTP_PATH` to match your SQL warehouse, and restart R. On Workbench, `DATABRICKS_HOST` is set for you.

To export the same variables for Python and the setup script, run `export DATABRICKS_HTTP_PATH=...` in the terminal, or use a `.env` file.

### 3. Install packages

```r
install.packages(c(
  "DBI", "odbc", "dbplyr", "dplyr", "ggplot2", "connectcreds",
  "shiny", "bslib", "bsicons", "plotly", "reactable", "gt", "rsconnect"
))
```

```bash
uv sync
```

### 4. Load the demo data (one time)

This step needs permission to create a catalog, or an existing catalog you own (set `DEMO_CATALOG`).

```bash
DATABRICKS_WAREHOUSE_ID=<warehouse-id> uv run setup/load_data.py
```

The script creates:

- `public_health_demo.surveillance.idb_raw`: the source file, as published
- `public_health_demo.surveillance.infectious_disease_cases`: typed, documented, and tagged
- Column masks that suppress counts of 1 to 10, and the matching rates and confidence intervals, for anyone outside the `phi_unmasked` group
- `public_health_demo.analyst_sandbox`: a schema analysts can write derived tables to

The source data is already public and de-identified. The masks show the *kind* of rule you would apply to sensitive data. In production, use account-level groups synced from your identity provider, with `is_account_group_member()`.

### 5. Run the walkthroughs

- **R:** open `demo/r/01-explore-dbplyr.R` and run it section by section.
- **Python:** open `demo/python/02-ibis-data-management.py` and run it cell by cell (`# %%`).

### 6. Publish to Posit Connect

**Shiny dashboard (viewer credentials)**

1. Publish `apps/shiny-dashboard/` with the Publish button in RStudio or Positron, `rsconnect::deployApp("apps/shiny-dashboard")`, or Git-backed deployment (a `manifest.json` is included).
2. In the content settings on Connect:
   - **Vars:** set `DATABRICKS_HOST` and `DATABRICKS_HTTP_PATH`.
   - **Access › Integrations:** add your Databricks **viewer** integration.
3. Open the app. The sidebar shows which Databricks identity is running the queries.

**Commons AI agent (viewer credentials)**

1. Run `Rscript deploy.R` from `apps/commons-agent/`. It prewarms the context index and deploys the app.
2. Set the same vars, and attach the same Databricks **viewer** integration. The integration's scopes must allow **model serving** as well as SQL (for example, `all-apis`), because the agent calls a Databricks serving endpoint as the viewer.
3. Optional: set `COMMONS_MODEL` to use a different serving endpoint (default `databricks-claude-sonnet-5-5`).

**Quarto report (service account)**

1. Publish `reports/` (a `manifest.json` is included), with the same vars. On Kubernetes-based Connect, choose an execution image that includes both Quarto and the Databricks ODBC driver (for example, a Posit Pro Drivers image).
2. Attach a Databricks **service account** integration, then schedule it.
3. Grant the service principal access to only the data the report's audience may see.

An administrator sets up each integration once. See [Databricks configuration for Posit Workbench and Posit Connect](https://docs.posit.co/data-sources/admin/databricks.html).

## The commons agent

[commons](https://posit-dev.github.io/commons/) builds AI data agents that put trusted code first. Each answer is labeled by how it was produced:

- **Verified:** the agent ran a *measure*, a trusted calculation extracted from existing code. The measures in `apps/commons-agent/measures/` come from the dashboard, the report, and the R walkthrough, and each one cites its source with `@provenance`.
- **Cited:** the agent wrote new SQL and cited the documentation that supports it (`dictionaries/` and `context/`, taken from CDPH's published data dictionary).
- **Untrusted:** neither trusted code nor supporting documentation was found.

The agent uses the same per-session Databricks connection as the dashboard, so Unity Catalog masks apply to its answers too. The model is Claude, served by Databricks Model Serving, so there is no external API key and the same viewer identity authorizes both the queries and the model calls.

Note: commons recognizes Databricks connections by the ODBC driver name. Some installations register the older Simba Spark ODBC driver under the name "Databricks", which commons does not recognize. With that driver, data dictionary `definitions` cannot be compiled, so this agent does not use them.

## Notes and best practices in the code

- **Connect inside `server()`.** With viewer credentials, each Shiny session needs its own connection, authenticated as that viewer. A connection at the top of `app.R` is shared by everyone. Close it with `session$onSessionEnded()`.
- **Mask derived values too.** A rate multiplied by its population gives the count back, so the setup masks rates and confidence intervals wherever the count is suppressed.
- **Derived tables inherit the author's view.** A table you build (like `county_disease_trends`) contains what *you* could see when you built it. Build shared derived tables with a pipeline identity, and govern them with their own grants.
- **Parameterize SQL.** Use `DBI::sqlInterpolate()` or dbplyr (`!!`) instead of `paste()` to build queries from user input.
- **`bigint = "numeric"`** returns Databricks `BIGINT` columns as ordinary R numbers instead of `integer64`.
- **ibis and sqlglot:** `pyproject.toml` pins `sqlglot<30.18`, because sqlglot 30.18 breaks table lookups in the ibis 12 Databricks backend.

## Resources

- [Posit and Databricks: connection patterns](https://docs.posit.co/data-sources/user/databricks/)
- [Workbench-managed Databricks credentials](https://docs.posit.co/ide/server-pro/user/posit-workbench/managed-credentials/databricks.html)
- [Posit Connect OAuth integrations](https://docs.posit.co/connect/user/oauth-integrations/)
- [commons](https://posit-dev.github.io/commons/) · [dbplyr](https://dbplyr.tidyverse.org/) · [ibis](https://ibis-project.org/) · [Unity Catalog row filters and column masks](https://docs.databricks.com/en/tables/row-and-column-filters.html)
