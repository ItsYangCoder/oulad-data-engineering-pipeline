-- Checks missing and duplicate candidate keys in every Bronze table.

WITH key_checks AS (

    SELECT
        'assessment_raw' AS table_name,
        COUNT(*) AS total_rows,
        SUM(CASE WHEN id_assessment IS NULL THEN 1 ELSE 0 END)
            AS missing_key_rows,
        COUNT(DISTINCT id_assessment)
            AS unique_key_count
    FROM open_university.oulad_bronze.assessment_raw

    UNION ALL

    SELECT
        'courses_raw',
        COUNT(*),
        SUM(
            CASE
                WHEN code_module IS NULL
                  OR code_presentation IS NULL
                THEN 1 ELSE 0
            END
        ),
        COUNT(
            DISTINCT CASE
                WHEN code_module IS NOT NULL
                 AND code_presentation IS NOT NULL
                THEN CONCAT_WS(
                    '|',
                    code_module,
                    code_presentation
                )
            END
        )
    FROM open_university.oulad_bronze.courses_raw

    UNION ALL

    SELECT
        'student_assessment_raw',
        COUNT(*),
        SUM(
            CASE
                WHEN id_assessment IS NULL
                  OR id_student IS NULL
                THEN 1 ELSE 0
            END
        ),
        COUNT(
            DISTINCT CASE
                WHEN id_assessment IS NOT NULL
                 AND id_student IS NOT NULL
                THEN CONCAT_WS(
                    '|',
                    CAST(id_assessment AS STRING),
                    CAST(id_student AS STRING)
                )
            END
        )
    FROM open_university.oulad_bronze.student_assessment_raw

    UNION ALL

    SELECT
        'student_info_raw',
        COUNT(*),
        SUM(
            CASE
                WHEN code_module IS NULL
                  OR code_presentation IS NULL
                  OR id_student IS NULL
                THEN 1 ELSE 0
            END
        ),
        COUNT(
            DISTINCT CASE
                WHEN code_module IS NOT NULL
                 AND code_presentation IS NOT NULL
                 AND id_student IS NOT NULL
                THEN CONCAT_WS(
                    '|',
                    code_module,
                    code_presentation,
                    CAST(id_student AS STRING)
                )
            END
        )
    FROM open_university.oulad_bronze.student_info_raw

    UNION ALL

    SELECT
        'student_registration_raw',
        COUNT(*),
        SUM(
            CASE
                WHEN code_module IS NULL
                  OR code_presentation IS NULL
                  OR id_student IS NULL
                THEN 1 ELSE 0
            END
        ),
        COUNT(
            DISTINCT CASE
                WHEN code_module IS NOT NULL
                 AND code_presentation IS NOT NULL
                 AND id_student IS NOT NULL
                THEN CONCAT_WS(
                    '|',
                    code_module,
                    code_presentation,
                    CAST(id_student AS STRING)
                )
            END
        )
    FROM open_university.oulad_bronze.student_registration_raw

    UNION ALL

    SELECT
        'vle_raw',
        COUNT(*),
        SUM(CASE WHEN id_site IS NULL THEN 1 ELSE 0 END),
        COUNT(DISTINCT id_site)
    FROM open_university.oulad_bronze.vle_raw

    UNION ALL

    SELECT
        'student_vle_raw',
        COUNT(*),
        SUM(
            CASE
                WHEN code_module IS NULL
                  OR code_presentation IS NULL
                  OR id_student IS NULL
                  OR id_site IS NULL
                  OR date IS NULL
                THEN 1 ELSE 0
            END
        ),
        COUNT(
            DISTINCT CASE
                WHEN code_module IS NOT NULL
                 AND code_presentation IS NOT NULL
                 AND id_student IS NOT NULL
                 AND id_site IS NOT NULL
                 AND date IS NOT NULL
                THEN CONCAT_WS(
                    '|',
                    code_module,
                    code_presentation,
                    CAST(id_student AS STRING),
                    CAST(id_site AS STRING),
                    CAST(date AS STRING)
                )
            END
        )
    FROM open_university.oulad_bronze.student_vle_raw
)

SELECT
    table_name,
    total_rows,
    missing_key_rows,
    unique_key_count,
    total_rows - missing_key_rows - unique_key_count
        AS duplicate_key_rows,
    CASE
        WHEN missing_key_rows = 0
         AND total_rows - missing_key_rows - unique_key_count = 0
        THEN 'PASS'
        ELSE 'REVIEW'
    END AS status
FROM key_checks
ORDER BY table_name;