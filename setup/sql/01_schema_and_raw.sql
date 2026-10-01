-- 01: Schema, landing volume, and raw (bronze) table
-- The raw CSV is uploaded to the volume by setup/load_data.py before this runs.

CREATE SCHEMA IF NOT EXISTS ${catalog}.surveillance
  COMMENT 'Communicable disease surveillance data used in the Posit + Databricks demo';

CREATE VOLUME IF NOT EXISTS ${catalog}.surveillance.landing
  COMMENT 'Landing zone for raw source files';

-- Keep the raw file exactly as published: every column as a string.
CREATE OR REPLACE TABLE ${catalog}.surveillance.idb_raw
  COMMENT 'Raw load of the CDPH "Infectious Diseases by Disease, County, Year, and Sex" open dataset (data.chhs.ca.gov). Do not use directly; see infectious_disease_cases.'
AS SELECT *, _metadata.file_name AS source_file, current_timestamp() AS loaded_at
FROM read_files(
  '/Volumes/${catalog}/surveillance/landing/idb/',
  format => 'csv',
  header => true,
  inferSchema => false
);
