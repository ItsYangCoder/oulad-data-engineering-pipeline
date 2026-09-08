-- File: courses_clean.sql
-- Suggested branch: feature/clean-courses
-- Purpose: Prepare the list of module presentations used by other Silver tables and Gold course
--    dimensions.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: open_university.oulad_bronze.courses_raw
-- Output: open_university.oulad_silver.courses_clean
-- Grain / business key: One module presentation; (code_module, code_presentation).
--
-- What to put in this file:
-- 1. Use named CTEs to trim text, convert ?, blank, NA, N/A and NULL text to SQL NULL, then TRY_CAST
--    numeric fields.
-- 2. Keep code_module, code_presentation and module_presentation_length.
-- 3. Trim and consistently capitalize module/presentation codes; cast module_presentation_length to
--    INT.
-- 4. Validate complete unique composite keys and a positive presentation length.
-- 5. Do not collapse different presentations of the same module or guess module titles/start dates.
-- 6. Keep source column names; add clean_load_timestamp and clean_load_date. Record any invalid
--    required values for review instead of silently losing rows.
-- 7. Create the Delta target once if needed. Make repeat loads use the complete business key; rerunning
--    the same input must not add duplicate business rows.
--
-- Validation belongs in tests/02_clean_checks/; these counts describe the current source batch.
--
-- Done when: 22 rows for the current batch, unique composite keys, valid lengths and related Silver
--    checks pass.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.
--
--
-- 
-- ========================================================================================================
-- File: courses_clean.sql
-- Branch: feature/clean-courses
-- Input: open_university.oulad_bronze.courses_raw
-- Output: open_university.oulad_silver.courses_clean
-- Grain / business key: One module presentation; (code_module, code_presentation).
-- ========================================================================================================

-- Create the Delta (Databricks' transactional storage format) target once, if it doesn't exist yet.
CREATE TABLE IF NOT EXISTS open_university.oulad_silver.courses_clean (
  code_module STRING,
  code_presentation STRING,
  module_presentation_length INT,
  is_valid_key BOOLEAN,
  is_valid_length BOOLEAN,
  clean_load_timestamp TIMESTAMP,
  clean_load_date DATE
) USING DELTA;

WITH normalized AS (
  -- Trim text and convert every known placeholder to a real SQL NULL.
  SELECT
    UPPER(TRIM(code_module)) AS code_module,
    UPPER(TRIM(code_presentation)) AS code_presentation,
    CASE
      WHEN TRIM(module_presentation_length) IN ('?', '', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE TRIM(module_presentation_length)
    END AS module_presentation_length_raw
  FROM open_university.oulad_bronze.courses_raw
),

casted AS (
  -- TRY_CAST (safe cast that returns NULL instead of erroring on bad input) the numeric field.
  SELECT
    code_module,
    code_presentation,
    TRY_CAST(module_presentation_length_raw AS INT) AS module_presentation_length
  FROM normalized
),

validated AS (
  -- Flag rows instead of dropping them, so invalid data stays visible for review.
  SELECT
    code_module,
    code_presentation,
    module_presentation_length,
    CASE WHEN code_module IS NOT NULL AND code_presentation IS NOT NULL
         THEN TRUE ELSE FALSE END AS is_valid_key,
    CASE WHEN module_presentation_length IS NOT NULL AND module_presentation_length > 0
         THEN TRUE ELSE FALSE END AS is_valid_length
  FROM casted
),

deduped AS (
  -- Guard against exact-duplicate source rows only; distinct presentations of the
  -- same module are never collapsed since the key includes code_presentation.
  SELECT DISTINCT
    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length
  FROM validated
)

MERGE INTO open_university.oulad_silver.courses_clean AS target
USING (
  SELECT
    *,
    current_timestamp() AS clean_load_timestamp,
    current_date() AS clean_load_date
  FROM deduped
) AS source
ON  target.code_module = source.code_module
AND target.code_presentation = source.code_presentation
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;
