-- ========================================================================================================
-- File: tests/02_clean_checks/04_silver_value_checks.sql
-- Branch: feature/clean-courses
-- Purpose: Find invalid types, unconverted placeholders, and out-of-range values across Silver tables.
-- Input: All seven Silver tables and column metadata.
-- Output: Read-only validation queries with failure counts/details and stated expected results; no data changes.
-- Grain / business key: One validation summary record per table check assertion.
-- ========================================================================================================

WITH silver_tables AS (
  SELECT table_name 
  FROM open_university.information_schema.tables 
  WHERE table_schema = 'oulad_silver'
),

-- ========================================================================================================
-- SECTION 1: PLACEHOLDER NORMALIZATION CHECKS
-- Verify raw placeholder strings (?, blank, NA, N/A, text NULL) were converted to SQL NULL or clean values
-- ========================================================================================================
placeholder_checks AS (

  -- 2. courses_clean
  SELECT 
    'courses' AS table_name,
    'placeholder_normalization' AS check_name,
    IF(
      EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'courses_clean'),
      (
        SELECT COUNT(*) 
        FROM open_university.oulad_silver.courses_clean 
        WHERE TRIM(CAST(code_module AS STRING)) IN ('?', '', 'NA', 'N/A', 'NULL')
           OR TRIM(CAST(code_presentation AS STRING)) IN ('?', '', 'NA', 'N/A', 'NULL')
           OR TRIM(CAST(module_presentation_length AS STRING)) IN ('?', '', 'NA', 'N/A', 'NULL')
      ),
      NULL
    ) AS invalid_count

  -- 1. assessments_clean
  -- UNION ALL
  -- SELECT 
  --   'assessments' AS table_name,
  --   'placeholder_normalization' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'assessments_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.assessments_clean 
  --       WHERE TRIM(CAST(assessment_type AS STRING)) IN ('?', '', 'NA', 'N/A', 'NULL')
  --          OR TRIM(CAST(weight AS STRING)) IN ('?', '', 'NA', 'N/A', 'NULL')
  --     ),
  --     NULL
  --   ) AS invalid_count

  -- 3. student_assessment_clean
  -- UNION ALL
  -- SELECT 
  --   'student_assessment' AS table_name,
  --   'placeholder_normalization' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_assessment_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.student_assessment_clean 
  --       WHERE TRIM(CAST(score AS STRING)) IN ('?', '', 'NA', 'N/A', 'NULL')
  --          OR TRIM(CAST(is_banked AS STRING)) IN ('?', '', 'NA', 'N/A', 'NULL')
  --     ),
  --     NULL
  --   ) AS invalid_count

  -- 4. student_info_clean
  -- UNION ALL
  -- SELECT 
  --   'student_info' AS table_name,
  --   'placeholder_normalization' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_info_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.student_info_clean 
  --       WHERE TRIM(CAST(final_result AS STRING)) IN ('?', '', 'NA', 'N/A', 'NULL')
  --          OR TRIM(CAST(studied_credits AS STRING)) IN ('?', '', 'NA', 'N/A', 'NULL')
  --     ),
  --     NULL
  --   ) AS invalid_count

  -- 5. student_registration_clean
  -- UNION ALL
  -- SELECT 
  --   'student_registration' AS table_name,
  --   'placeholder_normalization' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_registration_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.student_registration_clean 
  --       WHERE TRIM(CAST(date_registration AS STRING)) IN ('?', '', 'NA', 'N/A', 'NULL')
  --     ),
  --     NULL
  --   ) AS invalid_count

  -- 6. vle_clean
  -- UNION ALL
  -- SELECT 
  --   'vle' AS table_name,
  --   'placeholder_normalization' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'vle_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.vle_clean 
  --       WHERE TRIM(CAST(activity_type AS STRING)) IN ('?', '', 'NA', 'N/A', 'NULL')
  --     ),
  --     NULL
  --   ) AS invalid_count

  -- 7. student_vle_clean
  -- UNION ALL
  -- SELECT 
  --   'student_vle' AS table_name,
  --   'placeholder_normalization' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_vle_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.student_vle_clean 
  --       WHERE TRIM(CAST(sum_click AS STRING)) IN ('?', '', 'NA', 'N/A', 'NULL')
  --     ),
  --     NULL
  --   ) AS invalid_count
),

