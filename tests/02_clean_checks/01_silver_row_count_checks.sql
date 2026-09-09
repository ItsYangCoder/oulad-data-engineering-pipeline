-- Silver validation: row counts
-- Scope: courses_clean + assessment_clean + student_assessment_clean

-- ============================================================
-- COURSES CLEAN
-- ============================================================
WITH raw_counts AS (
    SELECT COUNT(*) AS raw_count FROM open_university.oulad_bronze.courses_raw
), clean_counts AS (
    SELECT COUNT(*) AS clean_count FROM open_university.oulad_silver.courses_clean
), quarantine_counts AS (
    SELECT COALESCE(SUM(source_row_count), 0) AS quarantine_count
    FROM open_university.oulad_silver.courses_invalid_key_quarantine
)
SELECT
    'courses' AS entity_name,
    raw.raw_count,
    clean.clean_count,
    quarantine.quarantine_count,
    clean.clean_count + quarantine.quarantine_count AS accounted_count,
    raw.raw_count - (clean.clean_count + quarantine.quarantine_count) AS leakage_count,
    CASE WHEN raw.raw_count - (clean.clean_count + quarantine.quarantine_count) = 0 THEN 'PASS' ELSE 'FAIL' END AS check_status
FROM raw_counts raw
CROSS JOIN clean_counts clean
CROSS JOIN quarantine_counts quarantine;

-- ============================================================
-- ASSESSMENT + STUDENT ASSESSMENT
-- ============================================================
WITH row_counts AS (
    SELECT 'assessment_clean' AS table_name,
           (SELECT COUNT(*) FROM open_university.oulad_bronze.assessment_raw) AS bronze_count,
           (SELECT COUNT(*) FROM open_university.oulad_silver.assessment_clean) AS silver_count,
           206 AS expected_count
    UNION ALL
    SELECT 'student_assessment_clean',
           (SELECT COUNT(*) FROM open_university.oulad_bronze.student_assessment_raw),
           (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean),
           173912
)
SELECT table_name, bronze_count, silver_count, expected_count,
       silver_count - bronze_count AS difference,
       CASE
           WHEN silver_count = expected_count AND silver_count = bronze_count THEN 'PASS'
           WHEN silver_count = expected_count AND silver_count <> bronze_count THEN 'REVIEW - documented transformation difference'
           ELSE 'FAIL'
       END AS status
FROM row_counts
ORDER BY table_name;
