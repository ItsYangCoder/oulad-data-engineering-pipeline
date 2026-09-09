-- Silver validation: value/domain checks
-- Scope: courses_clean + assessment_clean + student_assessment_clean

-- Courses length validity
SELECT 'courses_clean_invalid_length_values' AS check_name, COUNT(*) AS invalid_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS check_status
FROM open_university.oulad_silver.courses_clean
WHERE module_presentation_length IS NOT NULL AND module_presentation_length <= 0;

SELECT 'courses_clean_flag_accuracy' AS check_name, COUNT(*) AS mismatch_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS check_status
FROM open_university.oulad_silver.courses_clean
WHERE (is_valid_length = TRUE AND (module_presentation_length IS NULL OR module_presentation_length <= 0))
   OR (is_valid_length = FALSE AND module_presentation_length IS NOT NULL AND module_presentation_length > 0);

SELECT 'courses_clean_is_valid_key_check' AS check_name, COUNT(*) AS invalid_key_flag_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS check_status
FROM open_university.oulad_silver.courses_clean
WHERE is_valid_key = FALSE;

-- Assessment categories and ranges
SELECT assessment_type, COUNT(*) AS row_count
FROM open_university.oulad_silver.assessment_clean
GROUP BY assessment_type
ORDER BY assessment_type;

SELECT DISTINCT assessment_type
FROM open_university.oulad_silver.assessment_clean
WHERE assessment_type NOT IN ('TMA', 'CMA', 'Exam') OR assessment_type IS NULL;

SELECT id_assessment, weight
FROM open_university.oulad_silver.assessment_clean
WHERE weight IS NOT NULL AND (weight < 0 OR weight > 100);

SELECT *
FROM open_university.oulad_silver.assessment_clean
WHERE TRIM(code_module) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR TRIM(code_presentation) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR TRIM(assessment_type) IN ('?', '', 'NA', 'N/A', 'NULL');

-- Student assessment ranges and placeholders
SELECT id_assessment, id_student, score
FROM open_university.oulad_silver.student_assessment_clean
WHERE score IS NOT NULL AND (score < 0 OR score > 100);

SELECT DISTINCT is_banked
FROM open_university.oulad_silver.student_assessment_clean
WHERE is_banked IS NOT NULL AND is_banked NOT IN (0, 1);

SELECT *
FROM open_university.oulad_silver.student_assessment_clean
WHERE CAST(id_assessment AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR CAST(id_student AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR CAST(date_submitted AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR CAST(is_banked AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL')
   OR CAST(score AS STRING) IN ('?', '', 'NA', 'N/A', 'NULL');
