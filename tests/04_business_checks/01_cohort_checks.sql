-- Zero rows means pass. View active_days counts recorded days, including zero-click records.
WITH silver_pop AS (
    SELECT COUNT(*) AS silver_count
    FROM open_university.oulad_silver.student_info_clean
),
gold_pop AS (
    SELECT COUNT(*) AS gold_count
    FROM open_university.oulad_gold.vw_student_outcomes
),
check_1_population AS (
    SELECT
        'population' AS check_name,
        CASE
            WHEN silver_count = 32593
             AND gold_count = 32593
             AND silver_count = gold_count
            THEN 0
            ELSE 1
        END AS failure_count,
        CASE
            WHEN silver_count = 32593
             AND gold_count = 32593
             AND silver_count = gold_count
            THEN 'PASS'
            ELSE 'FAIL'
        END AS details
    FROM silver_pop
    CROSS JOIN gold_pop
),
check_2_enrollment_retention AS (
    SELECT
        'enrollment_retention' AS check_name,
        COUNT(*) AS failure_count,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS details
    FROM open_university.oulad_silver.student_info_clean s
    LEFT JOIN open_university.oulad_gold.vw_student_outcomes g
        ON s.code_module = g.code_module
        AND s.code_presentation = g.code_presentation
        AND s.id_student = g.id_student
    WHERE g.id_student IS NULL
),
check_3_enrollment_grain AS (
    SELECT
        'enrollment_grain' AS check_name,
        COUNT(*) AS failure_count,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS details
    FROM (
        SELECT
            code_module,
            code_presentation,
            id_student
        FROM open_university.oulad_gold.vw_student_outcomes
        GROUP BY
            code_module,
            code_presentation,
            id_student
        HAVING COUNT(*) > 1
    )
),
cohort_outcomes AS (
    SELECT
        code_module,
        code_presentation,
        COUNT(*) AS enrollment_count,
        COUNT(*) FILTER (
            WHERE final_result = 'Distinction'
        ) AS distinction_count,
        COUNT(*) FILTER (
            WHERE final_result = 'Pass'
        ) AS pass_count,
        COUNT(*) FILTER (
            WHERE final_result = 'Fail'
        ) AS fail_count,
        COUNT(*) FILTER (
            WHERE final_result = 'Withdrawn'
        ) AS withdrawn_count
    FROM open_university.oulad_gold.vw_student_outcomes
    GROUP BY
        code_module,
        code_presentation
),
check_4_outcome_reconciliation AS (
    SELECT
        'outcome_reconciliation' AS check_name,
        COUNT(*) AS failure_count,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS details
    FROM cohort_outcomes
    WHERE enrollment_count <> (
        distinction_count
        + pass_count
        + fail_count
        + withdrawn_count
    )
),
check_5_outcome_categories AS (
    SELECT
        'outcome_categories' AS check_name,
        COUNT(*) AS failure_count,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS details
    FROM open_university.oulad_gold.vw_student_outcomes
    WHERE final_result IS NULL
       OR final_result NOT IN (
            'Distinction',
            'Pass',
            'Fail',
            'Withdrawn'
       )
),
cohort_rates AS (
    SELECT
        code_module,
        code_presentation,
        100.0 * COUNT(*) FILTER (
            WHERE final_result = 'Distinction'
        ) / NULLIF(COUNT(*), 0) AS distinction_rate,
        100.0 * COUNT(*) FILTER (
            WHERE final_result = 'Pass'
        ) / NULLIF(COUNT(*), 0) AS pass_rate,
        100.0 * COUNT(*) FILTER (
            WHERE final_result = 'Fail'
        ) / NULLIF(COUNT(*), 0) AS fail_rate,
        100.0 * COUNT(*) FILTER (
            WHERE final_result = 'Withdrawn'
        ) / NULLIF(COUNT(*), 0) AS withdrawn_rate
    FROM open_university.oulad_gold.vw_student_outcomes
    GROUP BY
        code_module,
        code_presentation
),
check_6_rate_range AS (
    SELECT
        'rate_range' AS check_name,
        COUNT(*) AS failure_count,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS details
    FROM cohort_rates
    WHERE distinction_rate NOT BETWEEN 0 AND 100
       OR pass_rate NOT BETWEEN 0 AND 100
       OR fail_rate NOT BETWEEN 0 AND 100
       OR withdrawn_rate NOT BETWEEN 0 AND 100
),
cohort_rounded_rates AS (
    SELECT
        code_module,
        code_presentation,
        ROUND(
            100.0 * COUNT(*) FILTER (
                WHERE final_result = 'Distinction'
            ) / NULLIF(COUNT(*), 0), 2
        ) AS distinction_rate,
        ROUND(
            100.0 * COUNT(*) FILTER (
                WHERE final_result = 'Pass'
            ) / NULLIF(COUNT(*), 0), 2
        ) AS pass_rate,
        ROUND(
            100.0 * COUNT(*) FILTER (
                WHERE final_result = 'Fail'
            ) / NULLIF(COUNT(*), 0), 2
        ) AS fail_rate,
        ROUND(
            100.0 * COUNT(*) FILTER (
                WHERE final_result = 'Withdrawn'
            ) / NULLIF(COUNT(*), 0), 2
        ) AS withdrawn_rate
    FROM open_university.oulad_gold.vw_student_outcomes
    GROUP BY
        code_module,
        code_presentation
),
check_7_rate_reconciliation AS (
    SELECT
        'rate_reconciliation' AS check_name,
        COUNT(*) AS failure_count,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS details
    FROM cohort_rounded_rates
    WHERE ABS(
        distinction_rate
        + pass_rate
        + fail_rate
        + withdrawn_rate
        - 100.00
    ) > 0.02
),
check_8_unknown_demographics AS (
    SELECT
        'unknown_demographics' AS check_name,
        COUNT(*) AS failure_count,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS details
    FROM open_university.oulad_silver.student_info_clean s
    LEFT JOIN open_university.oulad_gold.vw_student_outcomes g
        ON s.code_module = g.code_module
        AND s.code_presentation = g.code_presentation
        AND s.id_student = g.id_student
    WHERE (s.imd_band IS NULL OR s.imd_band = 'Unknown')
      AND g.id_student IS NULL
),
check_9_zero_activity_retention AS (
    SELECT
        'zero_activity_retention' AS check_name,
        COUNT(*) AS failure_count,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS details
    FROM open_university.oulad_silver.student_info_clean s
    LEFT JOIN open_university.oulad_gold.vw_student_outcomes g
        ON s.code_module = g.code_module
        AND s.code_presentation = g.code_presentation
        AND s.id_student = g.id_student
    WHERE NOT EXISTS (
        SELECT 1 FROM open_university.oulad_silver.student_vle_clean v
        WHERE v.code_module = s.code_module
          AND v.code_presentation = s.code_presentation
          AND v.id_student = s.id_student
          AND v.sum_click > 0
    )
    AND (g.id_student IS NULL OR g.total_clicks IS NULL OR g.total_clicks <> 0)
)
SELECT * FROM check_1_population
UNION ALL
SELECT * FROM check_2_enrollment_retention
UNION ALL
SELECT * FROM check_3_enrollment_grain
UNION ALL
SELECT * FROM check_4_outcome_reconciliation
UNION ALL
SELECT * FROM check_5_outcome_categories
UNION ALL
SELECT * FROM check_6_rate_range
UNION ALL
SELECT * FROM check_7_rate_reconciliation
UNION ALL
SELECT * FROM check_8_unknown_demographics
UNION ALL
SELECT * FROM check_9_zero_activity_retention;
