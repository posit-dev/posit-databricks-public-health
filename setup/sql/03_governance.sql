-- 03: Governance in the platform, not in every app.
--
-- Small-cell suppression as a Unity Catalog column mask. Anyone querying the
-- table (Databricks SQL, a notebook, R, Python, a Shiny app on Posit Connect)
-- gets the same rule applied for their own identity.
--
-- Members of `${unmasked_group}` see exact counts. Everyone else sees counts of
-- 1-10 as NULL. The demo dataset is already public; the mask simulates the
-- kind of rule you would apply to line-level or sensitive data.
--
-- Note: this demo uses a workspace-local group with is_member(). In production,
-- prefer account-level groups (synced from your IdP) with is_account_group_member().

CREATE OR REPLACE FUNCTION ${catalog}.surveillance.mask_small_cells(cases INT)
  RETURNS INT
  COMMENT 'Suppresses case counts between 1 and 10 unless the caller is authorized to see unsuppressed data'
  RETURN CASE
    WHEN is_member('${unmasked_group}') THEN cases
    WHEN cases BETWEEN 1 AND 10 THEN NULL
    ELSE cases
  END;

ALTER TABLE ${catalog}.surveillance.infectious_disease_cases
  ALTER COLUMN cases SET MASK ${catalog}.surveillance.mask_small_cells;

-- Rates and confidence intervals can be multiplied back into a count
-- (rate x population), so suppress them wherever the count is suppressed.
CREATE OR REPLACE FUNCTION ${catalog}.surveillance.mask_rate_for_small_cells(value DOUBLE, cases INT)
  RETURNS DOUBLE
  COMMENT 'Suppresses rate-type values where the underlying case count is between 1 and 10, unless the caller is authorized'
  RETURN CASE
    WHEN is_member('${unmasked_group}') THEN value
    WHEN cases BETWEEN 1 AND 10 THEN NULL
    ELSE value
  END;

ALTER TABLE ${catalog}.surveillance.infectious_disease_cases
  ALTER COLUMN rate_per_100k SET MASK ${catalog}.surveillance.mask_rate_for_small_cells USING COLUMNS (cases);

ALTER TABLE ${catalog}.surveillance.infectious_disease_cases
  ALTER COLUMN ci_lower_95 SET MASK ${catalog}.surveillance.mask_rate_for_small_cells USING COLUMNS (cases);

ALTER TABLE ${catalog}.surveillance.infectious_disease_cases
  ALTER COLUMN ci_upper_95 SET MASK ${catalog}.surveillance.mask_rate_for_small_cells USING COLUMNS (cases);

-- Read access for analysts
GRANT USE CATALOG ON CATALOG ${catalog} TO `${reader_group}`;
GRANT USE SCHEMA, SELECT, EXECUTE ON SCHEMA ${catalog}.surveillance TO `${reader_group}`;
-- A sandbox schema analysts can write derived tables into (used by the Python demo)
CREATE SCHEMA IF NOT EXISTS ${catalog}.analyst_sandbox
  COMMENT 'Derived tables written by analysts from Posit Workbench';
GRANT USE SCHEMA, SELECT, CREATE TABLE, MODIFY ON SCHEMA ${catalog}.analyst_sandbox TO `${reader_group}`;
