-- ========================================================================================================
-- File: courses_clean.sql
-- Branch: feature/clean-courses
--
-- Purpose:
--    Clean and prepare course module presentations for the Silver layer while preserving
--    source records that require data-quality review.
--
-- Input:
--    open_university.oulad_bronze.courses_raw
--
-- Output:
--    open_university.oulad_silver.courses_clean
--    open_university.oulad_silver.courses_invalid_key_quarantine
--
-- Grain / Business Key:
--    One row per module presentation;
--    (code_module, code_presentation)
--
-- Expected Clean Row Count:
--    22 rows for the current source delivery.
--
-- Data Quality Rules:
--    1. code_module and code_presentation are trimmed and standardized to uppercase.
--    2. Placeholder values (?, blank, NA, N/A, NULL) are converted to SQL NULL.
--    3. module_presentation_length is converted using TRY_CAST to INT.
--    4. module_presentation_length must be a positive integer.
--    5. Rows with invalid business keys are quarantined rather than silently dropped.
--    6. Exact duplicate rows for the same business key are collapsed into one clean row.
--    7. Conflicting values for the same business key are quarantined rather than arbitrarily
--       selecting a winning value.
--    8. Different module presentations are preserved; records are not collapsed by code_module alone.
--
-- Deduplication Rule:
--    Exact duplicates are safely collapsed because they contain the same business-key values
--    and the same module_presentation_length.
--
--    Conflicting duplicate business keys are not resolved by selecting the largest, smallest,
--    or otherwise arbitrary value. All conflicting records are sent to quarantine for review.
--
-- Invalid Key Rule:
--    Records where code_module or code_presentation is NULL after normalization are sent to
--    courses_invalid_key_quarantine.
--
-- Invalid Length Rule:
--    Invalid or missing module_presentation_length values are preserved in courses_clean and
--    flagged through is_valid_length for downstream validation. No source record is silently lost.
--
-- Idempotency:
--    The clean table uses MERGE on the complete business key.
--    The quarantine table uses a deterministic quarantine_id so rerunning the same source data
--    does not create duplicate quarantine records.
--
-- Runtime / Databricks Considerations:
--    1. COUNT(DISTINCT ...) OVER (...) is not supported by Databricks/Spark SQL.
--       COLLECT_SET(...) OVER (...) is therefore used and wrapped with SIZE() to obtain the
--       distinct-value count.
--
--    2. OVER must bind directly to COLLECT_SET(...), not to SIZE(...).
--
--    3. CTEs are scoped to a single SQL statement. Shared cleaning logic is therefore
--       materialized into temporary views before the two MERGE statements.
--
-- Performance:
--    - No partitioning because courses is a small dimension-like table.
--    - No OPTIMIZE, ZORDER, caching, or unnecessary repartitioning.
--    - Window functions are used for duplicate/conflict classification.
--    - Shared normalization and classification logic is materialized once.
--    - MERGE is used to make repeated executions idempotent.
-- ========================================================================================================


-- ========================================================================================================
-- STEP 0: CREATE SILVER TARGET TABLE
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


-- ========================================================================================================
-- STEP 0B: CREATE INVALID-KEY QUARANTINE TABLE
-- ========================================================================================================

CREATE TABLE IF NOT EXISTS open_university.oulad_silver.courses_invalid_key_quarantine (
  quarantine_id STRING,
  code_module STRING,
  code_presentation STRING,
  module_presentation_length INT,
  is_valid_key BOOLEAN,
  is_valid_length BOOLEAN,
  quarantine_reason STRING,
  source_row_count BIGINT,
  clean_load_timestamp TIMESTAMP,
  clean_load_date DATE
) USING DELTA;


-- ========================================================================================================
-- STEP 1: NORMALIZE, CAST, AND FLAG SOURCE RECORDS
-- ========================================================================================================
--
-- All Bronze rows are retained at this stage.
--
-- Placeholder values are converted to SQL NULL only in the Silver transformation.
-- No invalid source record is silently filtered out here.

