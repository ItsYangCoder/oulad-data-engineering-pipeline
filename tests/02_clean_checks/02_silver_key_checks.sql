-- File: 02_silver_key_checks.sql
-- Suggested branch: feature/add-silver-checks
-- For checks tied to one transformation, use that transformation's branch instead.
-- Purpose: Find missing or repeated Silver business keys.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: All seven Silver tables.
-- Output: Read-only validation queries with failure counts/details and stated expected results; no data
--    changes.
--
-- What to put in this file:
-- 1. Check assessment by id_assessment; courses by code_module + code_presentation.
-- 2. Check student_assessment by id_assessment + id_student; student_info and registration by
--    code_module + code_presentation + id_student.
-- 3. Check vle by code_module + code_presentation + id_site; student_vle by those codes plus id_student
--    + id_site + date.
-- 4. Test each key component for NULL/blank separately, then GROUP BY the full key and HAVING COUNT(*)
--    > 1.
--
-- Use this file for manual Databricks checks. A runner must explicitly fail on violations; a displayed
--    result alone is not an automated test.
--
-- Done when: No missing required key components and no repeated full business keys.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.












































































-- ========================================================================================================
-- File: tests/02_clean_checks/02_silver_key_checks.sql
-- Branch: feature/clean-students
--
-- Objective:
--    Verify business key completeness and uniqueness for the student enrollment
--    and registration Silver tables.
--
--    Ensures:
--      1. Every required business-key attribute is populated.
--      2. Blank string values are not accepted for text key attributes.
--      3. The complete enrollment business key is unique within each table.
--      4. id_student is not treated as a unique key by itself because the same
--         student may enroll in multiple module presentations.
--
-- Scope:
--    Silver transformations owned by Task #9:
--      - student_info_clean
--      - student_registration_clean
--
-- Business Keys:
--    student_info_clean:
--      (code_module, code_presentation, id_student)
--
--    student_registration_clean:
--      (code_module, code_presentation, id_student)
--
-- Expected Results:
--    For both tables:
--      - missing / blank code_module = 0
--      - missing / blank code_presentation = 0
--      - NULL id_student = 0
--      - duplicate complete business keys = 0
--
-- Output:
--    Read-only validation results showing the table, validation rule,
--    affected column or key, failure count, expected count, and PASS/FAIL status.
--
-- No data is inserted, updated, deleted, or otherwise modified by this file.
-- ========================================================================================================


-- ========================================================================================================
-- PREPARATION: IDENTIFY DUPLICATE COMPLETE BUSINESS KEYS
-- ========================================================================================================
--
-- Duplicate detection must use the complete enrollment key:
--
--    code_module + code_presentation + id_student
--
-- id_student alone is intentionally not used because one student may legitimately
-- appear in several module presentations.
--
-- Only key combinations occurring more than once are retained in these CTEs.
-- ========================================================================================================

WITH student_info_duplicate_keys AS (

    SELECT
        code_module,
        code_presentation,
        id_student,
        COUNT(*) AS record_count

    FROM open_university.oulad_silver.student_info_clean

    GROUP BY
        code_module,
        code_presentation,
        id_student

    HAVING COUNT(*) > 1

),

student_registration_duplicate_keys AS (

    SELECT
        code_module,
        code_presentation,
        id_student,
        COUNT(*) AS record_count

    FROM open_university.oulad_silver.student_registration_clean

    GROUP BY
        code_module,
        code_presentation,
        id_student

    HAVING COUNT(*) > 1

)


-- ========================================================================================================
-- CHECK 1: STUDENT INFO CLEAN - code_module COMPLETENESS
-- ========================================================================================================
--
-- code_module is a required component of the student enrollment business key.
-- NULL and blank values are treated as invalid.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_info_clean' AS table_name,
    'Key component' AS check_name,
    'code_module' AS column_or_key,

    COUNT_IF(
        code_module IS NULL
        OR TRIM(code_module) = ''
    ) AS failure_count,

    0 AS expected_count,

    CASE
        WHEN COUNT_IF(
            code_module IS NULL
            OR TRIM(code_module) = ''
        ) = 0
        THEN 'Pass'
        ELSE 'Fail'
    END AS status

FROM open_university.oulad_silver.student_info_clean


