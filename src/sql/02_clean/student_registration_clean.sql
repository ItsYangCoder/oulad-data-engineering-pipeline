-- ========================================================================================================
-- File: student_registration_clean.sql
-- Branch: feature/clean-students
--
-- Purpose:
--    Clean and prepare student registration and unregistration timing for the Silver layer while
--    preserving legitimate missing dates and the relative-day meaning of the source fields.
--
-- Input:
--    open_university.oulad_bronze.student_registration_raw
--
-- Output:
--    open_university.oulad_silver.student_registration_clean
--
-- Grain / Business Key:
--    One student registration in one module presentation;
--    (code_module, code_presentation, id_student)
--
-- Expected Clean Row Count:
--    32,593 rows for the current source delivery.
--
-- Transformation / Data Quality Decisions:
--    1. The complete enrollment key is code_module + code_presentation + id_student.
--       Records are not deduplicated by id_student alone because the same student may register
--       in multiple module presentations.
--
--    2. Source placeholder values (?, blank, NA, N/A, NULL text) are converted to SQL NULL
--       only in the Silver layer. Bronze values remain unchanged.
--
--    3. code_module and code_presentation are trimmed and standardized to uppercase.
--
--    4. id_student is cast to BIGINT.
--
--    5. date_registration and date_unregistration are converted from source STRING values
--       to INT using TRY_CAST after missing-value placeholders are normalized to SQL NULL.
--
--    6. date_registration and date_unregistration represent days relative to the start of
--       a module presentation. Negative values are valid and must not be treated as errors.
--
--    7. The 45 documented missing date_registration values are preserved as SQL NULL.
--       Missing registration dates are not replaced with 0 or otherwise inferred.
--
--    8. The 22,521 documented missing date_unregistration values are preserved as SQL NULL.
--       Missing unregistration dates are not manufactured from student outcomes or other fields.
--
--    9. A missing date_unregistration does not by itself determine whether a student withdrew.
--       The agreed dropout indicator remains final_result = 'Withdrawn' from student_info_clean.
--
--   10. The source contains 93 Withdrawn enrollments with no recorded unregistration date.
--       These are retained as valid documented source conditions.
--
--   11. The source contains 9 Fail enrollments with a recorded unregistration date.
--       These are also retained because the presence of an unregistration date does not override
--       the student's recorded final_result.
--
--   12. Required business-key values are validated before MERGE.
--       Rows whose normalized code_module, code_presentation, or id_student is NULL are
--       reported and excluded from the MERGE source. This prevents NULL-key rows from being
--       inserted repeatedly because NULL values do not match normally in a MERGE condition.
--
--   13. Optional registration/unregistration dates may remain NULL and do not cause the row
--       to be excluded from the Silver table.
--
--   14. clean_load_timestamp and clean_load_date are added for Silver-layer auditability.
--
-- Idempotency / Repeatability:
--    The target is loaded with MERGE using the complete enrollment business key.
--    Existing registration records are updated and new registrations are inserted.
--
--    Rows with incomplete required business keys are excluded before MERGE so they cannot
--    create repeated NULL-key records on reruns.
--
-- Relationship Rule:
--    student_registration_clean must match student_info_clean using the complete enrollment key:
--    code_module + code_presentation + id_student.
--
--    Joining only on id_student is not sufficient because one student may have multiple
--    module-presentation enrollments.
--
-- Validation Expectations for the Current Batch:
--    - student_registration_clean row count = 32,593
--    - invalid required business keys = 0
--    - incomplete Silver business keys = 0
--    - duplicate complete business keys = 0
--    - Bronze enrollment keys missing from Silver = 0
--    - unexpected Silver enrollment keys = 0
--    - date_registration NULL count = 45
--    - date_unregistration NULL count = 22,521
--    - unexplained date conversion losses = 0
--    - unnormalized module/presentation codes = 0
--    - remaining source placeholders = 0
--    - missing audit fields = 0
--    - student_registration_clean -> student_info_clean orphan count = 0
--    - Withdrawn + NULL date_unregistration count = 93
--    - Fail + non-NULL date_unregistration count = 9
--
-- Important Business Rules:
--    - Negative relative-day values are valid.
--    - Unknown dates remain NULL and must not be replaced with day 0.
--    - date_unregistration provides timing information when available, not the authoritative
--      definition of dropout.
--    - Dropout remains final_result = 'Withdrawn'.
--    - The current fixed validation counts apply to this source delivery and should be
--      reviewed when a new batch is introduced.
--
-- ========================================================================================================


