-- Silver validation: business key integrity
-- Scope: courses_clean + assessment_clean + student_assessment_clean

-- Courses: required composite key and uniqueness
SELECT 'courses_clean_null_keys' AS check_name, COUNT(*) AS invalid_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS check_status
FROM open_university.oulad_silver.courses_clean
WHERE code_module IS NULL OR code_presentation IS NULL;

SELECT 'courses_clean_duplicate_keys' AS check_name, COUNT(*) AS duplicate_keys,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS check_status
FROM (
    SELECT code_module, code_presentation
    FROM open_university.oulad_silver.courses_clean
    GROUP BY code_module, code_presentation
    HAVING COUNT(*) > 1
) duplicate_key_groups;

-- Assessment: id_assessment
SELECT COUNT(*) AS null_id_assessment_count
FROM open_university.oulad_silver.assessment_clean
WHERE id_assessment IS NULL;

SELECT id_assessment, COUNT(*) AS row_count
FROM open_university.oulad_silver.assessment_clean
GROUP BY id_assessment
HAVING COUNT(*) > 1
ORDER BY row_count DESC;

-- Student assessment: (id_assessment, id_student)
SELECT COUNT(*) AS null_id_assessment_count
FROM open_university.oulad_silver.student_assessment_clean
WHERE id_assessment IS NULL;

SELECT COUNT(*) AS null_id_student_count
FROM open_university.oulad_silver.student_assessment_clean
WHERE id_student IS NULL;

SELECT id_assessment, id_student, COUNT(*) AS row_count
FROM open_university.oulad_silver.student_assessment_clean
GROUP BY id_assessment, id_student
HAVING COUNT(*) > 1
ORDER BY row_count DESC;


-- ========================================================================================================
-- SECTION 2: STUDENT INFO AND STUDENT REGISTRATION KEY CHECKS
-- ========================================================================================================
--
-- The student tables use the complete enrollment business key:
--
--    code_module + code_presentation + id_student
--
-- id_student alone is intentionally not treated as unique.
-- ========================================================================================================



-- ========================================================================================================
-- PREPARATION: IDENTIFY DUPLICATE COMPLETE BUSINESS KEYS
-- ========================================================================================================
--
-- Duplicate detection must use the complete enrollment key:
--
--    code_module + code_presentation + id_student
--
-- Only business-key combinations occurring more than once are retained in these CTEs.
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

-- VLE business keys
SELECT 'vle_clean_null_keys' AS check_name, COUNT(*) AS invalid_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM open_university.oulad_silver.vle_clean
WHERE code_module IS NULL OR code_presentation IS NULL OR id_site IS NULL;

SELECT 'vle_clean_duplicate_keys' AS check_name, COUNT(*) AS duplicate_keys,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
  SELECT code_module, code_presentation, id_site
  FROM open_university.oulad_silver.vle_clean
  GROUP BY code_module, code_presentation, id_site
  HAVING COUNT(*) > 1
);

SELECT 'student_vle_clean_null_keys' AS check_name, COUNT(*) AS invalid_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM open_university.oulad_silver.student_vle_clean
WHERE code_module IS NULL OR code_presentation IS NULL OR id_student IS NULL
   OR id_site IS NULL OR date IS NULL;

SELECT 'student_vle_clean_duplicate_keys' AS check_name, COUNT(*) AS duplicate_keys,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
  SELECT code_module, code_presentation, id_student, id_site, date
  FROM open_university.oulad_silver.student_vle_clean
  GROUP BY code_module, code_presentation, id_student, id_site, date
  HAVING COUNT(*) > 1
);
