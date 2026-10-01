# Python + Databricks with ibis
# ---------------------------------------------------------------------------
# Same question as the R script, same mental model: write dataframe code,
# Databricks runs it as SQL, and only small results come back to Python.
#
# Then a common data-management task: validate the source and publish a
# derived table back to Unity Catalog for other teams (and tools) to use.
#
# Run cell by cell (# %%) in Positron, VS Code, or Jupyter on Posit Workbench.

# %% Connect -----------------------------------------------------------------
import os

import ibis
from databricks.sdk.core import databricks_cli
from posit.connect.external.databricks import ConnectStrategy, databricks_config
from posit.workbench.external.databricks import WorkbenchStrategy

ibis.options.interactive = True

host = os.environ["DATABRICKS_HOST"].removeprefix("https://").rstrip("/")
http_path = os.environ["DATABRICKS_HTTP_PATH"]

# One config, three environments, no secrets in code:
#   Posit Workbench -> Workbench-managed Databricks credentials (your identity)
#   Posit Connect   -> Connect's Databricks OAuth integration
#   Your laptop     -> the Databricks CLI (`databricks auth login`)
cfg = databricks_config(
    posit_workbench_strategy=WorkbenchStrategy(),
    posit_connect_strategy=ConnectStrategy(),
    posit_default_strategy=databricks_cli,
    host=f"https://{host}",
)

con = ibis.databricks.connect(
    server_hostname=host,
    http_path=http_path,
    credentials_provider=lambda: cfg.authenticate,
    catalog="public_health_demo",
    schema="surveillance",
)

con.sql("SELECT current_user() AS me").to_pandas()

# %% A lazy table expression ---------------------------------------------------
cases = con.table("infectious_disease_cases")
cases.schema()

# %% Same question as in R: Valley Fever, statewide rate by year ----------------
_ = ibis._  # deferred column reference, like a bare column name in dplyr

valley_fever = (
    cases.filter(
        _.disease == "Coccidioidomycosis",
        _.sex == "Total",
        _.is_statewide,
    )
    .select("year", "cases", "population", "rate_per_100k")
    .order_by("year")
)

# Nothing has run yet. This is the SQL ibis will send to Databricks:
print(ibis.to_sql(valley_fever))

# %% Execute in Databricks and bring back 23 rows --------------------------------
valley_fever_df = valley_fever.to_pandas()
valley_fever_df.tail()

# %% Data management: validate before you publish ----------------------------------
# These checks all run in the warehouse; the results are a handful of numbers.
checks = cases.aggregate(
    rows=_.count(),
    years=_.year.nunique(),
    counties=_.county.nunique(),
    diseases=_.disease.nunique(),
    suppressed_counts=_.cases.isnull().sum(),
    negative_counts=(_.cases < 0).sum(),
    missing_population=_.population.isnull().sum(),
)
checks.to_pandas().T

# %% Duplicate key check: one row per disease/county/year/sex ------------------------
dupes = (
    cases.group_by(["disease", "county", "year", "sex"])
    .aggregate(n=_.count())
    .filter(_.n > 1)
)
assert dupes.count().to_pyarrow().as_py() == 0, "Duplicate keys found"

# %% Build a derived table: county trends, recent 5 years vs the prior 5 ---------------
period = ibis.cases(
    (_.year.between(2019, 2023), "recent"),
    (_.year.between(2014, 2018), "prior"),
)

county_trends = (
    cases.filter(_.sex == "Total", ~_.is_statewide)
    .mutate(period=period)
    .filter(_.period.notnull())
    .group_by(["disease", "county", "period"])
    .aggregate(cases=_.cases.sum(), person_years=_.population.sum())
    .mutate(rate_per_100k=_.cases / _.person_years * 100_000)
    .pivot_wider(
        id_cols=["disease", "county"],
        names_from="period",
        values_from=["cases", "rate_per_100k"],
    )
    .mutate(
        rate_change_pct=(_.rate_per_100k_recent / _.rate_per_100k_prior - 1) * 100,
    )
)

county_trends.filter(_.disease == "Coccidioidomycosis").order_by(
    ibis.desc("rate_per_100k_recent")
).head(10)

# %% Publish back to Unity Catalog ---------------------------------------------------
# Written to a sandbox schema the analyst group can write to. Unity Catalog
# records lineage from this table back to infectious_disease_cases.
# Note: the table is built with *your* permissions, so any masked values you
# can't see stay masked in the output.
con.create_table(
    "county_disease_trends",
    obj=county_trends,
    database=("public_health_demo", "analyst_sandbox"),
    overwrite=True,
)

con.table("county_disease_trends", database=("public_health_demo", "analyst_sandbox")).count()

# %% Clean up ------------------------------------------------------------------------
con.disconnect()