-- ========================================================================================================
-- STEP 0: CREATE THE SILVER TARGET TABLE
-- ========================================================================================================

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


-- ========================================================================================================
-- STEP 1: VALIDATE REQUIRED BUSINESS KEYS BEFORE MERGE
-- ========================================================================================================
--
-- Required business-key components are normalized using the same rules applied by the
-- Silver transformation.
--
-- Rows where any normalized key component becomes NULL are reported here before loading.
--
-- These rows must not participate in the MERGE because normal SQL equality does not match
-- NULL values. Allowing incomplete keys into the MERGE could therefore insert another copy
-- of the same invalid source row on every rerun.
--
-- Expected current-batch result:
--    invalid_business_key_rows = 0
-- ========================================================================================================

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


-- ========================================================================================================
-- STEP 2: NORMALIZE, TYPE, AND PREPARE SOURCE DATA
-- ========================================================================================================

MERGE INTO
    open_university.oulad_silver.student_registration_clean AS target

-- MERGE makes repeated executions idempotent for valid complete business keys.
-- Invalid required keys are excluded from the source before this MERGE.

USING (

    WITH normalized AS (

        SELECT

            -- ------------------------------------------------
            -- Standardize module code.
            -- ------------------------------------------------
            CASE
                WHEN UPPER(TRIM(code_module)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE UPPER(TRIM(code_module))
            END AS code_module,


            -- ------------------------------------------------
            -- Standardize presentation code.
            -- ------------------------------------------------
            CASE
                WHEN UPPER(TRIM(code_presentation)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE UPPER(TRIM(code_presentation))
            END AS code_presentation,


            -- ------------------------------------------------
            -- Cast student ID to the agreed Silver type.
            -- ------------------------------------------------
            TRY_CAST(id_student AS BIGINT) AS id_student,


            -- ------------------------------------------------
            -- Registration date
            --
            -- Source type: STRING
            -- Silver type: INT
            --
            -- Convert source missing-value representations
            -- such as '?' to SQL NULL before casting.
            --
            -- Negative values are valid because this represents
            -- days relative to the presentation start.
            -- ------------------------------------------------
            CASE
                WHEN UPPER(TRIM(date_registration)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE TRY_CAST(
                    TRIM(date_registration) AS INT
                )
            END AS date_registration,


            -- ------------------------------------------------
            -- Unregistration date
            --
            -- Source type: STRING
            -- Silver type: INT
            --
            -- Missing values are preserved as SQL NULL.
            -- Do not infer or manufacture withdrawal dates.
            -- ------------------------------------------------
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


-- ========================================================================================================
-- STEP 3: MATCH USING THE COMPLETE ENROLLMENT KEY
-- ========================================================================================================

ON  target.code_module       = source.code_module
AND target.code_presentation = source.code_presentation
AND target.id_student        = source.id_student


-- ========================================================================================================
-- STEP 4: UPDATE EXISTING REGISTRATIONS
-- ========================================================================================================

WHEN MATCHED THEN UPDATE SET

    target.date_registration    = source.date_registration,
    target.date_unregistration  = source.date_unregistration,
    target.clean_load_timestamp = source.clean_load_timestamp,
    target.clean_load_date      = source.clean_load_date


-- ========================================================================================================
-- STEP 5: INSERT NEW REGISTRATIONS
-- ========================================================================================================

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