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


-- Input:
--   open_university.oulad_bronze.vle_raw
--
-- Output:
--   open_university.oulad_silver.vle_clean
--
-- Grain:
--   One VLE resource per module presentation
--
-- Business key:
--   (code_module, code_presentation, id_site)
--
-- Important:
--   NULL week_from / week_to values are valid.
--   They mean that the source does not specify an availability period.
-- =============================================================================


-- =============================================================================
-- 1. CREATE CLEAN TARGET
-- =============================================================================

CREATE TABLE IF NOT EXISTS open_university.oulad_silver.vle_clean (
    code_module STRING,
    code_presentation STRING,
    id_site BIGINT,
    activity_type STRING,
    week_from INT,
    week_to INT,

    -- Data-quality flags
    is_valid_date_range BOOLEAN,
    has_valid_business_keys BOOLEAN,

    -- Audit columns
    clean_load_timestamp TIMESTAMP,
    clean_load_date DATE
)
USING DELTA;


-- =============================================================================
-- 2. CREATE REJECT TABLE
-- =============================================================================
-- Invalid rows are recorded here instead of being silently discarded.
-- This also lets us distinguish legitimate NULL weeks from bad numeric values.

CREATE TABLE IF NOT EXISTS open_university.oulad_silver.vle_rejected (
    code_module STRING,
    code_presentation STRING,
    id_site_raw STRING,
    activity_type STRING,
    week_from_raw STRING,
    week_to_raw STRING,
    rejection_reason STRING,
    rejected_load_timestamp TIMESTAMP,
    rejected_load_date DATE
)
USING DELTA;


-- =============================================================================
-- 3. BUILD CLEANING / VALIDATION STAGE
-- =============================================================================

CREATE OR REPLACE TEMP VIEW vle_clean_stage AS

WITH raw_trimmed AS (

    SELECT
        TRIM(CAST(code_module AS STRING)) AS code_module,
        TRIM(CAST(code_presentation AS STRING)) AS code_presentation,
        TRIM(CAST(id_site AS STRING)) AS id_site_raw,
        TRIM(CAST(activity_type AS STRING)) AS activity_type,
        TRIM(CAST(week_from AS STRING)) AS week_from_raw,
        TRIM(CAST(week_to AS STRING)) AS week_to_raw

    FROM open_university.oulad_bronze.vle_raw
),


-- ---------------------------------------------------------------------------
-- Standardize source null representations.
--
-- Important:
-- A source NULL / ?, blank / NA / N/A / NULL is a legitimate SQL NULL.
-- We preserve that distinction before TRY_CAST.
-- ---------------------------------------------------------------------------

standardized_nulls AS (

    SELECT

        CASE
            WHEN code_module IS NULL
              OR UPPER(code_module) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE UPPER(code_module)
        END AS code_module,

        CASE
            WHEN code_presentation IS NULL
              OR UPPER(code_presentation) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE UPPER(code_presentation)
        END AS code_presentation,

        CASE
            WHEN id_site_raw IS NULL
              OR UPPER(id_site_raw) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE id_site_raw
        END AS id_site_raw,

        CASE
            WHEN activity_type IS NULL
              OR UPPER(activity_type) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE LOWER(activity_type)
        END AS activity_type,

        CASE
            WHEN week_from_raw IS NULL
              OR UPPER(week_from_raw) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE week_from_raw
        END AS week_from_raw,

        CASE
            WHEN week_to_raw IS NULL
              OR UPPER(week_to_raw) IN ('?', '', 'NA', 'N/A', 'NULL')
            THEN NULL
            ELSE week_to_raw
        END AS week_to_raw

    FROM raw_trimmed
),


-- ---------------------------------------------------------------------------
-- Cast numeric fields.
-- ---------------------------------------------------------------------------

typed AS (

    SELECT
        code_module,
        code_presentation,

        id_site_raw,
        TRY_CAST(id_site_raw AS BIGINT) AS id_site,

        activity_type,

        week_from_raw,
        TRY_CAST(week_from_raw AS INT) AS week_from,

        week_to_raw,
        TRY_CAST(week_to_raw AS INT) AS week_to

    FROM standardized_nulls
),


-- ---------------------------------------------------------------------------
-- Validate keys and optional week values.
--
-- Important:
-- week_from_raw IS NULL + week_from IS NULL = legitimate missing value
--
-- week_from_raw IS NOT NULL + week_from IS NULL = failed numeric cast
-- ---------------------------------------------------------------------------

