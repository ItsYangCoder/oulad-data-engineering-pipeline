-- ========================================================================================================
-- File: tests/02_clean_checks/03_silver_null_checks.sql
-- Branch: feature/clean-students
--
-- Objective:
--    Validate required NULL constraints, documented optional NULL values, and known
--    registration/outcome exceptions for the student Silver tables.
--
--    Ensures:
--      1. Required business-key attributes and Silver audit fields are not NULL.
--      2. Documented optional missing values are preserved with the expected current-batch counts.
--      3. Valid Bronze registration/unregistration values are not lost during STRING-to-INT conversion.
--      4. Known outcome/date exceptions are preserved rather than incorrectly treated as errors.
--
-- Scope:
--    Silver transformations owned by Task #9:
--      - student_info_clean
--      - student_registration_clean
--
-- Expected Optional NULLs:
--    student_info_clean.imd_band:
--      1,111
--
--    student_registration_clean.date_registration:
--      45
--
--    student_registration_clean.date_unregistration:
--      22,521
--
-- Expected Outcome / Date Conditions:
--    Withdrawn enrollments with NULL date_unregistration:
--      93
--
--    Fail enrollments with non-NULL date_unregistration:
--      9
--
-- Important Business Rules:
--    - Missing optional values are preserved as SQL NULL rather than imputed.
--    - A missing date_unregistration does not automatically mean the source record is invalid.
--    - Dropout is determined from final_result = 'Withdrawn', not from the presence or absence
--      of date_unregistration alone.
--    - Registration and unregistration dates are relative-day values; negative values are valid.
--
-- Output:
--    Read-only validation results showing the table, validation rule, affected column/rule,
--    actual count, expected count, and PASS/FAIL status.
--
-- No data is inserted, updated, deleted, or otherwise modified by this file.
-- ========================================================================================================


-- ========================================================================================================
-- PREPARATION: DETECT REGISTRATION DATE CONVERSION LOSSES
-- ========================================================================================================
--
-- Compare non-missing Bronze date values with the corresponding typed Silver values.
--
-- A conversion loss occurs when:
--    - Bronze contains a real source value rather than a documented missing-value placeholder, AND
--    - the corresponding Silver INT value is NULL.
--
-- The join uses the complete enrollment key:
--    code_module + code_presentation + id_student
--
-- Expected result:
--    conversion-loss rows = 0
-- ========================================================================================================

WITH registration_conversion_losses AS (

    SELECT
        b.code_module,
        b.code_presentation,
        b.id_student

    FROM open_university.oulad_bronze.student_registration_raw AS b

    INNER JOIN open_university.oulad_silver.student_registration_clean AS s
        ON  UPPER(TRIM(b.code_module)) = s.code_module
        AND UPPER(TRIM(b.code_presentation)) = s.code_presentation
        AND TRY_CAST(b.id_student AS BIGINT) = s.id_student

    WHERE
        (
            UPPER(TRIM(b.date_registration))
                NOT IN ('', '?', 'NA', 'N/A', 'NULL')
            AND s.date_registration IS NULL
        )

        OR

        (
            UPPER(TRIM(b.date_unregistration))
                NOT IN ('', '?', 'NA', 'N/A', 'NULL')
            AND s.date_unregistration IS NULL
        )

)


-- ========================================================================================================
-- CHECK 1: STUDENT INFO CLEAN - EXPECTED NULL IMD BAND VALUES
-- ========================================================================================================
--
-- The source contains 1,111 enrollments with missing imd_band values.
--
-- These are valid documented missing values and must remain SQL NULL in Silver.
-- They must not be replaced with a default demographic category.
--
-- Expected result:
--    actual_count = 1,111
--    status = Pass
-- ========================================================================================================

SELECT
    'student_info_clean' AS table_name,
    'Expected optional NULLs' AS check_name,
    'imd_band' AS column_name,
    COUNT(*) AS actual_count,
    1111 AS expected_count,

    CASE
        WHEN COUNT(*) = 1111 THEN 'Pass'
        ELSE 'Fail'
    END AS status

FROM open_university.oulad_silver.student_info_clean
WHERE imd_band IS NULL


UNION ALL


-- ========================================================================================================
-- CHECK 2: STUDENT REGISTRATION CLEAN - EXPECTED NULL REGISTRATION DATES
-- ========================================================================================================
--
-- The current source batch contains 45 registrations with no recorded date_registration.
--
-- These values are intentionally preserved as SQL NULL rather than being replaced with 0
-- or an inferred relative day.
--
-- Expected result:
--    actual_count = 45
--    status = Pass
-- ========================================================================================================

SELECT
    'student_registration_clean',
    'Expected optional NULLs',
    'date_registration',
    COUNT(*),
    45,

    CASE
        WHEN COUNT(*) = 45 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean
WHERE date_registration IS NULL


UNION ALL


