
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

SELECT COUNT(*) AS null_id_assessment_count
FROM open_university.oulad_silver.assessment_clean
WHERE id_assessment IS NULL;

SELECT id_assessment, COUNT(*) AS row_count
FROM open_university.oulad_silver.assessment_clean
GROUP BY id_assessment
HAVING COUNT(*) > 1
ORDER BY row_count DESC;

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

ORDER BY
    table_name,
    check_name,
    column_or_key;

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
-- Checks required Silver business keys and duplicate key groups.
-- Expected result: zero invalid or duplicate keys.
