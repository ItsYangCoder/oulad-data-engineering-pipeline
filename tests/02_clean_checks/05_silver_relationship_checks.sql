

SELECT
    COUNT(*) AS orphan_count
FROM open_university.oulad_silver.student_assessment_clean sa
LEFT JOIN open_university.oulad_silver.assessment_clean a
    ON sa.id_assessment = a.id_assessment
WHERE a.id_assessment IS NULL;

SELECT DISTINCT
    sa.id_assessment
FROM open_university.oulad_silver.student_assessment_clean sa
LEFT JOIN open_university.oulad_silver.assessment_clean a
    ON sa.id_assessment = a.id_assessment
WHERE a.id_assessment IS NULL
ORDER BY sa.id_assessment;

SELECT
    COUNT(*) AS orphan_count
FROM open_university.oulad_silver.assessment_clean a
LEFT JOIN open_university.oulad_silver.courses_clean c
    ON a.code_module = c.code_module
   AND a.code_presentation = c.code_presentation
WHERE c.code_module IS NULL
   OR c.code_presentation IS NULL;

SELECT DISTINCT
    a.code_module,
    a.code_presentation
FROM open_university.oulad_silver.assessment_clean a
LEFT JOIN open_university.oulad_silver.courses_clean c
    ON a.code_module = c.code_module
   AND a.code_presentation = c.code_presentation
WHERE c.code_module IS NULL
   OR c.code_presentation IS NULL
ORDER BY
    a.code_module,
    a.code_presentation;

SELECT
    'student_info_clean -> courses_clean' AS relationship_name,

    COUNT(*) AS orphan_count,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END AS status

FROM open_university.oulad_silver.student_info_clean AS si

LEFT JOIN open_university.oulad_silver.courses_clean AS c
    ON  si.code_module = c.code_module
    AND si.code_presentation = c.code_presentation

WHERE c.code_module IS NULL

UNION ALL

SELECT
    'student_registration_clean -> student_info_clean',

    COUNT(*),

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean AS sr

LEFT JOIN open_university.oulad_silver.student_info_clean AS si
    ON  sr.code_module = si.code_module
    AND sr.code_presentation = si.code_presentation
    AND sr.id_student = si.id_student

WHERE si.id_student IS NULL;

SELECT 'vle_to_courses' AS relationship_name, COUNT(*) AS orphan_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM open_university.oulad_silver.vle_clean v
LEFT JOIN open_university.oulad_silver.courses_clean c
  ON v.code_module = c.code_module
 AND v.code_presentation = c.code_presentation
WHERE c.code_module IS NULL;

SELECT 'student_vle_to_vle' AS relationship_name, COUNT(*) AS orphan_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM open_university.oulad_silver.student_vle_clean sv
LEFT JOIN open_university.oulad_silver.vle_clean v
  ON sv.code_module = v.code_module
 AND sv.code_presentation = v.code_presentation
 AND sv.id_site = v.id_site
WHERE v.id_site IS NULL;

SELECT 'student_vle_to_enrollment' AS relationship_name, COUNT(*) AS orphan_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM open_university.oulad_silver.student_vle_clean sv
LEFT JOIN open_university.oulad_silver.student_info_clean si
  ON sv.code_module = si.code_module
 AND sv.code_presentation = si.code_presentation
 AND sv.id_student = si.id_student
WHERE si.id_student IS NULL;
-- Checks required parent-child relationships across Silver tables.
-- Expected result: zero orphan records.
