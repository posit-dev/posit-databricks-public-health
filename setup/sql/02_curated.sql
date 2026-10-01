-- 02: Curated (silver) table: typed, documented, analysis-ready.
-- Source conventions (CDPH data dictionary): Rate is '-' when there are zero
-- cases; a trailing '*' marks an unstable rate (relative standard error of 23%
-- or more, the NCHS threshold); 'SC' marks a row CDPH suppressed at the source
-- for small numbers, in which case Cases and the confidence interval are blank.

CREATE OR REPLACE TABLE ${catalog}.surveillance.infectious_disease_cases (
  disease          STRING  COMMENT 'Reportable disease name',
  county           STRING  COMMENT 'California county of residence; "California" is the statewide total',
  year             INT     COMMENT 'Year of episode',
  sex              STRING  COMMENT 'Female, Male, or Total',
  cases            INT     COMMENT 'Cases meeting the surveillance case definition. NULL when suppressed, either by CDPH at the source (see source_suppressed) or by the small-cell column mask',
  population       BIGINT  COMMENT 'Population denominator',
  rate_per_100k    DOUBLE  COMMENT 'Published incidence rate per 100,000: cases * 100,000 / population. 0 when there were no cases; NULL when suppressed or not calculated',
  rate_unstable    BOOLEAN COMMENT 'TRUE when CDPH flags the rate as unstable: relative standard error of 23% or more (NCHS threshold)',
  source_suppressed BOOLEAN COMMENT 'TRUE when CDPH suppressed this row in the published data for small numbers (Rate = SC)',
  ci_lower_95      DOUBLE  COMMENT 'Lower bound of the exact (Clopper-Pearson) 95% confidence interval for the rate',
  ci_upper_95      DOUBLE  COMMENT 'Upper bound of the exact (Clopper-Pearson) 95% confidence interval for the rate',
  is_statewide     BOOLEAN COMMENT 'TRUE for the statewide (California) total rows'
)
COMMENT 'Reported cases of selected communicable diseases by county, year, and sex, 2001-2023. Source: CDPH Infectious Diseases Branch via the CHHS Open Data Portal.';

INSERT INTO ${catalog}.surveillance.infectious_disease_cases
SELECT
  Disease                                              AS disease,
  County                                               AS county,
  CAST(Year AS INT)                                    AS year,
  Sex                                                  AS sex,
  CAST(Cases AS INT)                                   AS cases,
  CAST(Population AS BIGINT)                           AS population,
  CASE WHEN Rate = '-' THEN 0.0
       ELSE TRY_CAST(regexp_replace(Rate, '[^0-9.]', '') AS DOUBLE) END
                                                       AS rate_per_100k,
  Rate LIKE '%*%'                                      AS rate_unstable,
  Rate = 'SC'                                          AS source_suppressed,
  TRY_CAST(Lower_95__CI AS DOUBLE)                     AS ci_lower_95,
  TRY_CAST(Upper_95__CI AS DOUBLE)                     AS ci_upper_95,
  County = 'California'                                AS is_statewide
FROM ${catalog}.surveillance.idb_raw;

ALTER TABLE ${catalog}.surveillance.infectious_disease_cases
  SET TAGS ('domain' = 'communicable_disease', 'source' = 'chhs_open_data', 'refresh' = 'annual');
