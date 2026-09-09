-- Final Silver row-count gate
-- Fixed expectations apply to the current OULAD source batch.

WITH counts AS (
  SELECT 'courses_clean' AS table_name,
         (SELECT COUNT(*) FROM open_university.oulad_bronze.courses_raw) AS bronze_rows,
         (SELECT COUNT(*) FROM open_university.oulad_silver.courses_clean) AS silver_rows,
         22 AS expected_bronze_rows,
         22 AS expected_silver_rows
  UNION ALL
  SELECT 'assessment_clean',
         (SELECT COUNT(*) FROM open_university.oulad_bronze.assessment_raw),
         (SELECT COUNT(*) FROM open_university.oulad_silver.assessment_clean),
         206, 206
  UNION ALL
  SELECT 'student_assessment_clean',
         (SELECT COUNT(*) FROM open_university.oulad_bronze.student_assessment_raw),
         (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean),
         173912, 173912
  UNION ALL
  SELECT 'student_info_clean',
         (SELECT COUNT(*) FROM open_university.oulad_bronze.student_info_raw),
         (SELECT COUNT(*) FROM open_university.oulad_silver.student_info_clean),
         32593, 32593
  UNION ALL
  SELECT 'student_registration_clean',
         (SELECT COUNT(*) FROM open_university.oulad_bronze.student_registration_raw),
         (SELECT COUNT(*) FROM open_university.oulad_silver.student_registration_clean),
         32593, 32593
  UNION ALL
  SELECT 'vle_clean',
         (SELECT COUNT(*) FROM open_university.oulad_bronze.vle_raw),
         (SELECT COUNT(*) FROM open_university.oulad_silver.vle_clean),
         6364, 6364
  UNION ALL
  SELECT 'student_vle_clean',
         (SELECT COUNT(*) FROM open_university.oulad_bronze.student_vle_raw),
         (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean),
         10655280, 8459320
)
SELECT
  table_name,
  bronze_rows,
  silver_rows,
  expected_bronze_rows,
  expected_silver_rows,
  CASE
    WHEN bronze_rows = expected_bronze_rows
     AND silver_rows = expected_silver_rows
    THEN 'PASS' ELSE 'FAIL'
  END AS status
FROM counts
ORDER BY table_name;