CREATE OR REPLACE TEMPORARY VIEW courses_flagged_staging AS (

  WITH normalized AS (

    SELECT

      CASE
        WHEN UPPER(TRIM(CAST(code_module AS STRING)))
             IN ('?', '', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE UPPER(TRIM(CAST(code_module AS STRING)))
      END AS code_module,

      CASE
        WHEN UPPER(TRIM(CAST(code_presentation AS STRING)))
             IN ('?', '', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
      END AS code_presentation,

      CASE
        WHEN UPPER(TRIM(CAST(module_presentation_length AS STRING)))
             IN ('?', '', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE TRIM(CAST(module_presentation_length AS STRING))
      END AS module_presentation_length_raw

    FROM open_university.oulad_bronze.courses_raw
  ),

  casted AS (

    SELECT

      code_module,
      code_presentation,

      TRY_CAST(module_presentation_length_raw AS INT)
        AS module_presentation_length

    FROM normalized
  )

  SELECT

    code_module,
    code_presentation,
    module_presentation_length,

    CASE
      WHEN code_module IS NOT NULL
       AND code_presentation IS NOT NULL
      THEN TRUE
      ELSE FALSE
    END AS is_valid_key,

    CASE
      WHEN module_presentation_length IS NOT NULL
       AND module_presentation_length > 0
      THEN TRUE
      ELSE FALSE
    END AS is_valid_length

  FROM casted
);


-- ========================================================================================================
-- STEP 2: CLASSIFY VALID-KEY RECORDS FOR DUPLICATE / CONFLICT DETECTION
-- ========================================================================================================
--
-- Only records with a complete business key participate in duplicate/conflict classification.
--
-- A key with one distinct module_presentation_length value represents either:
--    - one unique source row, or
--    - exact duplicates.
--
-- A key with more than one distinct length value represents a conflicting business key.
--
-- COLLECT_SET removes duplicate values, while SIZE() returns the number of distinct values.
-- This replaces unsupported COUNT(DISTINCT ...) OVER (...) syntax in Databricks/Spark SQL.

CREATE OR REPLACE TEMPORARY VIEW courses_classified_staging AS (

  SELECT

    f.*,

    COUNT(*) OVER (
      PARTITION BY code_module, code_presentation
    ) AS key_row_count,

    SIZE(
      COLLECT_SET(
        COALESCE(
          CAST(module_presentation_length AS STRING),
          '__NULL__'
        )
      ) OVER (
        PARTITION BY code_module, code_presentation
      )
    ) AS distinct_length_count

  FROM courses_flagged_staging f

  WHERE is_valid_key = TRUE
);


-- ========================================================================================================
-- STEP 3: MERGE VALID-KEY RECORDS INTO SILVER
-- ========================================================================================================
--
-- Unique records and exact duplicates are eligible for the clean table.
--
-- ROW_NUMBER is used only when all records for a business key have the same
-- module_presentation_length. It therefore collapses exact duplicates without
-- arbitrarily resolving conflicting values.
--
-- Invalid-key records are excluded here and handled in STEP 4.

WITH clean_records AS (

  SELECT

    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length

  FROM courses_classified_staging

  WHERE distinct_length_count = 1

  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY code_module, code_presentation
    ORDER BY module_presentation_length DESC NULLS LAST
  ) = 1
)

MERGE INTO open_university.oulad_silver.courses_clean AS target

USING (

  SELECT

    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,
    CURRENT_TIMESTAMP() AS clean_load_timestamp,
    CURRENT_DATE() AS clean_load_date

  FROM clean_records

) AS source

ON  target.code_module = source.code_module
AND target.code_presentation = source.code_presentation

WHEN MATCHED THEN UPDATE SET

  target.module_presentation_length = source.module_presentation_length,
  target.is_valid_key                = source.is_valid_key,
  target.is_valid_length             = source.is_valid_length,
  target.clean_load_timestamp        = source.clean_load_timestamp,
  target.clean_load_date             = source.clean_load_date

WHEN NOT MATCHED THEN INSERT (

  code_module,
  code_presentation,
  module_presentation_length,
  is_valid_key,
  is_valid_length,
  clean_load_timestamp,
  clean_load_date

)

VALUES (

  source.code_module,
  source.code_presentation,
  source.module_presentation_length,
  source.is_valid_key,
  source.is_valid_length,
  source.clean_load_timestamp,
  source.clean_load_date

);


-- ========================================================================================================
-- STEP 4: PREPARE INVALID AND CONFLICTING RECORDS FOR QUARANTINE
-- ========================================================================================================
--
-- Two categories are quarantined:
--
--    1. INVALID_BUSINESS_KEY
--       code_module or code_presentation is missing after normalization.
--
--    2. CONFLICTING_BUSINESS_KEY
--       The same complete business key contains more than one distinct
--       module_presentation_length value.
--
-- No arbitrary value is selected for conflicting keys.
--
-- source_row_count records how many source rows contributed to each quarantined
-- combination for audit/review purposes.

WITH invalid_key_records AS (

  SELECT

    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,

    'INVALID_BUSINESS_KEY' AS quarantine_reason,

    COUNT(*) OVER (
      PARTITION BY
        COALESCE(code_module, '__NULL__'),
        COALESCE(code_presentation, '__NULL__'),
        COALESCE(
          CAST(module_presentation_length AS STRING),
          '__NULL__'
        )
    ) AS source_row_count

  FROM courses_flagged_staging

  WHERE is_valid_key = FALSE
),

conflicting_records AS (

  SELECT

    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,

    'CONFLICTING_BUSINESS_KEY' AS quarantine_reason,

    COUNT(*) OVER (
      PARTITION BY code_module, code_presentation
    ) AS source_row_count

  FROM courses_classified_staging

  WHERE distinct_length_count > 1
),

quarantine_records AS (

  SELECT
    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,
    quarantine_reason,
    source_row_count

  FROM invalid_key_records

  UNION ALL

  SELECT
    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,
    quarantine_reason,
    source_row_count

  FROM conflicting_records
),

quarantine_prepared AS (

  SELECT

    CONCAT_WS(
      '||',
      COALESCE(code_module, '__NULL__'),
      COALESCE(code_presentation, '__NULL__'),
      COALESCE(
        CAST(module_presentation_length AS STRING),
        '__NULL__'
      ),
      quarantine_reason
    ) AS quarantine_id,

    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,
    quarantine_reason,
    source_row_count

  FROM quarantine_records

  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY
      COALESCE(code_module, '__NULL__'),
      COALESCE(code_presentation, '__NULL__'),
      COALESCE(
        CAST(module_presentation_length AS STRING),
        '__NULL__'
      ),
      quarantine_reason
    ORDER BY source_row_count DESC
  ) = 1
)


-- ========================================================================================================
-- STEP 5: MERGE QUARANTINED RECORDS
-- ========================================================================================================
--
-- quarantine_id provides deterministic idempotency.
-- Rerunning the same Bronze input updates the existing quarantine record rather
-- than inserting another copy.

MERGE INTO open_university.oulad_silver.courses_invalid_key_quarantine AS target

USING (

  SELECT

    quarantine_id,
    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,
    quarantine_reason,
    source_row_count,
    CURRENT_TIMESTAMP() AS clean_load_timestamp,
    CURRENT_DATE() AS clean_load_date

  FROM quarantine_prepared

) AS source

ON target.quarantine_id = source.quarantine_id

WHEN MATCHED THEN UPDATE SET

  target.code_module                 = source.code_module,
  target.code_presentation           = source.code_presentation,
  target.module_presentation_length  = source.module_presentation_length,
  target.is_valid_key                = source.is_valid_key,
  target.is_valid_length             = source.is_valid_length,
  target.quarantine_reason           = source.quarantine_reason,
  target.source_row_count            = source.source_row_count,
  target.clean_load_timestamp        = source.clean_load_timestamp,
  target.clean_load_date             = source.clean_load_date

WHEN NOT MATCHED THEN INSERT (

  quarantine_id,
  code_module,
  code_presentation,
  module_presentation_length,
  is_valid_key,
  is_valid_length,
  quarantine_reason,
  source_row_count,
  clean_load_timestamp,
  clean_load_date

)

VALUES (

  source.quarantine_id,
  source.code_module,
  source.code_presentation,
  source.module_presentation_length,
  source.is_valid_key,
  source.is_valid_length,
  source.quarantine_reason,
  source.source_row_count,
  source.clean_load_timestamp,
  source.clean_load_date

);
