-- File: assessment_clean.sql

-- Suggested branch: feature/clean-assessments

-- Purpose:
-- Prepare assessment definitions by cleaning text fields,
-- converting data types, and preserving valid missing dates.

-- Input:
-- open_university.oulad_bronze.assessment_raw

-- Output:
-- open_university.oulad_silver.assessment_clean

-- Grain / business key:
-- One row per assessment; id_assessment.

-- Expected current batch:
-- 206 rows.
-- 11 assessment dates are intentionally missing and belong to Exam records.
-- Missing dates must remain NULL; they must NOT be removed or replaced with a fake date.

-- ============================================================
-- STEP 1: Create the Silver table if it does not exist.
-- ============================================================

CREATE TABLE IF NOT EXISTS open_university.oulad_silver.assessment_clean (
    code_module STRING,
    code_presentation STRING,
    id_assessment BIGINT,
    assessment_type STRING,
    date INT,
    weight DECIMAL(5,2),
    clean_load_timestamp TIMESTAMP,
    clean_load_date DATE
)
USING DELTA;


-- ============================================================
-- STEP 2: Clean the Bronze data.
-- ============================================================

MERGE INTO open_university.oulad_silver.assessment_clean AS target

USING (

    WITH cleaned AS (

        SELECT
            -- TRIM removes unnecessary spaces from text values.
            TRIM(code_module) AS code_module,

            TRIM(code_presentation) AS code_presentation,

            -- Convert the assessment ID from INT to BIGINT.
            -- TRY_CAST prevents the entire query from failing
            -- if an unexpected non-numeric value appears.
            TRY_CAST(id_assessment AS BIGINT) AS id_assessment,

            -- Standardize assessment type.
            -- TMA and CMA remain uppercase.
            -- Exam is standardized to "Exam".
            CASE
                WHEN UPPER(TRIM(assessment_type)) = 'TMA'
                    THEN 'TMA'

                WHEN UPPER(TRIM(assessment_type)) = 'CMA'
                    THEN 'CMA'

                WHEN UPPER(TRIM(assessment_type)) = 'EXAM'
                    THEN 'Exam'

                ELSE NULL
            END AS assessment_type,

            -- The Bronze date column is STRING.
            --
            -- NULLIF converts a blank string into SQL NULL.
            -- TRY_CAST then converts the remaining value to INT.
            --
            -- Missing assessment dates are preserved as NULL.
            TRY_CAST(
                NULLIF(TRIM(date), '')
                AS INT
            ) AS date,

            -- Convert weight from DOUBLE to DECIMAL.
            TRY_CAST(weight AS DECIMAL(5,2)) AS weight

        FROM open_university.oulad_bronze.assessment_raw
    )

    SELECT
        code_module,
        code_presentation,
        id_assessment,
        assessment_type,
        date,
        weight,

        -- Audit timestamp:
        -- records when the clean record was loaded.
        CURRENT_TIMESTAMP() AS clean_load_timestamp,

        -- Audit date:
        -- records the calendar date when the clean record was loaded.
        CURRENT_DATE() AS clean_load_date

    FROM cleaned

) AS source

-- Use the complete business key to identify
-- the same assessment during repeated loads.
ON target.id_assessment = source.id_assessment

-- If the assessment already exists, update it.
WHEN MATCHED THEN UPDATE SET
    target.code_module = source.code_module,
    target.code_presentation = source.code_presentation,
    target.assessment_type = source.assessment_type,
    target.date = source.date,
    target.weight = source.weight,
    target.clean_load_timestamp = source.clean_load_timestamp,
    target.clean_load_date = source.clean_load_date

-- If the assessment does not exist, insert it.
WHEN NOT MATCHED THEN INSERT (
    code_module,
    code_presentation,
    id_assessment,
    assessment_type,
    date,
    weight,
    clean_load_timestamp,
    clean_load_date
)
VALUES (
    source.code_module,
    source.code_presentation,
    source.id_assessment,
    source.assessment_type,
    source.date,
    source.weight,
    source.clean_load_timestamp,
    source.clean_load_date
);