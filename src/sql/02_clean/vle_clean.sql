-- File: vle_clean.sql
-- Suggested branch: feature/clean-vle
-- Purpose: Prepare VLE resource descriptions and optional availability weeks.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: open_university.oulad_bronze.vle_raw
-- Output: open_university.oulad_silver.vle_clean
-- Grain / business key: One resource per module presentation; (code_module, code_presentation,
--    id_site).
--
-- What to put in this file:
-- 1. Use named CTEs to trim text, convert ?, blank, NA, N/A and NULL text to SQL NULL, then TRY_CAST
--    numeric fields.
-- 2. Keep code_module, code_presentation, id_site, activity_type, week_from and week_to.
-- 3. Cast id_site to BIGINT and week fields to INT; standardize activity_type consistently.
-- 4. Preserve 5,243 rows with both availability weeks missing; NULL means the source does not specify
--    that period.
-- 5. Check week_from <= week_to when both exist; validate the complete resource key and
--    course/presentation parent.
-- 6. Keep resource attributes here for the VLE fact; the agreed Gold design has no separate
--    dim_vle_resource model.
-- 7. Keep source column names; add clean_load_timestamp and clean_load_date. Record any invalid
--    required values for review instead of silently losing rows.
-- 8. Create the Delta target once if needed. Make repeat loads use the complete business key; rerunning
--    the same input must not add duplicate business rows.
--
-- Validation belongs in tests/02_clean_checks/; these counts describe the current source batch.
--
-- Done when: 6,364 resources for the current batch; unique composite keys; expected NULL weeks
--    retained; related Silver checks pass.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.



-- File: vle_clean.sql
-- Branch: feature/clean-vle
-- Input: open_university.oulad_bronze.vle_raw
-- Output: open_university.oulad_silver.vle_clean
-- Grain / business key: One resource per module presentation;
--   (code_module, code_presentation, id_site).
-- ========================================================================================================

-- Create the Delta target once. Validation flags retain data-quality findings in Silver instead of
-- silently dropping source resources.
CREATE TABLE IF NOT EXISTS open_university.oulad_silver.vle_clean (
  code_module STRING,
  code_presentation STRING,
  id_site BIGINT,
  activity_type STRING,
  week_from INT,
  week_to INT,
  is_valid_key BOOLEAN,
  is_valid_week_range BOOLEAN,
  is_valid_parent BOOLEAN,
  clean_load_timestamp TIMESTAMP,
  clean_load_date DATE
) USING DELTA;

WITH normalized AS (
  -- Standardize text and convert all documented source placeholders to SQL NULL.
  SELECT
    CASE
      WHEN code_module IS NULL
        OR UPPER(TRIM(code_module)) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE UPPER(TRIM(code_module))
    END AS code_module,
    CASE
      WHEN code_presentation IS NULL
        OR UPPER(TRIM(code_presentation)) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE UPPER(TRIM(code_presentation))
    END AS code_presentation,
    CASE
      WHEN id_site IS NULL
        OR UPPER(TRIM(CAST(id_site AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE TRIM(CAST(id_site AS STRING))
    END AS id_site_raw,
    CASE
      WHEN activity_type IS NULL
        OR UPPER(TRIM(activity_type)) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE LOWER(TRIM(activity_type))
    END AS activity_type,
    CASE
      WHEN week_from IS NULL
        OR UPPER(TRIM(CAST(week_from AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE TRIM(CAST(week_from AS STRING))
    END AS week_from_raw,
    CASE
      WHEN week_to IS NULL
        OR UPPER(TRIM(CAST(week_to AS STRING))) IN ('', '?', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE TRIM(CAST(week_to AS STRING))
    END AS week_to_raw
  FROM open_university.oulad_bronze.vle_raw
),

casted AS (
  -- TRY_CAST keeps malformed numeric values visible as failed validation rather than aborting the load.
  SELECT
    code_module,
    code_presentation,
    TRY_CAST(id_site_raw AS BIGINT) AS id_site,
    activity_type,
    TRY_CAST(week_from_raw AS INT) AS week_from,
    TRY_CAST(week_to_raw AS INT) AS week_to,
    id_site_raw,
    week_from_raw,
    week_to_raw
  FROM normalized
),

validated AS (
  SELECT
    source.code_module,
    source.code_presentation,
    source.id_site,
    source.activity_type,
    source.week_from,
    source.week_to,
    CASE
      WHEN source.code_module IS NOT NULL
       AND source.code_presentation IS NOT NULL
       AND source.id_site_raw IS NOT NULL
       AND source.id_site IS NOT NULL
      THEN TRUE ELSE FALSE
    END AS is_valid_key,
    CASE
      -- NULL availability endpoints are allowed. Non-NULL source text must cast successfully,
      -- and a complete range must be ordered from the earlier week to the later week.
      WHEN source.week_from_raw IS NOT NULL AND source.week_from IS NULL THEN FALSE
      WHEN source.week_to_raw IS NOT NULL AND source.week_to IS NULL THEN FALSE
      WHEN source.week_from IS NOT NULL
       AND source.week_to IS NOT NULL
       AND source.week_from > source.week_to THEN FALSE
      ELSE TRUE
    END AS is_valid_week_range,
    CASE
      WHEN parent.code_module IS NOT NULL THEN TRUE ELSE FALSE
    END AS is_valid_parent
  FROM casted AS source
  LEFT JOIN open_university.oulad_silver.courses_clean AS parent
    ON source.code_module = parent.code_module
   AND source.code_presentation = parent.code_presentation
),

prepared AS (
  SELECT
    code_module,
    code_presentation,
    id_site,
    activity_type,
    week_from,
    week_to,
    is_valid_key,
    is_valid_week_range,
    is_valid_parent,
    CURRENT_TIMESTAMP() AS clean_load_timestamp,
    CURRENT_DATE() AS clean_load_date
  FROM validated
)

MERGE INTO open_university.oulad_silver.vle_clean AS target
USING prepared AS source
ON  target.code_module <=> source.code_module
AND target.code_presentation <=> source.code_presentation
AND target.id_site <=> source.id_site
WHEN MATCHED THEN UPDATE SET
  target.activity_type = source.activity_type,
  target.week_from = source.week_from,
  target.week_to = source.week_to,
  target.is_valid_key = source.is_valid_key,
  target.is_valid_week_range = source.is_valid_week_range,
  target.is_valid_parent = source.is_valid_parent,
  target.clean_load_timestamp = source.clean_load_timestamp,
  target.clean_load_date = source.clean_load_date
WHEN NOT MATCHED THEN INSERT (
  code_module,
  code_presentation,
  id_site,
  activity_type,
  week_from,
  week_to,
  is_valid_key,
  is_valid_week_range,
  is_valid_parent,
  clean_load_timestamp,
  clean_load_date
)
VALUES (
  source.code_module,
  source.code_presentation,
  source.id_site,
  source.activity_type,
  source.week_from,
  source.week_to,
  source.is_valid_key,
  source.is_valid_week_range,
  source.is_valid_parent,
  source.clean_load_timestamp,
  source.clean_load_date
);