validated AS (

    SELECT
        t.*,

        CASE
            WHEN t.code_module IS NOT NULL
             AND t.code_presentation IS NOT NULL
             AND t.id_site IS NOT NULL
            THEN TRUE
            ELSE FALSE
        END AS has_valid_business_keys,


        CASE
            WHEN
                (
                    t.week_from_raw IS NULL
                    OR t.week_from IS NOT NULL
                )
                AND
                (
                    t.week_to_raw IS NULL
                    OR t.week_to IS NOT NULL
                )
            THEN TRUE
            ELSE FALSE
        END AS has_valid_week_values,


        CASE
            -- Both weeks known: start must not exceed end
            WHEN t.week_from IS NOT NULL
             AND t.week_to IS NOT NULL
            THEN t.week_from <= t.week_to

            -- Missing availability weeks are allowed
            ELSE TRUE
        END AS is_valid_date_range,


        -- Validate parent module presentation.
        CASE
            WHEN c.code_module IS NOT NULL
            THEN TRUE
            ELSE FALSE
        END AS has_valid_parent

    FROM typed t

    LEFT JOIN open_university.oulad_silver.courses_clean c
        ON  t.code_module = c.code_module
        AND t.code_presentation = c.code_presentation
),


-- ---------------------------------------------------------------------------
-- Detect unexpected duplicate VLE resource business keys.
--
-- We do NOT arbitrarily keep one duplicated record.
-- ---------------------------------------------------------------------------

duplicate_checked AS (

    SELECT
        *,

        COUNT(*) OVER (
            PARTITION BY
                code_module,
                code_presentation,
                id_site
        ) AS business_key_count

    FROM validated
),


-- ---------------------------------------------------------------------------
-- Produce rejection reason.
-- ---------------------------------------------------------------------------

final_stage AS (

    SELECT
        *,

        CONCAT_WS(
            '; ',

            CASE
                WHEN has_valid_business_keys = FALSE
                THEN 'INVALID_OR_MISSING_BUSINESS_KEY'
            END,

            CASE
                WHEN week_from_raw IS NOT NULL
                 AND week_from IS NULL
                THEN 'INVALID_WEEK_FROM'
            END,

            CASE
                WHEN week_to_raw IS NOT NULL
                 AND week_to IS NULL
                THEN 'INVALID_WEEK_TO'
            END,

            CASE
                WHEN is_valid_date_range = FALSE
                THEN 'WEEK_FROM_GREATER_THAN_WEEK_TO'
            END,

            CASE
                WHEN has_valid_parent = FALSE
                 AND has_valid_business_keys = TRUE
                THEN 'MISSING_COURSE_PRESENTATION_PARENT'
            END,

            CASE
                WHEN business_key_count > 1
                THEN 'DUPLICATE_RESOURCE_BUSINESS_KEY'
            END

        ) AS rejection_reason

    FROM duplicate_checked
)

SELECT *
FROM final_stage;

-- =============================================================================
-- 4. STORE INVALID ROWS FOR REVIEW
-- =============================================================================

INSERT OVERWRITE open_university.oulad_silver.vle_rejected

SELECT
    code_module,
    code_presentation,
    id_site_raw,
    activity_type,
    week_from_raw,
    week_to_raw,
    rejection_reason,
    CURRENT_TIMESTAMP() AS rejected_load_timestamp,
    CURRENT_DATE() AS rejected_load_date

FROM vle_clean_stage

WHERE has_valid_business_keys = FALSE
   OR has_valid_week_values = FALSE
   OR is_valid_date_range = FALSE
   OR has_valid_parent = FALSE
   OR business_key_count > 1;

-- =============================================================================
-- 5. IDEMPOTENT LOAD INTO VLE_CLEAN
-- =============================================================================

MERGE INTO open_university.oulad_silver.vle_clean AS target

USING (

    SELECT
        code_module,
        code_presentation,
        id_site,
        activity_type,
        week_from,
        week_to,
        is_valid_date_range,
        has_valid_business_keys,
        CURRENT_TIMESTAMP() AS clean_load_timestamp,
        CURRENT_DATE() AS clean_load_date

    FROM vle_clean_stage

    WHERE has_valid_business_keys = TRUE
      AND has_valid_week_values = TRUE
      AND is_valid_date_range = TRUE
      AND has_valid_parent = TRUE
      AND business_key_count = 1

) AS source

-- Use the ACTUAL complete business key.
-- No fake UNKNOWN / -999 values are required.
ON  target.code_module = source.code_module
AND target.code_presentation = source.code_presentation
AND target.id_site = source.id_site


WHEN MATCHED THEN
    UPDATE SET

        target.activity_type =
            source.activity_type,

        target.week_from =
            source.week_from,

        target.week_to =
            source.week_to,

        target.is_valid_date_range =
            source.is_valid_date_range,

        target.has_valid_business_keys =
            source.has_valid_business_keys,

        target.clean_load_timestamp =
            source.clean_load_timestamp,

        target.clean_load_date =
            source.clean_load_date


WHEN NOT MATCHED THEN
    INSERT (
        code_module,
        code_presentation,
        id_site,
        activity_type,
        week_from,
        week_to,
        is_valid_date_range,
        has_valid_business_keys,
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
        source.is_valid_date_range,
        source.has_valid_business_keys,
        source.clean_load_timestamp,
        source.clean_load_date
    );

    