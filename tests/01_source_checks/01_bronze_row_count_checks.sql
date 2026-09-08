-- Suggested branch: test/bronze-checks
-- For checks tied to one transformation, use that transformation's branch instead.

-- Confirms that every Bronze table contains the expected source rows.

SELECT
    'assessments_raw' AS table_name,
    COUNT(*) AS bronze_count,
    206 AS expected_count,
    COUNT(*) - 206 AS difference
FROM open_university.oulad_bronze.assessment_raw

UNION ALL

SELECT
    'courses_raw',
    COUNT(*),
    22,
    COUNT(*) - 22
FROM open_university.oulad_bronze.courses_raw

UNION ALL

SELECT
    'student_assessments_raw',
    COUNT(*),
    173912,
    COUNT(*) - 173912
FROM open_university.oulad_bronze.student_assessment_raw

UNION ALL

SELECT
    'student_info_raw',
    COUNT(*),
    32593,
    COUNT(*) - 32593
FROM open_university.oulad_bronze.student_info_raw

UNION ALL

SELECT
    'student_reg_raw',
    COUNT(*),
    32593,
    COUNT(*) - 32593
FROM open_university.oulad_bronze.student_registration_raw

UNION ALL

SELECT
    'student_vle_raw',
    COUNT(*),
    10655280,
    COUNT(*) - 10655280
FROM open_university.oulad_bronze.student_vle_raw

UNION ALL

SELECT
    'vle_raw',
    COUNT(*),
    6364,
    COUNT(*) - 6364
FROM open_university.oulad_bronze.vle_raw;
