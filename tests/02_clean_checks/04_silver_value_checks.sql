-- ========================================================================================================
-- File: tests/02_clean_checks/04_silver_value_checks.sql
--
-- Objective:
--    Validate domain values, normalized source values, schema data types,
--    and metadata flag accuracy for currently implemented Silver clean tables.
--
-- Scope:
--    Currently implemented Silver transformations:
--      - courses_clean
--      - student_info_clean
--      - student_registration_clean
--
-- Ensures:
--    courses_clean:
--      1. module_presentation_length contains only valid positive values when populated.
--      2. is_valid_length correctly reflects the validity of module_presentation_length.
--      3. Invalid business-key records are not present in the clean Silver table.
--
--    student_info_clean / student_registration_clean:
--      1. Silver columns use the agreed physical data types.
--      2. Source placeholder values do not remain as text after cleaning.
--      3. Categorical attributes contain only accepted normalized values.
--      4. Numeric student attributes contain valid nonnegative values.
--
-- Important Data Quality Decisions:
--    - NULL imd_band values are valid because the current source delivery contains
--      1,111 documented missing IMD values.
--
--    - Source imd_band = '10-20' is normalized to '10-20%'.
--
--    - Databricks type validation uses full_data_type rather than data_type because
--      metadata aliases such as LONG may be shown for BIGINT columns.
--
--    - Negative registration and unregistration relative-day values are valid and
--      therefore are not treated as value-range failures.
--
-- Output:
--    Read-only validation queries showing failure counts and PASS/FAIL status.
--
-- No data is inserted, updated, deleted, or otherwise modified by this file.
-- ========================================================================================================



-- ========================================================================================================
-- SECTION 1: COURSES CLEAN VALUE CHECKS
-- ========================================================================================================


-- ========================================================================================================
-- CHECK 1: COURSES CLEAN - LENGTH DOMAIN VALIDITY
-- ========================================================================================================
--
-- module_presentation_length must be a positive value when populated.
--
-- Invalid values include:
--    - zero
--    - negative values
--
-- NULL is not treated as a domain violation here because missing values are handled separately
-- by the is_valid_length flag check.
--
-- Expected result:
--    invalid_rows = 0
--    check_status = PASS
-- ========================================================================================================

SELECT

    'courses_clean_invalid_length_values' AS check_name,

    COUNT(*) AS invalid_rows,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status

FROM open_university.oulad_silver.courses_clean

WHERE module_presentation_length IS NOT NULL
  AND module_presentation_length <= 0;



-- ========================================================================================================
-- CHECK 2: COURSES CLEAN - LENGTH FLAG ACCURACY
-- ========================================================================================================
--
-- is_valid_length must correctly describe module_presentation_length.
--
-- Expected rule:
--    TRUE  -> module_presentation_length is present and greater than zero.
--    FALSE -> module_presentation_length is NULL or not greater than zero.
--
-- Expected result:
--    mismatch_rows = 0
--    check_status = PASS
-- ========================================================================================================

SELECT

    'courses_clean_flag_accuracy' AS check_name,

    COUNT(*) AS mismatch_rows,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status

FROM open_university.oulad_silver.courses_clean

WHERE
      (
          is_valid_length = TRUE
          AND (
              module_presentation_length IS NULL
              OR module_presentation_length <= 0
          )
      )

   OR (
          is_valid_length = FALSE
          AND (
              module_presentation_length IS NOT NULL
              AND module_presentation_length > 0
          )
      );



-- ========================================================================================================
-- CHECK 3: COURSES CLEAN - BUSINESS KEY FLAG ACCURACY
-- ========================================================================================================
--
-- Invalid business keys should not remain in courses_clean.
--
-- Invalid/conflicting business-key records are expected to be handled by the
-- courses_clean transformation and routed to the quarantine table.
--
-- Expected result:
--    invalid_key_flag_rows = 0
--    check_status = PASS
-- ========================================================================================================

SELECT

    'courses_clean_is_valid_key_check' AS check_name,

    COUNT(*) AS invalid_key_flag_rows,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status

