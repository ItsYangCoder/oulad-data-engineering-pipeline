-- ========================================================================================================
-- File: tests/02_clean_checks/02_silver_key_checks.sql
-- Branch: feature/clean-courses
-- Purpose: Find missing or repeated Silver business keys across all dataset tables.
-- Input: All seven Silver tables.
-- Output: Read-only validation queries with failure counts/details and stated expected results; no data changes.
-- Grain / business key: One validation summary record per table check.
-- NOTE: Temporarily scoped to 'courses' only. Spark/Databricks resolves every table reference in the
--       query plan at analysis time, so IF(EXISTS(...), ..., NULL) does NOT prevent TABLE_OR_VIEW_NOT_FOUND
--       for tables that don't exist yet — the block referencing a missing table must be commented out
--       entirely, not just guarded. Uncomment each table's block below once its Silver table is merged.
-- ========================================================================================================

-- Utility view/CTE to identify existing Silver tables in the workspace schema
WITH silver_tables AS (
  SELECT table_name 
  FROM open_university.information_schema.tables 
  WHERE table_schema = 'oulad_silver'
),

-- ========================================================================================================
-- SECTION 1: KEY COMPLETENESS CHECKS (Test each key component for NULL or blank values separately)
-- ========================================================================================================
completeness_checks AS (

  -- 2. courses (Keys: code_module, code_presentation)
  SELECT 
    'courses' AS table_name,
    'code_module' AS key_component,
    IF(
      EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'courses_clean'),
      (SELECT COUNT(*) FROM open_university.oulad_silver.courses_clean WHERE code_module IS NULL OR TRIM(code_module) IN ('', '?', 'NA', 'N/A', 'NULL')),
      NULL
    ) AS null_or_blank_count UNION ALL
  SELECT 
    'courses' AS table_name,
    'code_presentation' AS key_component,
    IF(
      EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'courses_clean'),
      (SELECT COUNT(*) FROM open_university.oulad_silver.courses_clean WHERE code_presentation IS NULL OR TRIM(code_presentation) IN ('', '?', 'NA', 'N/A', 'NULL')),
      NULL
    ) AS null_or_blank_count

  -- 1. assessments (Key: id_assessment) — UNCOMMENT once open_university.oulad_silver.assessments_clean exists
  -- UNION ALL
  -- SELECT 
  --   'assessments' AS table_name,
  --   'id_assessment' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'assessments_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.assessments_clean WHERE id_assessment IS NULL OR TRIM(CAST(id_assessment AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count

  -- 3. student_assessment (Keys: id_assessment, id_student) — UNCOMMENT once student_assessment_clean exists
  -- UNION ALL
  -- SELECT 
  --   'student_assessment' AS table_name,
  --   'id_assessment' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_assessment_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean WHERE id_assessment IS NULL OR TRIM(CAST(id_assessment AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count
  -- UNION ALL
  -- SELECT 
  --   'student_assessment' AS table_name,
  --   'id_student' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_assessment_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_assessment_clean WHERE id_student IS NULL OR TRIM(CAST(id_student AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count

  -- 4. student_info (Keys: code_module, code_presentation, id_student) — UNCOMMENT once student_info_clean exists
  -- UNION ALL
  -- SELECT 
  --   'student_info' AS table_name,
  --   'code_module' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_info_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_info_clean WHERE code_module IS NULL OR TRIM(code_module) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count
  -- UNION ALL
  -- SELECT 
  --   'student_info' AS table_name,
  --   'code_presentation' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_info_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_info_clean WHERE code_presentation IS NULL OR TRIM(code_presentation) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count
  -- UNION ALL
  -- SELECT 
  --   'student_info' AS table_name,
  --   'id_student' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_info_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_info_clean WHERE id_student IS NULL OR TRIM(CAST(id_student AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count

  -- 5. student_registration (Keys: code_module, code_presentation, id_student) — UNCOMMENT once student_registration_clean exists
  -- UNION ALL
  -- SELECT 
  --   'student_registration' AS table_name,
  --   'code_module' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_registration_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_registration_clean WHERE code_module IS NULL OR TRIM(code_module) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count
  -- UNION ALL
  -- SELECT 
  --   'student_registration' AS table_name,
  --   'code_presentation' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_registration_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_registration_clean WHERE code_presentation IS NULL OR TRIM(code_presentation) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count
  -- UNION ALL
  -- SELECT 
  --   'student_registration' AS table_name,
  --   'id_student' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_registration_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_registration_clean WHERE id_student IS NULL OR TRIM(CAST(id_student AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count

  -- 6. vle (Keys: code_module, code_presentation, id_site) — UNCOMMENT once vle_clean exists
  -- UNION ALL
  -- SELECT 
  --   'vle' AS table_name,
  --   'code_module' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'vle_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.vle_clean WHERE code_module IS NULL OR TRIM(code_module) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count
  -- UNION ALL
  -- SELECT 
  --   'vle' AS table_name,
  --   'code_presentation' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'vle_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.vle_clean WHERE code_presentation IS NULL OR TRIM(code_presentation) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count
  -- UNION ALL
  -- SELECT 
  --   'vle' AS table_name,
  --   'id_site' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'vle_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.vle_clean WHERE id_site IS NULL OR TRIM(CAST(id_site AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count

  -- 7. student_vle (Keys: code_module, code_presentation, id_student, id_site, date) — UNCOMMENT once student_vle_clean exists
  -- UNION ALL
  -- SELECT 
  --   'student_vle' AS table_name,
  --   'code_module' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_vle_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean WHERE code_module IS NULL OR TRIM(code_module) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count
  -- UNION ALL
  -- SELECT 
  --   'student_vle' AS table_name,
  --   'code_presentation' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_vle_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean WHERE code_presentation IS NULL OR TRIM(code_presentation) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count
  -- UNION ALL
  -- SELECT 
  --   'student_vle' AS table_name,
  --   'id_student' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_vle_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean WHERE id_student IS NULL OR TRIM(CAST(id_student AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count
  -- UNION ALL
  -- SELECT 
  --   'student_vle' AS table_name,
  --   'id_site' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_vle_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean WHERE id_site IS NULL OR TRIM(CAST(id_site AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count
  -- UNION ALL
  -- SELECT 
  --   'student_vle' AS table_name,
  --   'date' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_vle_clean'),
  --     (SELECT COUNT(*) FROM open_university.oulad_silver.student_vle_clean WHERE date IS NULL OR TRIM(CAST(date AS STRING)) IN ('', '?', 'NA', 'N/A', 'NULL')),
  --     NULL
  --   ) AS null_or_blank_count
),

-- ========================================================================================================
-- SECTION 2: KEY UNIQUENESS CHECKS (GROUP BY full business key HAVING COUNT(*) > 1)
-- ========================================================================================================
uniqueness_checks AS (

  -- 2. courses (code_module, code_presentation)
  SELECT 
    'courses' AS table_name,
    'FULL_BUSINESS_KEY' AS key_component,
    IF(
      EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'courses_clean'),
      (SELECT COUNT(*) FROM (SELECT code_module, code_presentation FROM open_university.oulad_silver.courses_clean GROUP BY code_module, code_presentation HAVING COUNT(*) > 1)),
      NULL
    ) AS duplicate_key_groups

  -- 1. assessments (id_assessment) — UNCOMMENT once assessments_clean exists
  -- UNION ALL
  -- SELECT 
  --   'assessments' AS table_name,
  --   'FULL_BUSINESS_KEY' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'assessments_clean'),
  --     (SELECT COUNT(*) FROM (SELECT id_assessment FROM open_university.oulad_silver.assessments_clean GROUP BY id_assessment HAVING COUNT(*) > 1)),
  --     NULL
  --   ) AS duplicate_key_groups

  -- 3. student_assessment (id_assessment, id_student) — UNCOMMENT once student_assessment_clean exists
  -- UNION ALL
  -- SELECT 
  --   'student_assessment' AS table_name,
  --   'FULL_BUSINESS_KEY' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_assessment_clean'),
  --     (SELECT COUNT(*) FROM (SELECT id_assessment, id_student FROM open_university.oulad_silver.student_assessment_clean GROUP BY id_assessment, id_student HAVING COUNT(*) > 1)),
  --     NULL
  --   ) AS duplicate_key_groups

  -- 4. student_info (code_module, code_presentation, id_student) — UNCOMMENT once student_info_clean exists
  -- UNION ALL
  -- SELECT 
  --   'student_info' AS table_name,
  --   'FULL_BUSINESS_KEY' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_info_clean'),
  --     (SELECT COUNT(*) FROM (SELECT code_module, code_presentation, id_student FROM open_university.oulad_silver.student_info_clean GROUP BY code_module, code_presentation, id_student HAVING COUNT(*) > 1)),
  --     NULL
  --   ) AS duplicate_key_groups

  -- 5. student_registration (code_module, code_presentation, id_student) — UNCOMMENT once student_registration_clean exists
  -- UNION ALL
  -- SELECT 
  --   'student_registration' AS table_name,
  --   'FULL_BUSINESS_KEY' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_registration_clean'),
  --     (SELECT COUNT(*) FROM (SELECT code_module, code_presentation, id_student FROM open_university.oulad_silver.student_registration_clean GROUP BY code_module, code_presentation, id_student HAVING COUNT(*) > 1)),
  --     NULL
  --   ) AS duplicate_key_groups

  -- 6. vle (code_module, code_presentation, id_site) — UNCOMMENT once vle_clean exists
  -- UNION ALL
  -- SELECT 
  --   'vle' AS table_name,
  --   'FULL_BUSINESS_KEY' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'vle_clean'),
  --     (SELECT COUNT(*) FROM (SELECT code_module, code_presentation, id_site FROM open_university.oulad_silver.vle_clean GROUP BY code_module, code_presentation, id_site HAVING COUNT(*) > 1)),
  --     NULL
  --   ) AS duplicate_key_groups

  -- 7. student_vle (code_module, code_presentation, id_student, id_site, date) — UNCOMMENT once student_vle_clean exists
  -- UNION ALL
  -- SELECT 
  --   'student_vle' AS table_name,
  --   'FULL_BUSINESS_KEY' AS key_component,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_vle_clean'),
  --     (SELECT COUNT(*) FROM (SELECT code_module, code_presentation, id_student, id_site, date FROM open_university.oulad_silver.student_vle_clean GROUP BY code_module, code_presentation, id_student, id_site, date HAVING COUNT(*) > 1)),
  --     NULL
  --   ) AS duplicate_key_groups
)

-- Combined final output summarizing completeness & uniqueness assertions
SELECT 
  'COMPLETENESS_CHECK' AS check_type,
  table_name,
  key_component,
  COALESCE(null_or_blank_count, 0) AS invalid_record_count,
  0 AS expected_invalid_count,
  CASE 
    WHEN null_or_blank_count IS NULL THEN 'UNBUILT_TABLE'
    WHEN null_or_blank_count = 0 THEN 'PASSED'
    ELSE 'FAILED'
  END AS status
FROM completeness_checks

UNION ALL

SELECT 
  'UNIQUENESS_CHECK' AS check_type,
  table_name,
  key_component,
  COALESCE(duplicate_key_groups, 0) AS invalid_record_count,
  0 AS expected_invalid_count,
  CASE 
    WHEN duplicate_key_groups IS NULL THEN 'UNBUILT_TABLE'
    WHEN duplicate_key_groups = 0 THEN 'PASSED'
    ELSE 'FAILED'
  END AS status
FROM uniqueness_checks
ORDER BY check_type, table_name, key_component;