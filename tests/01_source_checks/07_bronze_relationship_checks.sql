-- Suggested branch: test/bronze-checks
-- For checks tied to one transformation, use that transformation's branch instead.

-- Checks whether child records have matching parent records.

SELECT
    'student_assessment → assessment' AS relationship,
    COUNT(*) AS orphan_rows,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'REVIEW' END AS status
FROM open_university.oulad_bronze.student_assessment_raw s
LEFT JOIN open_university.oulad_bronze.assessment_raw a
    ON s.id_assessment = a.id_assessment
WHERE a.id_assessment IS NULL

UNION ALL

SELECT
    'student_info → courses',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'REVIEW' END
FROM open_university.oulad_bronze.student_info_raw s
LEFT JOIN open_university.oulad_bronze.courses_raw c
    ON s.code_module = c.code_module
   AND s.code_presentation = c.code_presentation
WHERE c.code_module IS NULL

UNION ALL

SELECT
    'student_registration → student_info',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'REVIEW' END
FROM open_university.oulad_bronze.student_registration_raw r
LEFT JOIN open_university.oulad_bronze.student_info_raw s
    ON r.code_module = s.code_module
   AND r.code_presentation = s.code_presentation
   AND r.id_student = s.id_student
WHERE s.id_student IS NULL

UNION ALL

SELECT
    'vle → courses',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'REVIEW' END
FROM open_university.oulad_bronze.vle_raw v
LEFT JOIN open_university.oulad_bronze.courses_raw c
    ON v.code_module = c.code_module
   AND v.code_presentation = c.code_presentation
WHERE c.code_module IS NULL

UNION ALL

SELECT
    'student_vle → vle',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'REVIEW' END
FROM open_university.oulad_bronze.student_vle_raw s
LEFT JOIN open_university.oulad_bronze.vle_raw v
    ON s.code_module = v.code_module
   AND s.code_presentation = v.code_presentation
   AND s.id_site = v.id_site
WHERE v.id_site IS NULL

UNION ALL

SELECT
    'student_vle → student_info',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'REVIEW' END
FROM open_university.oulad_bronze.student_vle_raw v
LEFT JOIN open_university.oulad_bronze.student_info_raw s
    ON v.code_module = s.code_module
   AND v.code_presentation = s.code_presentation
   AND v.id_student = s.id_student
WHERE s.id_student IS NULL;