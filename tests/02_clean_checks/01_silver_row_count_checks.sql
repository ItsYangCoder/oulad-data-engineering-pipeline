-- ========================================================================================================
-- File: tests/02_clean_checks/01_silver_row_count_checks.sql
-- Branch: feature/clean-courses
-- Purpose: Explain every Bronze-to-Silver row-count difference across all dataset tables.
-- Input: All seven Bronze and matching Silver tables.
-- Output: Read-only validation queries with failure counts/details and stated expected results; no data changes.
-- Grain / business key: One validation record per table pair.
-- NOTE: Temporarily scoped to 'courses' only — assessments_clean, student_assessment_clean,
--       student_info_clean, student_registration_clean, vle_clean, and student_vle_clean
--       do not exist yet under oulad_silver. Uncomment the other UNION ALL blocks below in
--       each CTE once teammates merge those Silver tables.
-- ========================================================================================================
WITH bronze_counts AS (
  SELECT 'courses' AS table_name, COUNT(*) AS bronze_count FROM open_university.oulad_bronze.courses_raw
  -- UNION ALL SELECT 'assessments' AS table_name, COUNT(*) AS bronze_count FROM open_university.oulad_bronze.assessment_raw
  -- UNION ALL SELECT 'student_assessment' AS table_name, COUNT(*) AS bronze_count FROM open_university.oulad_bronze.student_assessment_raw
  -- UNION ALL SELECT 'student_info' AS table_name, COUNT(*) AS bronze_count FROM open_university.oulad_bronze.student_info_raw
  -- UNION ALL SELECT 'student_registration' AS table_name, COUNT(*) AS bronze_count FROM open_university.oulad_bronze.student_registration_raw
  -- UNION ALL SELECT 'vle' AS table_name, COUNT(*) AS bronze_count FROM open_university.oulad_bronze.vle_raw
  -- UNION ALL SELECT 'student_vle' AS table_name, COUNT(*) AS bronze_count FROM open_university.oulad_bronze.student_vle_raw
),
silver_counts AS (
  SELECT 'courses' AS table_name, COUNT(*) AS silver_count FROM open_university.oulad_silver.courses_clean
  -- UNION ALL SELECT 'assessments' AS table_name, COUNT(*) AS silver_count FROM open_university.oulad_silver.assessments_clean
  -- UNION ALL SELECT 'student_assessment' AS table_name, COUNT(*) AS silver_count FROM open_university.oulad_silver.student_assessment_clean
  -- UNION ALL SELECT 'student_info' AS table_name, COUNT(*) AS silver_count FROM open_university.oulad_silver.student_info_clean
  -- UNION ALL SELECT 'student_registration' AS table_name, COUNT(*) AS silver_count FROM open_university.oulad_silver.student_registration_clean
  -- UNION ALL SELECT 'vle' AS table_name, COUNT(*) AS silver_count FROM open_university.oulad_silver.vle_clean
  -- UNION ALL SELECT 'student_vle' AS table_name, COUNT(*) AS silver_count FROM open_university.oulad_silver.student_vle_clean
),
baselines AS (
  SELECT 'courses' AS table_name, 22 AS expected_count
  -- UNION ALL SELECT 'assessments' AS table_name, 206 AS expected_count
  -- UNION ALL SELECT 'student_assessment' AS table_name, 173912 AS expected_count
  -- UNION ALL SELECT 'student_info' AS table_name, 32593 AS expected_count
  -- UNION ALL SELECT 'student_registration' AS table_name, 32593 AS expected_count
  -- UNION ALL SELECT 'vle' AS table_name, 6364 AS expected_count
  -- Note: student_vle expected to change from 10,655,280 source rows to 8,459,320 complete daily keys after aggregation
  -- UNION ALL SELECT 'student_vle' AS table_name, 8459320 AS expected_count
)
SELECT
  b.table_name,
  b.bronze_count,
  s.silver_count,
  e.expected_count,
  (s.silver_count - b.bronze_count) AS difference,
  CASE 
    WHEN s.silver_count = e.expected_count THEN 'PASSED'
    ELSE 'FAILED'
  END AS status
FROM bronze_counts b
JOIN silver_counts s ON b.table_name = s.table_name
JOIN baselines e     ON b.table_name = e.table_name
ORDER BY b.table_name;