FROM open_university.oulad_silver.courses_clean

WHERE is_valid_key = FALSE;



-- ========================================================================================================
-- SECTION 2: STUDENT INFO AND STUDENT REGISTRATION VALUE CHECKS
-- ========================================================================================================


-- ========================================================================================================
-- PREPARATION: DEFINE EXPECTED SILVER COLUMN TYPES
-- ========================================================================================================
--
-- Define the expected physical data type for every column owned by the Task #9
-- student Silver transformations.
--
-- These expected types are compared with Unity Catalog metadata below.
-- ========================================================================================================

WITH expected_types AS (

    SELECT *
    FROM VALUES

        ('student_info_clean', 'code_module', 'string'),
        ('student_info_clean', 'code_presentation', 'string'),
        ('student_info_clean', 'id_student', 'bigint'),
        ('student_info_clean', 'gender', 'string'),
        ('student_info_clean', 'region', 'string'),
        ('student_info_clean', 'highest_education', 'string'),
        ('student_info_clean', 'imd_band', 'string'),
        ('student_info_clean', 'age_band', 'string'),
        ('student_info_clean', 'num_of_prev_attempts', 'int'),
        ('student_info_clean', 'studied_credits', 'int'),
        ('student_info_clean', 'disability', 'string'),
        ('student_info_clean', 'final_result', 'string'),
        ('student_info_clean', 'clean_load_timestamp', 'timestamp'),
        ('student_info_clean', 'clean_load_date', 'date'),

        ('student_registration_clean', 'code_module', 'string'),
        ('student_registration_clean', 'code_presentation', 'string'),
        ('student_registration_clean', 'id_student', 'bigint'),
        ('student_registration_clean', 'date_registration', 'int'),
        ('student_registration_clean', 'date_unregistration', 'int'),
        ('student_registration_clean', 'clean_load_timestamp', 'timestamp'),
        ('student_registration_clean', 'clean_load_date', 'date')

    AS t(table_name, column_name, expected_type)

),


-- ========================================================================================================
-- PREPARATION: IDENTIFY SILVER TYPE MISMATCHES
-- ========================================================================================================
--
-- Compare the expected definitions above against actual Unity Catalog metadata.
--
-- full_data_type is used instead of data_type because Databricks may display aliases,
-- such as LONG, even when the underlying physical type is BIGINT.
--
-- A mismatch is recorded when:
--    1. An expected column cannot be found, OR
--    2. Its physical data type differs from the expected type.
--
-- Expected result:
--    type mismatches = 0
-- ========================================================================================================

type_mismatches AS (

    SELECT
        e.table_name,
        e.column_name,
        e.expected_type,
        LOWER(c.full_data_type) AS actual_type

    FROM expected_types AS e

    LEFT JOIN open_university.information_schema.columns AS c
        ON  c.table_schema = 'oulad_silver'
        AND c.table_name = e.table_name
        AND c.column_name = e.column_name

    WHERE c.column_name IS NULL
       OR LOWER(c.full_data_type) <> e.expected_type

)


-- ========================================================================================================
-- CHECK 1: STUDENT SILVER SCHEMA TYPES
-- ========================================================================================================
--
-- Confirm that all expected columns across student_info_clean and
-- student_registration_clean exist and use the agreed physical Silver data types.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'Student Silver schema' AS check_name,
    'student_info_clean + student_registration_clean' AS column_or_rule,

    COUNT(*) AS failure_count,

    0 AS expected_count,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END AS status

FROM type_mismatches



UNION ALL



