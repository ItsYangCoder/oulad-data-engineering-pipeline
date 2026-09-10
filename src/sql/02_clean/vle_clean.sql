-- Silver VLE resources
-- One row per (code_module, code_presentation, id_site).

CREATE TABLE IF NOT EXISTS open_university.oulad_silver.vle_clean (
  code_module STRING,
  code_presentation STRING,
  id_site BIGINT,
  activity_type STRING,
  week_from INT,
  week_to INT,
  is_valid_date_range BOOLEAN,
  has_valid_business_keys BOOLEAN,
  clean_load_timestamp TIMESTAMP,
  clean_load_date DATE
) USING DELTA;

CREATE TABLE IF NOT EXISTS open_university.oulad_silver.vle_rejected (
  code_module STRING,
  code_presentation STRING,
  id_site_raw STRING,
  activity_type_raw STRING,
  week_from_raw STRING,
  week_to_raw STRING,
  rejection_reason STRING,
  clean_load_timestamp TIMESTAMP,
  clean_load_date DATE
) USING DELTA;

-- Bronze is treated as cumulative history. Rows missing from one delivery are not automatic deletes.
CREATE OR REPLACE TEMP VIEW vle_typed_current_batch AS
WITH normalized AS (
  SELECT
    CAST(code_module AS STRING) AS code_module_raw,
    CAST(code_presentation AS STRING) AS code_presentation_raw,
    CAST(id_site AS STRING) AS id_site_raw,
    CAST(activity_type AS STRING) AS activity_type_raw,
    CAST(week_from AS STRING) AS week_from_raw,
    CAST(week_to AS STRING) AS week_to_raw,
    CASE WHEN code_module IS NULL OR UPPER(TRIM(CAST(code_module AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
      THEN NULL ELSE UPPER(TRIM(CAST(code_module AS STRING))) END AS code_module,
    CASE WHEN code_presentation IS NULL OR UPPER(TRIM(CAST(code_presentation AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
      THEN NULL ELSE UPPER(TRIM(CAST(code_presentation AS STRING))) END AS code_presentation,
    CASE WHEN id_site IS NULL OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
      THEN NULL ELSE TRIM(CAST(id_site AS STRING)) END AS id_site_normalized,
    CASE WHEN activity_type IS NULL OR UPPER(TRIM(CAST(activity_type AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
      THEN NULL ELSE LOWER(TRIM(CAST(activity_type AS STRING))) END AS activity_type,
    CASE WHEN week_from IS NULL OR UPPER(TRIM(CAST(week_from AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
      THEN NULL ELSE TRIM(CAST(week_from AS STRING)) END AS week_from_normalized,
    CASE WHEN week_to IS NULL OR UPPER(TRIM(CAST(week_to AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL')
      THEN NULL ELSE TRIM(CAST(week_to AS STRING)) END AS week_to_normalized
  FROM open_university.oulad_bronze.vle_raw
),
casted AS (
  SELECT *,
    TRY_CAST(id_site_normalized AS BIGINT) AS id_site,
    TRY_CAST(week_from_normalized AS INT) AS week_from,
    TRY_CAST(week_to_normalized AS INT) AS week_to
  FROM normalized
)
SELECT *,
  CASE
    WHEN code_module IS NULL THEN 'MISSING_CODE_MODULE'
    WHEN code_presentation IS NULL THEN 'MISSING_CODE_PRESENTATION'
    WHEN id_site_normalized IS NULL THEN 'MISSING_ID_SITE'
    WHEN id_site IS NULL THEN 'INVALID_ID_SITE'
    WHEN week_from_normalized IS NOT NULL AND week_from IS NULL THEN 'INVALID_WEEK_FROM'
    WHEN week_to_normalized IS NOT NULL AND week_to IS NULL THEN 'INVALID_WEEK_TO'
    ELSE NULL
  END AS rejection_reason
FROM casted;

-- Keep unique rejected records instead of replacing the previous rejection history.
MERGE INTO open_university.oulad_silver.vle_rejected AS target
USING (
  SELECT DISTINCT
    code_module_raw,
    code_presentation_raw,
    id_site_raw,
    activity_type_raw,
    week_from_raw,
    week_to_raw,
    rejection_reason,
    CURRENT_TIMESTAMP() AS clean_load_timestamp,
    CURRENT_DATE() AS clean_load_date
  FROM vle_typed_current_batch
  WHERE rejection_reason IS NOT NULL
) AS source
ON  target.code_module <=> source.code_module_raw
AND target.code_presentation <=> source.code_presentation_raw
AND target.id_site_raw <=> source.id_site_raw
AND target.activity_type_raw <=> source.activity_type_raw
AND target.week_from_raw <=> source.week_from_raw
AND target.week_to_raw <=> source.week_to_raw
AND target.rejection_reason = source.rejection_reason
WHEN NOT MATCHED THEN INSERT (
  code_module,
  code_presentation,
  id_site_raw,
  activity_type_raw,
  week_from_raw,
  week_to_raw,
  rejection_reason,
  clean_load_timestamp,
  clean_load_date
)
VALUES (
  source.code_module_raw,
  source.code_presentation_raw,
  source.id_site_raw,
  source.activity_type_raw,
  source.week_from_raw,
  source.week_to_raw,
  source.rejection_reason,
  source.clean_load_timestamp,
  source.clean_load_date
);

MERGE INTO open_university.oulad_silver.vle_clean AS target
USING (
  SELECT code_module, code_presentation, id_site, activity_type, week_from, week_to,
         CASE WHEN week_from IS NOT NULL AND week_to IS NOT NULL AND week_from > week_to
              THEN FALSE ELSE TRUE END AS is_valid_date_range,
         TRUE AS has_valid_business_keys,
         CURRENT_TIMESTAMP() AS clean_load_timestamp,
         CURRENT_DATE() AS clean_load_date
  FROM (
    SELECT v.*,
           ROW_NUMBER() OVER (
             PARTITION BY v.code_module, v.code_presentation, v.id_site
             ORDER BY
               CASE WHEN v.activity_type IS NOT NULL THEN 0 ELSE 1 END,
               CASE WHEN v.week_from IS NOT NULL THEN 0 ELSE 1 END,
               CASE WHEN v.week_to IS NOT NULL THEN 0 ELSE 1 END,
               v.activity_type, v.week_from, v.week_to
           ) AS row_number
    FROM vle_typed_current_batch v
    WHERE v.rejection_reason IS NULL
  ) ranked
  WHERE row_number = 1
) AS source
ON target.code_module = source.code_module
AND target.code_presentation = source.code_presentation
AND target.id_site = source.id_site
WHEN MATCHED THEN UPDATE SET
  target.activity_type = source.activity_type,
  target.week_from = source.week_from,
  target.week_to = source.week_to,
  target.is_valid_date_range = source.is_valid_date_range,
  target.has_valid_business_keys = source.has_valid_business_keys,
  target.clean_load_timestamp = source.clean_load_timestamp,
  target.clean_load_date = source.clean_load_date
WHEN NOT MATCHED THEN INSERT (
  code_module, code_presentation, id_site, activity_type, week_from, week_to,
  is_valid_date_range, has_valid_business_keys, clean_load_timestamp, clean_load_date
) VALUES (
  source.code_module, source.code_presentation, source.id_site, source.activity_type,
  source.week_from, source.week_to, source.is_valid_date_range, source.has_valid_business_keys,
  source.clean_load_timestamp, source.clean_load_date
);
-- Keep unmatched target rows. A missing resource in a partial batch is not a delete.

DROP VIEW IF EXISTS vle_typed_current_batch;
