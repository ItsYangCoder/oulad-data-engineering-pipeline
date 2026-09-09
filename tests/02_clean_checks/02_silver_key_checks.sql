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
