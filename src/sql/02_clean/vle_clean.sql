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



-- Create the Delta target table if it does not exist
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


-- Define the cleaning logic and merge into the target
WITH raw_trimmed AS (
    SELECT
        TRIM(code_module) AS code_module,
        TRIM(code_presentation) AS code_presentation,
        TRIM(id_site) AS id_site,
        TRIM(activity_type) AS activity_type,
        TRIM(week_from) AS week_from,
        TRIM(week_to) AS week_to
    FROM open_university.oulad_bronze.vle_raw
),

standardized_nulls AS (
    SELECT
        -- Standardize text nulls for all columns
        CASE WHEN UPPER(code_module) IN ('?', '', 'NA', 'N/A', 'NULL') THEN NULL ELSE code_module END AS code_module_clean,
        CASE WHEN UPPER(code_presentation) IN ('?', '', 'NA', 'N/A', 'NULL') THEN NULL ELSE code_presentation END AS code_presentation_clean,
        CASE WHEN UPPER(id_site) IN ('?', '', 'NA', 'N/A', 'NULL') THEN NULL ELSE id_site END AS id_site_clean,
        CASE WHEN UPPER(activity_type) IN ('?', '', 'NA', 'N/A', 'NULL') THEN NULL ELSE activity_type END AS activity_type_clean,
        CASE WHEN UPPER(week_from) IN ('?', '', 'NA', 'N/A', 'NULL') THEN NULL ELSE week_from END AS week_from_clean,
        CASE WHEN UPPER(week_to) IN ('?', '', 'NA', 'N/A', 'NULL') THEN NULL ELSE week_to END AS week_to_clean
    FROM raw_trimmed
),

casted_and_validated AS (
    SELECT
        -- Keep source names and cast required types
        code_module_clean AS code_module,
        code_presentation_clean AS code_presentation,
        TRY_CAST(id_site_clean AS BIGINT) AS id_site,
        LOWER(activity_type_clean) AS activity_type, -- Standardizing activity types to lowercase
        TRY_CAST(week_from_clean AS INT) AS week_from,
        TRY_CAST(week_to_clean AS INT) AS week_to,
        
        -- Validation: check if week_from <= week_to when both exist
        CASE 
            WHEN TRY_CAST(week_from_clean AS INT) IS NOT NULL 
             AND TRY_CAST(week_to_clean AS INT) IS NOT NULL 
             AND TRY_CAST(week_from_clean AS INT) > TRY_CAST(week_to_clean AS INT) 
            THEN FALSE 
            ELSE TRUE 
        END AS is_valid_date_range,

        -- Validation: Flag missing primary business keys instead of silently dropping
        CASE 
            WHEN code_module_clean IS NULL OR code_presentation_clean IS NULL OR TRY_CAST(id_site_clean AS BIGINT) IS NULL 
            THEN FALSE 
            ELSE TRUE 
        END AS has_valid_business_keys,

        -- Add audit columns
        CURRENT_TIMESTAMP() AS clean_load_timestamp,
        CURRENT_DATE() AS clean_load_date
    FROM standardized_nulls
)

-- Idempotent Upsert (Merge)
MERGE INTO open_university.oulad_silver.vle_clean AS target
USING casted_and_validated AS source
    -- We coalesce null keys to a dummy value so the merge doesn't fail on NULL = NULL comparisons for invalid records
    ON COALESCE(target.code_module, 'UNKNOWN') = COALESCE(source.code_module, 'UNKNOWN')
   AND COALESCE(target.code_presentation, 'UNKNOWN') = COALESCE(source.code_presentation, 'UNKNOWN')
   AND COALESCE(target.id_site, -999) = COALESCE(source.id_site, -999)

WHEN MATCHED THEN
    UPDATE SET
        target.activity_type = source.activity_type,
        target.week_from = source.week_from,
        target.week_to = source.week_to,
        target.is_valid_date_range = source.is_valid_date_range,
        target.has_valid_business_keys = source.has_valid_business_keys,
        target.clean_load_timestamp = source.clean_load_timestamp,
        target.clean_load_date = source.clean_load_date

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