-- ========================================================================================================
-- SECTION 2: NUMERIC RANGE AND BOUNDARY CHECKS
-- Verify positive lengths, non-negative clicks/credits/attempts, score ranges (0..100), and binary flags
-- ========================================================================================================
range_checks AS (

  -- 1. courses_clean: module_presentation_length > 0
  SELECT 
    'courses' AS table_name,
    'positive_presentation_length' AS check_name,
    IF(
      EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'courses_clean'),
      (
        SELECT COUNT(*) 
        FROM open_university.oulad_silver.courses_clean 
        WHERE module_presentation_length IS NULL OR module_presentation_length <= 0
      ),
      NULL
    ) AS invalid_count

  -- 2. assessments_clean: weight between 0 and 100
  -- UNION ALL
  -- SELECT 
  --   'assessments' AS table_name,
  --   'weight_range_0_100' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'assessments_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.assessments_clean 
  --       WHERE weight IS NOT NULL AND (weight < 0 OR weight > 100)
  --     ),
  --     NULL
  --   ) AS invalid_count

  -- 3. student_assessment_clean: score between 0 and 100 when present
  -- UNION ALL
  -- SELECT 
  --   'student_assessment' AS table_name,
  --   'score_range_0_100' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_assessment_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.student_assessment_clean 
  --       WHERE score IS NOT NULL AND (score < 0 OR score > 100)
  --     ),
  --     NULL
  --   ) AS invalid_count

  -- 4. student_assessment_clean: is_banked in (0, 1)
  -- UNION ALL
  -- SELECT 
  --   'student_assessment' AS table_name,
  --   'is_banked_binary_flag' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_assessment_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.student_assessment_clean 
  --       WHERE is_banked IS NOT NULL AND is_banked NOT IN (0, 1)
  --     ),
  --     NULL
  --   ) AS invalid_count

  -- 5. student_info_clean: studied_credits >= 0
  -- UNION ALL
  -- SELECT 
  --   'student_info' AS table_name,
  --   'nonnegative_credits' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_info_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.student_info_clean 
  --       WHERE studied_credits IS NOT NULL AND studied_credits < 0
  --     ),
  --     NULL
  --   ) AS invalid_count

  -- 6. student_info_clean: num_of_prev_attempts >= 0
  -- UNION ALL
  -- SELECT 
  --   'student_info' AS table_name,
  --   'nonnegative_attempts' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_info_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.student_info_clean 
  --       WHERE num_of_prev_attempts IS NOT NULL AND num_of_prev_attempts < 0
  --     ),
  --     NULL
  --   ) AS invalid_count

  -- 7. student_vle_clean: sum_click >= 0
  -- UNION ALL
  -- SELECT 
  --   'student_vle' AS table_name,
  --   'nonnegative_clicks' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_vle_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.student_vle_clean 
  --       WHERE sum_click IS NOT NULL AND sum_click < 0
  --     ),
  --     NULL
  --   ) AS invalid_count
),

-- ========================================================================================================
-- SECTION 3: CATEGORICAL DOMAIN AND LOGICAL RELATIONSHIP CHECKS
-- Verify valid domain values (CMA/TMA/Exam, Distinction/Fail/Pass/Withdrawn) and week ordering logic
-- ========================================================================================================
domain_and_logic_checks AS (

  -- 1. assessments_clean: assessment_type IN ('CMA', 'TMA', 'Exam')
  -- SELECT 
  --   'assessments' AS table_name,
  --   'valid_assessment_type_domain' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'assessments_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.assessments_clean 
  --       WHERE assessment_type IS NOT NULL AND UPPER(TRIM(assessment_type)) NOT IN ('CMA', 'TMA', 'EXAM')
  --     ),
  --     NULL
  --   ) AS invalid_count

  -- 2. student_info_clean: final_result IN ('Distinction', 'Fail', 'Pass', 'Withdrawn')
  -- UNION ALL
  -- SELECT 
  --   'student_info' AS table_name,
  --   'valid_final_result_domain' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'student_info_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.student_info_clean 
  --       WHERE final_result IS NOT NULL AND INITCAP(TRIM(final_result)) NOT IN ('Distinction', 'Fail', 'Pass', 'Withdrawn')
  --     ),
  --     NULL
  --   ) AS invalid_count

  -- 3. vle_clean: week_from <= week_to ONLY when both exist (allowing NULLs)
  -- UNION ALL
  -- SELECT 
  --   'vle' AS table_name,
  --   'valid_week_from_to_ordering' AS check_name,
  --   IF(
  --     EXISTS(SELECT 1 FROM silver_tables WHERE table_name = 'vle_clean'),
  --     (
  --       SELECT COUNT(*) 
  --       FROM open_university.oulad_silver.vle_clean 
  --       WHERE week_from IS NOT NULL 
  --         AND week_to IS NOT NULL 
  --         AND week_from > week_to
  --     ),
  --     NULL
  --   ) AS invalid_count

  SELECT 'placeholder' AS table_name, 'placeholder' AS check_name, CAST(NULL AS BIGINT) AS invalid_count WHERE FALSE
)

-- Combined final output summarizing all value level validations
SELECT 
  table_name,
  check_name,
  COALESCE(invalid_count, 0) AS invalid_record_count,
  0 AS expected_invalid_count,
  CASE 
    WHEN invalid_count IS NULL THEN 'UNBUILT_TABLE'
    WHEN invalid_count = 0 THEN 'PASSED'
    ELSE 'FAILED'
  END AS status
FROM (
  SELECT * FROM placeholder_checks
  UNION ALL
  SELECT * FROM range_checks
  UNION ALL
  SELECT * FROM domain_and_logic_checks
)
ORDER BY table_name, check_name;