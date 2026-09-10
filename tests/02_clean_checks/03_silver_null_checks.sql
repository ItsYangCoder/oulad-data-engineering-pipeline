

SELECT
    COUNT(*) AS unexpected_null_count
FROM open_university.oulad_silver.assessment_clean
WHERE id_assessment IS NULL
   OR TRIM(code_module) IS NULL
   OR TRIM(code_module) = ''
   OR TRIM(code_presentation) IS NULL
   OR TRIM(code_presentation) = ''
   OR TRIM(assessment_type) IS NULL
   OR TRIM(assessment_type) = ''
   OR clean_load_timestamp IS NULL
   OR clean_load_date IS NULL;

SELECT
    assessment_type,
    COUNT(*) AS null_date_count
FROM open_university.oulad_silver.assessment_clean
WHERE date IS NULL
GROUP BY assessment_type
ORDER BY assessment_type;

SELECT
    COUNT(*) AS unexpected_null_count
FROM open_university.oulad_silver.student_assessment_clean
WHERE id_assessment IS NULL
   OR id_student IS NULL
   OR clean_load_timestamp IS NULL
   OR clean_load_date IS NULL;

SELECT
    a.assessment_type,
    COUNT(*) AS null_score_count
FROM open_university.oulad_silver.student_assessment_clean sa
JOIN open_university.oulad_silver.assessment_clean a
    ON sa.id_assessment = a.id_assessment
WHERE sa.score IS NULL
GROUP BY a.assessment_type
ORDER BY a.assessment_type;

SELECT
    'student_info_clean' AS table_name,
    'Expected optional NULLs' AS check_name,
    'imd_band' AS column_name,
    COUNT(*) AS actual_count,
    1111 AS expected_count,

    CASE
        WHEN COUNT(*) = 1111 THEN 'Pass'
        ELSE 'Fail'
    END AS status

FROM open_university.oulad_silver.student_info_clean
WHERE imd_band IS NULL

UNION ALL

SELECT
    'student_registration_clean',
    'Expected optional NULLs',
    'date_registration',
    COUNT(*),
    45,

    CASE
        WHEN COUNT(*) = 45 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean
WHERE date_registration IS NULL

UNION ALL

SELECT
    'student_registration_clean',
    'Expected optional NULLs',
    'date_unregistration',
    COUNT(*),
    22521,

    CASE
        WHEN COUNT(*) = 22521 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean
WHERE date_unregistration IS NULL

UNION ALL

SELECT
    'student_info_clean',
    'Required NULL check',
    'business key + audit fields',
    COUNT(*),
    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_info_clean

WHERE code_module IS NULL
   OR code_presentation IS NULL
   OR id_student IS NULL
   OR clean_load_timestamp IS NULL
   OR clean_load_date IS NULL

UNION ALL

SELECT
    'student_registration_clean',
    'Required NULL check',
    'business key + audit fields',
    COUNT(*),
    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean

WHERE code_module IS NULL
   OR code_presentation IS NULL
   OR id_student IS NULL
   OR clean_load_timestamp IS NULL
   OR clean_load_date IS NULL

UNION ALL

SELECT
    'student_registration_clean',
    'Conversion loss',
    'date_registration + date_unregistration',
    COUNT(*),
    0,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM (
    SELECT b.code_module, b.code_presentation, b.id_student
    FROM open_university.oulad_bronze.student_registration_raw AS b
    INNER JOIN open_university.oulad_silver.student_registration_clean AS s
        ON UPPER(TRIM(CAST(b.code_module AS STRING))) = s.code_module
       AND UPPER(TRIM(CAST(b.code_presentation AS STRING))) = s.code_presentation
       AND TRY_CAST(b.id_student AS BIGINT) = s.id_student
    WHERE (
        b.date_registration IS NOT NULL
        AND UPPER(TRIM(CAST(b.date_registration AS STRING))) NOT IN ('', '?', 'NA', 'N/A', 'NULL')
        AND TRY_CAST(b.date_registration AS INT) IS NOT NULL
        AND s.date_registration IS NULL
    )
    OR (
        b.date_unregistration IS NOT NULL
        AND UPPER(TRIM(CAST(b.date_unregistration AS STRING))) NOT IN ('', '?', 'NA', 'N/A', 'NULL')
        AND TRY_CAST(b.date_unregistration AS INT) IS NOT NULL
        AND s.date_unregistration IS NULL
    )
) AS registration_conversion_losses

UNION ALL

SELECT
    'student_registration_clean',
    'Expected outcome/date condition',
    'Withdrawn + NULL date_unregistration',
    COUNT(*),
    93,

    CASE
        WHEN COUNT(*) = 93 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean AS sr

INNER JOIN open_university.oulad_silver.student_info_clean AS si
    ON  sr.code_module = si.code_module
    AND sr.code_presentation = si.code_presentation
    AND sr.id_student = si.id_student

WHERE si.final_result = 'Withdrawn'
  AND sr.date_unregistration IS NULL

UNION ALL

SELECT
    'student_registration_clean',
    'Expected outcome/date condition',
    'Fail + non-NULL date_unregistration',
    COUNT(*),
    9,

    CASE
        WHEN COUNT(*) = 9 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean AS sr

INNER JOIN open_university.oulad_silver.student_info_clean AS si
    ON  sr.code_module = si.code_module
    AND sr.code_presentation = si.code_presentation
    AND sr.id_student = si.id_student

WHERE si.final_result = 'Fail'
  AND sr.date_unregistration IS NOT NULL;

SELECT
  COUNT(*) AS resources_with_both_weeks_missing,
  CASE WHEN COUNT(*) = 5243 THEN 'PASS' ELSE 'REVIEW' END AS status
FROM open_university.oulad_silver.vle_clean
WHERE week_from IS NULL AND week_to IS NULL;

SELECT 'vle_clean_required_nulls' AS check_name, COUNT(*) AS invalid_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM open_university.oulad_silver.vle_clean
WHERE code_module IS NULL OR code_presentation IS NULL OR id_site IS NULL
   OR clean_load_timestamp IS NULL OR clean_load_date IS NULL;

SELECT 'student_vle_clean_required_nulls' AS check_name, COUNT(*) AS invalid_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM open_university.oulad_silver.student_vle_clean
WHERE code_module IS NULL OR code_presentation IS NULL OR id_student IS NULL
   OR id_site IS NULL OR date IS NULL OR sum_click IS NULL
   OR clean_load_timestamp IS NULL OR clean_load_date IS NULL;
-- Checks required fields and documented optional NULL values in Silver.
-- Required-field failures should be zero; optional NULL counts follow the source profile.