UNION ALL


-- ========================================================================================================
-- CHECK 2: STUDENT INFO CLEAN - code_presentation COMPLETENESS
-- ========================================================================================================
--
-- code_presentation is required because presentation codes provide the enrollment
-- context within a module.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_info_clean',
    'Key component',
    'code_presentation',

    COUNT_IF(
        code_presentation IS NULL
        OR TRIM(code_presentation) = ''
    ),

    0,

    CASE
        WHEN COUNT_IF(
            code_presentation IS NULL
            OR TRIM(code_presentation) = ''
        ) = 0
        THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean


UNION ALL


-- ========================================================================================================
-- CHECK 3: STUDENT INFO CLEAN - id_student COMPLETENESS
-- ========================================================================================================
--
-- Every enrollment must have a student identifier.
--
-- id_student is required but is not expected to be unique by itself.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_info_clean',
    'Key component',
    'id_student',

    COUNT_IF(id_student IS NULL),

    0,

    CASE
        WHEN COUNT_IF(id_student IS NULL) = 0
        THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean


UNION ALL


-- ========================================================================================================
-- CHECK 4: STUDENT INFO CLEAN - COMPLETE BUSINESS KEY UNIQUENESS
-- ========================================================================================================
--
-- The combination:
--
--    code_module + code_presentation + id_student
--
-- must identify exactly one enrollment record.
--
-- A repeated id_student is valid when the student appears in a different module
-- or presentation. Only repetition of the complete business key is considered
-- a duplicate enrollment.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_info_clean',
    'Full-key uniqueness',
    'code_module + code_presentation + id_student',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM student_info_duplicate_keys


UNION ALL


-- ========================================================================================================
-- CHECK 5: STUDENT REGISTRATION CLEAN - code_module COMPLETENESS
-- ========================================================================================================
--
-- code_module is a required component of the registration business key.
-- NULL and blank values are treated as invalid.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_registration_clean',
    'Key component',
    'code_module',

    COUNT_IF(
        code_module IS NULL
        OR TRIM(code_module) = ''
    ),

    0,

    CASE
        WHEN COUNT_IF(
            code_module IS NULL
            OR TRIM(code_module) = ''
        ) = 0
        THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean


UNION ALL


-- ========================================================================================================
-- CHECK 6: STUDENT REGISTRATION CLEAN - code_presentation COMPLETENESS
-- ========================================================================================================
--
-- code_presentation is required to identify the registration within the correct
-- module presentation.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_registration_clean',
    'Key component',
    'code_presentation',

    COUNT_IF(
        code_presentation IS NULL
        OR TRIM(code_presentation) = ''
    ),

    0,

    CASE
        WHEN COUNT_IF(
            code_presentation IS NULL
            OR TRIM(code_presentation) = ''
        ) = 0
        THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean


UNION ALL


-- ========================================================================================================
-- CHECK 7: STUDENT REGISTRATION CLEAN - id_student COMPLETENESS
-- ========================================================================================================
--
-- Every registration must contain a student identifier.
--
-- id_student remains part of the composite enrollment key and is not tested for
-- uniqueness by itself.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_registration_clean',
    'Key component',
    'id_student',

    COUNT_IF(id_student IS NULL),

    0,

    CASE
        WHEN COUNT_IF(id_student IS NULL) = 0
        THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean


UNION ALL


-- ========================================================================================================
-- CHECK 8: STUDENT REGISTRATION CLEAN - COMPLETE BUSINESS KEY UNIQUENESS
-- ========================================================================================================
--
-- The complete registration business key is:
--
--    code_module + code_presentation + id_student
--
-- Each complete key must occur exactly once in the Silver registration table.
--
-- Expected result:
--    failure_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_registration_clean',
    'Full-key uniqueness',
    'code_module + code_presentation + id_student',

    COUNT(*),

    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM student_registration_duplicate_keys


-- ========================================================================================================
-- FINAL OUTPUT ORDER
-- ========================================================================================================
--
-- Results are ordered by table, validation type, and affected column/key so that
-- the manual Databricks output is easy to review and capture as validation evidence.
-- ========================================================================================================

ORDER BY
    table_name,
    check_name,
    column_or_key;