-- Cleans student enrollment and demographic data for the Silver layer.
-- One row represents one student in one module presentation.
-- Missing demographic values stay NULL, and MERGE prevents duplicate enrollments.

CREATE TABLE IF NOT EXISTS
    open_university.oulad_silver.student_info_clean
(
    code_module            STRING,
    code_presentation      STRING,
    id_student             BIGINT,
    gender                 STRING,
    region                 STRING,
    highest_education      STRING,
    imd_band               STRING,
    age_band               STRING,
    num_of_prev_attempts   INT,
    studied_credits        INT,
    disability             STRING,
    final_result           STRING,
    clean_load_timestamp   TIMESTAMP,
    clean_load_date        DATE
)
USING DELTA;


-- Step 1: Validate required business keys before merge
-- Required business-key components are normalized using the same rules applied by the
-- Silver transformation.
-- Rows where any normalized key component becomes NULL are reported here before loading.
-- These rows must not participate in the MERGE because normal SQL equality does not match
-- NULL values. Allowing incomplete keys into the MERGE could therefore insert another copy
-- of the same invalid source row on every rerun.
-- Expected current-batch result:
--    invalid_business_key_rows = 0

WITH normalized_keys AS (

    SELECT

        CASE
            WHEN UPPER(TRIM(code_module)) IN
                 ('', '?', 'NA', 'N/A', 'NULL')
            THEN NULL

            ELSE UPPER(TRIM(code_module))
        END AS code_module,


        CASE
            WHEN UPPER(TRIM(code_presentation)) IN
                 ('', '?', 'NA', 'N/A', 'NULL')
            THEN NULL

            ELSE UPPER(TRIM(code_presentation))
        END AS code_presentation,


        TRY_CAST(id_student AS BIGINT) AS id_student

    FROM open_university.oulad_bronze.student_info_raw
)

SELECT
    COUNT(*) AS invalid_business_key_rows

FROM normalized_keys

WHERE code_module IS NULL
   OR code_presentation IS NULL
   OR id_student IS NULL;


-- Step 2: Normalize, type, and prepare source data

MERGE INTO open_university.oulad_silver.student_info_clean AS target

-- MERGE makes repeated executions idempotent for valid complete business keys.
-- Invalid required keys are excluded from the source before this MERGE.

USING (

    WITH normalized AS (

        SELECT

            -- Standardize module code.
            CASE
                WHEN UPPER(TRIM(code_module)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE UPPER(TRIM(code_module))
            END AS code_module,


            -- Standardize presentation code.
            CASE
                WHEN UPPER(TRIM(code_presentation)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE UPPER(TRIM(code_presentation))
            END AS code_presentation,


            -- Cast student ID to the agreed Silver type.
            TRY_CAST(id_student AS BIGINT) AS id_student,


            -- Standardize gender.
            CASE
                WHEN UPPER(TRIM(gender)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE UPPER(TRIM(gender))
            END AS gender,


            -- Preserve category meaning while removing
            -- unnecessary surrounding spaces.
            CASE
                WHEN UPPER(TRIM(region)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE TRIM(region)
            END AS region,


            CASE
                WHEN UPPER(TRIM(highest_education)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE TRIM(highest_education)
            END AS highest_education,


            -- Standardize IMD band.
            -- Missing values remain NULL.
            -- The source category '10-20' is standardized
            -- to '10-20%' for consistency with the other bands.
            CASE
                WHEN UPPER(TRIM(imd_band)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                WHEN TRIM(imd_band) = '10-20'
                THEN '10-20%'

                ELSE TRIM(imd_band)
            END AS imd_band,


            CASE
                WHEN UPPER(TRIM(age_band)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE TRIM(age_band)
            END AS age_band,


            TRY_CAST(
                num_of_prev_attempts AS INT
            ) AS num_of_prev_attempts,


            TRY_CAST(
                studied_credits AS INT
            ) AS studied_credits,


            -- Standardize disability indicator.
            CASE
                WHEN UPPER(TRIM(disability)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE UPPER(TRIM(disability))
            END AS disability,


            -- Normalize final_result to the agreed categories
            -- without changing its business meaning.
            CASE
                WHEN UPPER(TRIM(final_result)) = 'DISTINCTION'
                    THEN 'Distinction'

                WHEN UPPER(TRIM(final_result)) = 'FAIL'
                    THEN 'Fail'

                WHEN UPPER(TRIM(final_result)) = 'PASS'
                    THEN 'Pass'

                WHEN UPPER(TRIM(final_result)) = 'WITHDRAWN'
                    THEN 'Withdrawn'

                WHEN UPPER(TRIM(final_result)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                    THEN NULL

                ELSE TRIM(final_result)
            END AS final_result

        FROM open_university.oulad_bronze.student_info_raw
    ),


    prepared AS (

        SELECT
            code_module,
            code_presentation,
            id_student,
            gender,
            region,
            highest_education,
            imd_band,
            age_band,
            num_of_prev_attempts,
            studied_credits,
            disability,
            final_result,

            CURRENT_TIMESTAMP() AS clean_load_timestamp,
            CURRENT_DATE() AS clean_load_date

        FROM normalized

        -- Protect the complete enrollment key before MERGE.
        -- Incomplete keys were reported in STEP 1 and are excluded here
        -- so NULL-key rows cannot be reinserted on subsequent runs.
        WHERE code_module IS NOT NULL
          AND code_presentation IS NOT NULL
          AND id_student IS NOT NULL
    )

    SELECT *
    FROM prepared

) AS source


-- Step 3: Match using the complete enrollment key

ON  target.code_module       = source.code_module
AND target.code_presentation = source.code_presentation
AND target.id_student        = source.id_student


-- Step 4: Update existing enrollments

WHEN MATCHED THEN UPDATE SET

    target.gender               = source.gender,
    target.region               = source.region,
    target.highest_education    = source.highest_education,
    target.imd_band             = source.imd_band,
    target.age_band             = source.age_band,
    target.num_of_prev_attempts = source.num_of_prev_attempts,
    target.studied_credits      = source.studied_credits,
    target.disability           = source.disability,
    target.final_result         = source.final_result,
    target.clean_load_timestamp = source.clean_load_timestamp,
    target.clean_load_date      = source.clean_load_date


-- Step 5: Insert new enrollments

WHEN NOT MATCHED THEN INSERT
(
    code_module,
    code_presentation,
    id_student,
    gender,
    region,
    highest_education,
    imd_band,
    age_band,
    num_of_prev_attempts,
    studied_credits,
    disability,
    final_result,
    clean_load_timestamp,
    clean_load_date
)

VALUES
(
    source.code_module,
    source.code_presentation,
    source.id_student,
    source.gender,
    source.region,
    source.highest_education,
    source.imd_band,
    source.age_band,
    source.num_of_prev_attempts,
    source.studied_credits,
    source.disability,
    source.final_result,
    source.clean_load_timestamp,
    source.clean_load_date
);