-- ========================================================================================================
-- CHECK 2: STUDENT INFO CLEAN - SOURCE PLACEHOLDER NORMALIZATION
-- ========================================================================================================
--
-- Confirm that documented textual placeholder values have not survived into the
-- cleaned student_info_clean text attributes.
--
-- Values checked:
--    ?
--    NA
--    N/A
--    NULL text
--
-- Actual SQL NULL values are not treated as textual placeholders by this check.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'Source placeholder normalization',
    'student_info_clean text columns',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE UPPER(TRIM(COALESCE(code_module, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(code_presentation, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(gender, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(region, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(highest_education, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(imd_band, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(age_band, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(disability, '')))
          IN ('?', 'NA', 'N/A', 'NULL')

   OR UPPER(TRIM(COALESCE(final_result, '')))
          IN ('?', 'NA', 'N/A', 'NULL')



UNION ALL



-- ========================================================================================================
-- CHECK 3: STUDENT INFO CLEAN - ACCEPTED GENDER VALUES
-- ========================================================================================================
--
-- gender is standardized to uppercase during cleaning.
--
-- Accepted values:
--    F
--    M
--
-- NULL gender values are considered failures.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'Accepted values',
    'gender',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE gender NOT IN ('F', 'M')
   OR gender IS NULL



UNION ALL



-- ========================================================================================================
-- CHECK 4: STUDENT INFO CLEAN - ACCEPTED DISABILITY VALUES
-- ========================================================================================================
--
-- disability is standardized to uppercase during cleaning.
--
-- Accepted values:
--    Y
--    N
--
-- NULL disability values are considered failures.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'Accepted values',
    'disability',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE disability NOT IN ('Y', 'N')
   OR disability IS NULL



UNION ALL



-- ========================================================================================================
-- CHECK 5: STUDENT INFO CLEAN - ACCEPTED FINAL RESULT VALUES
-- ========================================================================================================
--
-- final_result is normalized to the agreed canonical outcome categories.
--
-- Accepted values:
--    Distinction
--    Fail
--    Pass
--    Withdrawn
--
-- NULL final_result values are considered failures.
--
-- Dropout classification continues to use:
--    final_result = 'Withdrawn'
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'Accepted values',
    'final_result',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE final_result NOT IN (
    'Distinction',
    'Fail',
    'Pass',
    'Withdrawn'
)
OR final_result IS NULL



UNION ALL



-- ========================================================================================================
-- CHECK 6: STUDENT INFO CLEAN - ACCEPTED IMD BAND VALUES
-- ========================================================================================================
--
-- Confirm that every populated imd_band belongs to the agreed percentage-band categories.
--
-- The original source value '10-20' is expected to have been standardized to '10-20%'.
--
-- NULL imd_band values are intentionally allowed because the current source delivery
-- contains 1,111 documented missing IMD values.
--
-- Accepted populated values:
--    0-10%
--    10-20%
--    20-30%
--    30-40%
--    40-50%
--    50-60%
--    60-70%
--    70-80%
--    80-90%
--    90-100%
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'Accepted values',
    'imd_band',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE imd_band IS NOT NULL
  AND imd_band NOT IN (
        '0-10%',
        '10-20%',
        '20-30%',
        '30-40%',
        '40-50%',
        '50-60%',
        '60-70%',
        '70-80%',
        '80-90%',
        '90-100%'
  )



UNION ALL



-- ========================================================================================================
-- CHECK 7: STUDENT INFO CLEAN - PREVIOUS ATTEMPTS RANGE
-- ========================================================================================================
--
-- num_of_prev_attempts represents the number of previous attempts associated
-- with an enrollment.
--
-- Valid values must:
--    - be non-NULL
--    - be greater than or equal to 0
--
-- Negative attempt counts have no valid business interpretation.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'Numeric range',
    'num_of_prev_attempts',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE num_of_prev_attempts IS NULL
   OR num_of_prev_attempts < 0



UNION ALL



-- ========================================================================================================
-- CHECK 8: STUDENT INFO CLEAN - STUDIED CREDITS RANGE
-- ========================================================================================================
--
-- studied_credits records the number of credits associated with the student's enrollment.
--
-- Valid values must:
--    - be non-NULL
--    - be greater than or equal to 0
--
-- Negative credit values are considered invalid.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'Numeric range',
    'studied_credits',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE studied_credits IS NULL
   OR studied_credits < 0;