-- ========================================================================================================
-- CHECK 3: STUDENT REGISTRATION CLEAN - EXPECTED NULL UNREGISTRATION DATES
-- ========================================================================================================
--
-- The current source batch contains 22,521 registrations with no recorded date_unregistration.
--
-- A NULL date_unregistration is an expected condition for many enrollments and must not
-- automatically be interpreted as a data-quality failure.
--
-- Expected result:
--    actual_count = 22,521
--    status = Pass
-- ========================================================================================================

SELECT
    'student_registration_clean',
    'Expected optional NULLs',
    'date_unregistration',
    COUNT(*),
    22521,

    CASE
        WHEN COUNT(*) = 22521 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean
WHERE date_unregistration IS NULL


UNION ALL


-- ========================================================================================================
-- CHECK 4: STUDENT INFO CLEAN - REQUIRED BUSINESS KEY AND AUDIT FIELDS
-- ========================================================================================================
--
-- Every student_info_clean record must contain:
--    - code_module
--    - code_presentation
--    - id_student
--    - clean_load_timestamp
--    - clean_load_date
--
-- Optional demographic attributes such as imd_band are intentionally excluded from this check.
--
-- Expected result:
--    actual_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_info_clean',
    'Required NULL check',
    'business key + audit fields',
    COUNT(*),
    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE code_module IS NULL
   OR code_presentation IS NULL
   OR id_student IS NULL
   OR clean_load_timestamp IS NULL
   OR clean_load_date IS NULL


UNION ALL


-- ========================================================================================================
-- CHECK 5: STUDENT REGISTRATION CLEAN - REQUIRED BUSINESS KEY AND AUDIT FIELDS
-- ========================================================================================================
--
-- Every student_registration_clean record must contain:
--    - code_module
--    - code_presentation
--    - id_student
--    - clean_load_timestamp
--    - clean_load_date
--
-- date_registration and date_unregistration are optional and are therefore not included
-- in this required-field NULL check.
--
-- Expected result:
--    actual_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_registration_clean',
    'Required NULL check',
    'business key + audit fields',
    COUNT(*),
    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean

WHERE code_module IS NULL
   OR code_presentation IS NULL
   OR id_student IS NULL
   OR clean_load_timestamp IS NULL
   OR clean_load_date IS NULL


UNION ALL


-- ========================================================================================================
-- CHECK 6: STUDENT REGISTRATION CLEAN - DATE CONVERSION LOSS
-- ========================================================================================================
--
-- Confirms that valid non-missing Bronze registration/unregistration values did not
-- become NULL during Silver type conversion.
--
-- Missing-value placeholders are intentionally excluded from conversion-loss detection.
--
-- Expected result:
--    actual_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_registration_clean',
    'Conversion loss',
    'date_registration + date_unregistration',
    COUNT(*),
    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM registration_conversion_losses


UNION ALL


-- ========================================================================================================
-- CHECK 7: WITHDRAWN ENROLLMENTS WITH NO UNREGISTRATION DATE
-- ========================================================================================================
--
-- The source contains 93 enrollments where:
--
--    final_result = 'Withdrawn'
--    AND date_unregistration IS NULL
--
-- These records are expected and must be preserved.
--
-- This confirms that a missing unregistration date does not invalidate a Withdrawn outcome
-- and that no missing withdrawal date has been invented during cleaning.
--
-- The join uses the complete enrollment key.
--
-- Expected result:
--    actual_count = 93
--    status = Pass
-- ========================================================================================================

SELECT
    'student_registration_clean',
    'Expected outcome/date condition',
    'Withdrawn + NULL date_unregistration',
    COUNT(*),
    93,

    CASE
        WHEN COUNT(*) = 93 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean AS sr

INNER JOIN open_university.oulad_silver.student_info_clean AS si
    ON  sr.code_module = si.code_module
    AND sr.code_presentation = si.code_presentation
    AND sr.id_student = si.id_student

WHERE si.final_result = 'Withdrawn'
  AND sr.date_unregistration IS NULL


UNION ALL


-- ========================================================================================================
-- CHECK 8: FAIL ENROLLMENTS WITH AN UNREGISTRATION DATE
-- ========================================================================================================
--
-- The source contains 9 enrollments where:
--
--    final_result = 'Fail'
--    AND date_unregistration IS NOT NULL
--
-- These records are expected and must remain unchanged.
--
-- This confirms that the existence of an unregistration date does not automatically
-- redefine the student's final_result as Withdrawn.
--
-- The authoritative dropout indicator remains:
--    final_result = 'Withdrawn'
--
-- Expected result:
--    actual_count = 9
--    status = Pass
-- ========================================================================================================

SELECT
    'student_registration_clean',
    'Expected outcome/date condition',
    'Fail + non-NULL date_unregistration',
    COUNT(*),
    9,

    CASE
        WHEN COUNT(*) = 9 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean AS sr

INNER JOIN open_university.oulad_silver.student_info_clean AS si
    ON  sr.code_module = si.code_module
    AND sr.code_presentation = si.code_presentation
    AND sr.id_student = si.id_student

WHERE si.final_result = 'Fail'
  AND sr.date_unregistration IS NOT NULL;