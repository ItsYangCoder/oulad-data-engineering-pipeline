-- Suggested branch: test/bronze-checks
-- For checks tied to one transformation, use that transformation's branch instead.

-- 1. Missing assessment dates by assessment type
SELECT
    assessment_type,
    COUNT(*) AS total_assessments,
    SUM(
        CASE
            WHEN date IS NULL
              OR TRIM(CAST(date AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS missing_assessment_date
FROM open_university.oulad_bronze.assessment_raw
GROUP BY assessment_type
ORDER BY assessment_type;



-- 2. Missing scores by assessment type
SELECT
    a.assessment_type,
    COUNT(*) AS total_student_assessments,
    SUM(
        CASE
            WHEN s.score IS NULL
              OR TRIM(CAST(s.score AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS missing_score
FROM open_university.oulad_bronze.student_assessment_raw s
INNER JOIN open_university.oulad_bronze.assessment_raw a
    ON s.id_assessment = a.id_assessment
GROUP BY a.assessment_type
ORDER BY a.assessment_type;


-- 3. Registration missing values by final result
SELECT
    i.final_result,
    COUNT(*) AS total_students,

    SUM(
        CASE
            WHEN r.date_registration IS NULL
              OR TRIM(CAST(r.date_registration AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS missing_date_registration,

    SUM(
        CASE
            WHEN r.date_unregistration IS NULL
              OR TRIM(CAST(r.date_unregistration AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS missing_date_unregistration

FROM open_university.oulad_bronze.student_registration_raw r
INNER JOIN open_university.oulad_bronze.student_info_raw i
    ON r.code_module = i.code_module
   AND r.code_presentation = i.code_presentation
   AND r.id_student = i.id_student
GROUP BY i.final_result
ORDER BY i.final_result;


-- 4. Check whether week_from and week_to are missing together
SELECT
    COUNT(*) AS total_vle_rows,

    SUM(
        CASE
            WHEN TRIM(CAST(week_from AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
             AND TRIM(CAST(week_to AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS both_weeks_missing,

    SUM(
        CASE
            WHEN TRIM(CAST(week_from AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
             AND TRIM(CAST(week_to AS STRING))
                    NOT IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS only_week_from_missing,

    SUM(
        CASE
            WHEN TRIM(CAST(week_to AS STRING))
                    IN ('', '?', 'NA', 'N/A', 'NULL')
             AND TRIM(CAST(week_from AS STRING))
                    NOT IN ('', '?', 'NA', 'N/A', 'NULL')
            THEN 1 ELSE 0
        END
    ) AS only_week_to_missing

FROM open_university.oulad_bronze.vle_raw;