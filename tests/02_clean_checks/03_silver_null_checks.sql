-- File: 03_silver_null_checks.sql
-- Suggested branch: feature/add-silver-checks
-- For checks tied to one transformation, use that transformation's branch instead.
-- Purpose: Separate valid missing optional values from unexpected missing data.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: All Silver tables, plus the documented source missing-value results.
-- Output: Read-only validation queries with failure counts/details and stated expected results; no data
--    changes.
--
-- What to put in this file:
-- 1. Check required keys, clean_load_timestamp and clean_load_date for NULL; compare typed values
--    against non-missing Bronze inputs to detect failed conversions.
-- 2. Report expected optional NULLs: 1,111 imd_band; 45 date_registration; 22,521 date_unregistration;
--    5,243 each week_from/week_to.
-- 3. Report 11 assessment dates missing only for Exam and 173 scores missing only for TMA.
-- 4. Join the proper assessment/enrollment context using full keys; do not fail a table merely because
--    these documented optional values are NULL.
--
-- Use this file for manual Databricks checks. A runner must explicitly fail on violations; a displayed
--    result alone is not an automated test.
--
-- Done when: No unexpected required NULLs or unexplained conversion losses; optional NULL counts match
--    the current-batch baseline.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.

-- ============================================================
-- 1. assessment_clean
-- Required fields:
-- id_assessment
-- code_module
-- code_presentation
-- assessment_type
-- clean_load_timestamp
-- clean_load_date
--
-- Expected optional NULL:
-- date = 11 NULLs, all for Exam assessments
-- ============================================================

SELECT
    COUNT(*) AS unexpected_null_count
FROM open_university.oulad_silver.assessment_clean
WHERE id_assessment IS NULL
   OR TRIM(code_module) IS NULL
   OR TRIM(code_module) = ''
   OR TRIM(code_presentation) IS NULL
   OR TRIM(code_presentation) = ''
   OR TRIM(assessment_type) IS NULL
   OR TRIM(assessment_type) = ''
   OR clean_load_timestamp IS NULL
   OR clean_load_date IS NULL;


-- Check the documented 11 missing assessment dates
-- Expected: 11 rows, all assessment_type = 'Exam'

SELECT
    assessment_type,
    COUNT(*) AS null_date_count
FROM open_university.oulad_silver.assessment_clean
WHERE date IS NULL
GROUP BY assessment_type
ORDER BY assessment_type;


-- ============================================================
-- 2. student_assessment_clean
-- Required fields:
-- id_assessment
-- id_student
-- clean_load_timestamp
-- clean_load_date
--
-- Expected optional NULL:
-- score = 173 NULLs, all for TMA assessments
-- ============================================================

SELECT
    COUNT(*) AS unexpected_null_count
FROM open_university.oulad_silver.student_assessment_clean
WHERE id_assessment IS NULL
   OR id_student IS NULL
   OR clean_load_timestamp IS NULL
   OR clean_load_date IS NULL;


-- Check the documented 173 missing scores
-- Expected: 173 rows, all assessment_type = 'TMA'

SELECT
    a.assessment_type,
    COUNT(*) AS null_score_count
FROM open_university.oulad_silver.student_assessment_clean sa
JOIN open_university.oulad_silver.assessment_clean a
    ON sa.id_assessment = a.id_assessment
WHERE sa.score IS NULL
GROUP BY a.assessment_type
ORDER BY a.assessment_type;


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

FROM (
    SELECT b.code_module, b.code_presentation, b.id_student
    FROM open_university.oulad_bronze.student_registration_raw AS b
    INNER JOIN open_university.oulad_silver.student_registration_clean AS s
        ON UPPER(TRIM(CAST(b.code_module AS STRING))) = s.code_module
       AND UPPER(TRIM(CAST(b.code_presentation AS STRING))) = s.code_presentation
       AND TRY_CAST(b.id_student AS BIGINT) = s.id_student
    WHERE (
        b.date_registration IS NOT NULL
        AND UPPER(TRIM(CAST(b.date_registration AS STRING))) NOT IN ('', '?', 'NA', 'N/A', 'NULL')
        AND TRY_CAST(b.date_registration AS INT) IS NOT NULL
        AND s.date_registration IS NULL
    )
    OR (
        b.date_unregistration IS NOT NULL
        AND UPPER(TRIM(CAST(b.date_unregistration AS STRING))) NOT IN ('', '?', 'NA', 'N/A', 'NULL')
        AND TRY_CAST(b.date_unregistration AS INT) IS NOT NULL
        AND s.date_unregistration IS NULL
    )
) AS registration_conversion_losses


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

-- VLE optional NULLs and audit fields
SELECT
  COUNT(*) AS resources_with_both_weeks_missing,
  CASE WHEN COUNT(*) = 5243 THEN 'PASS' ELSE 'REVIEW' END AS status
FROM open_university.oulad_silver.vle_clean
WHERE week_from IS NULL AND week_to IS NULL;

SELECT 'vle_clean_required_nulls' AS check_name, COUNT(*) AS invalid_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM open_university.oulad_silver.vle_clean
WHERE code_module IS NULL OR code_presentation IS NULL OR id_site IS NULL
   OR clean_load_timestamp IS NULL OR clean_load_date IS NULL;

SELECT 'student_vle_clean_required_nulls' AS check_name, COUNT(*) AS invalid_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM open_university.oulad_silver.student_vle_clean
WHERE code_module IS NULL OR code_presentation IS NULL OR id_student IS NULL
   OR id_site IS NULL OR date IS NULL OR sum_click IS NULL
   OR clean_load_timestamp IS NULL OR clean_load_date IS NULL;
