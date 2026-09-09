-- Cleans registration and unregistration dates for the Silver layer.
-- Dates are day numbers relative to the presentation start, so negative values are valid.
-- Missing dates stay NULL. One row represents one student registration per presentation.

CREATE TABLE IF NOT EXISTS
    open_university.oulad_silver.student_registration_clean
(
    code_module              STRING,
    code_presentation        STRING,
    id_student               BIGINT,
    date_registration        INT,
    date_unregistration      INT,
    clean_load_timestamp     TIMESTAMP,
    clean_load_date          DATE
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

    FROM open_university.oulad_bronze.student_registration_raw
)

SELECT
    COUNT(*) AS invalid_business_key_rows

FROM normalized_keys

WHERE code_module IS NULL
   OR code_presentation IS NULL
   OR id_student IS NULL;


-- Step 2: Normalize, type, and prepare source data

MERGE INTO
    open_university.oulad_silver.student_registration_clean AS target

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


            -- Registration date
            -- Source type: STRING
            -- Silver type: INT
            -- Convert source missing-value representations
            -- such as '?' to SQL NULL before casting.
            -- Negative values are valid because this represents
            -- days relative to the presentation start.
            CASE
                WHEN UPPER(TRIM(date_registration)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE TRY_CAST(
                    TRIM(date_registration) AS INT
                )
            END AS date_registration,


            -- Unregistration date
            -- Source type: STRING
            -- Silver type: INT
            -- Missing values are preserved as SQL NULL.
            -- Do not infer or manufacture withdrawal dates.
            CASE
                WHEN UPPER(TRIM(date_unregistration)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE TRY_CAST(
                    TRIM(date_unregistration) AS INT
                )
            END AS date_unregistration

        FROM
            open_university.oulad_bronze.student_registration_raw
    ),


    prepared AS (

        SELECT
            code_module,
            code_presentation,
            id_student,
            date_registration,
            date_unregistration,

            -- Silver audit fields.
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


-- Step 4: Update existing registrations

WHEN MATCHED THEN UPDATE SET

    target.date_registration    = source.date_registration,
    target.date_unregistration  = source.date_unregistration,
    target.clean_load_timestamp = source.clean_load_timestamp,
    target.clean_load_date      = source.clean_load_date


-- Step 5: Insert new registrations

WHEN NOT MATCHED THEN INSERT
(
    code_module,
    code_presentation,
    id_student,
    date_registration,
    date_unregistration,
    clean_load_timestamp,
    clean_load_date
)

VALUES
(
    source.code_module,
    source.code_presentation,
    source.id_student,
    source.date_registration,
    source.date_unregistration,
    source.clean_load_timestamp,
    source.clean_load_date
);