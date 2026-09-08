-- ========================================================================================================
-- File: courses_clean.sql
-- Branch: feature/clean-courses
-- Input: open_university.oulad_bronze.courses_raw
-- Output: open_university.oulad_silver.courses_clean
-- Grain / business key: One module presentation; (code_module, code_presentation).
-- ========================================================================================================

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
  -- Trim and convert all placeholder strings (?, blank, NA, N/A, NULL) to real SQL NULLs across keys and values
  SELECT
    CASE 
      WHEN UPPER(TRIM(code_module)) IN ('?', '', 'NA', 'N/A', 'NULL') THEN NULL 
      ELSE UPPER(TRIM(code_module)) 
    END AS code_module,
    
    CASE 
      WHEN UPPER(TRIM(code_presentation)) IN ('?', '', 'NA', 'N/A', 'NULL') THEN NULL 
      ELSE UPPER(TRIM(code_presentation)) 
    END AS code_presentation,

    CASE
      WHEN TRIM(module_presentation_length) IN ('?', '', 'NA', 'N/A', 'NULL') THEN NULL
      ELSE TRIM(module_presentation_length)
    END AS module_presentation_length_raw
  FROM open_university.oulad_bronze.courses_raw
),

casted AS (
  SELECT
    code_module,
    code_presentation,
    TRY_CAST(module_presentation_length_raw AS INT) AS module_presentation_length
  FROM normalized
),

validated AS (
  SELECT
    code_module,
    code_presentation,
    module_presentation_length,
    CASE 
      WHEN code_module IS NOT NULL AND code_presentation IS NOT NULL THEN TRUE 
      ELSE FALSE 
    END AS is_valid_key,
    CASE 
      WHEN module_presentation_length IS NOT NULL AND module_presentation_length > 0 THEN TRUE 
      ELSE FALSE 
    END AS is_valid_length
  FROM casted
),

deduped AS (
  -- Guarantee exactly one row per full business key (code_module, code_presentation)
  SELECT 
    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length
  FROM (
    SELECT 
      *,
      ROW_NUMBER() OVER (
        PARTITION BY code_module, code_presentation 
        ORDER BY is_valid_length DESC, module_presentation_length DESC
      ) AS row_num
    FROM validated
  )
  WHERE row_num = 1
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