"""Build the demo data in Databricks Unity Catalog.

Downloads the public CDPH "Infectious Diseases by Disease, County, Year, and Sex"
dataset, uploads it to a Unity Catalog volume, and runs the SQL in setup/sql/.

Run once, as a user who can create catalogs/schemas (or point CATALOG at one
you own):

    export DATABRICKS_CONFIG_PROFILE=DEFAULT   # or DATABRICKS_HOST + auth of your choice
    export DATABRICKS_WAREHOUSE_ID=<sql-warehouse-id>
    uv run setup/load_data.py

Optional environment variables:
    DEMO_CATALOG        catalog to use (default: public_health_demo)
    DEMO_UNMASKED_GROUP group allowed to see unsuppressed counts (default: phi_unmasked)
    DEMO_READER_GROUP   group granted read access (default: account users)
    DEMO_SOURCE_CSV     path to an already-downloaded copy of the source CSV
"""

import os
import re
import subprocess
from pathlib import Path

from databricks.sdk import WorkspaceClient
from databricks.sdk.service.sql import StatementState

SOURCE_URL = (
    "https://data.chhs.ca.gov/dataset/03e61434-7db8-4a53-a3e2-1d4d36d6848d/"
    "resource/75019f89-b349-4d5e-825d-8b5960fc028c/download/"
    "odp_idb_2001-2023_ddg_compliant.csv"
)

params = {
    "catalog": os.environ.get("DEMO_CATALOG", "public_health_demo"),
    "unmasked_group": os.environ.get("DEMO_UNMASKED_GROUP", "phi_unmasked"),
    "reader_group": os.environ.get("DEMO_READER_GROUP", "account users"),
}
warehouse_id = os.environ["DATABRICKS_WAREHOUSE_ID"]
sql_dir = Path(__file__).parent / "sql"

w = WorkspaceClient()  # Databricks unified auth: profile, env vars, CLI, or Workbench


def run_sql(statement: str) -> None:
    resp = w.statement_execution.execute_statement(
        statement=statement, warehouse_id=warehouse_id, wait_timeout="50s"
    )
    while resp.status.state in (StatementState.PENDING, StatementState.RUNNING):
        resp = w.statement_execution.get_statement(resp.statement_id)
    if resp.status.state != StatementState.SUCCEEDED:
        raise RuntimeError(f"{resp.status.error}\n---\n{statement}")


def run_sql_file(path: Path) -> None:
    text = path.read_text()
    for key, value in params.items():
        text = text.replace("${" + key + "}", value)
    text = "\n".join(l for l in text.splitlines() if not l.strip().startswith("--"))
    for statement in re.split(r";\s*\n", text):
        if statement.strip():
            print(f"  > {statement.strip().splitlines()[0][:90]}")
            run_sql(statement)


catalog = params["catalog"]

print("Creating schema and volume")
run_sql(f"CREATE CATALOG IF NOT EXISTS {catalog}")
run_sql(f"CREATE SCHEMA IF NOT EXISTS {catalog}.surveillance")
run_sql(f"CREATE VOLUME IF NOT EXISTS {catalog}.surveillance.landing")

print("Downloading source data from the CHHS Open Data Portal")
local_csv = Path(os.environ.get("DEMO_SOURCE_CSV", "/tmp/idb_2001_2023.csv"))
if not local_csv.exists():
    subprocess.run(["curl", "-sSfL", "-o", str(local_csv), SOURCE_URL], check=True)

print("Uploading to Unity Catalog volume")
with local_csv.open("rb") as f:
    w.files.upload(
        f"/Volumes/{catalog}/surveillance/landing/idb/idb_2001_2023.csv", f, overwrite=True
    )

print("Ensuring the unmasked-data group exists (membership is managed separately)")
if not list(w.groups.list(filter=f'displayName eq "{params["unmasked_group"]}"')):
    w.groups.create(display_name=params["unmasked_group"])

for sql_file in sorted(sql_dir.glob("*.sql")):
    print(f"Running {sql_file.name}")
    run_sql_file(sql_file)

print("Done.")
