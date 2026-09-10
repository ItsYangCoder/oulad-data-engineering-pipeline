-- File: 01_cohort_checks.sql
-- Branch: feature/cohort-analysis
-- Purpose: Validate cohort populations, outcomes, and rates.
-- Expected population: 32,593 enrollments.
-- 0 failures = pass.


-- Check 1: Population

WITH silver_pop AS (
    SELECT COUNT(*) AS silver_count
    FROM open_university.oulad_silver.student_info_clean
),

gold_pop AS (
    SELECT COUNT(*) AS gold_count
    FROM open_university.oulad_gold.vw_student_outcomes
)

SELECT
    'population' AS check_name,
    silver_count,
    gold_count,
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
CROSS JOIN gold_pop;


-- Check 2: Enrollment retention

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
WHERE g.id_student IS NULL;


-- Check 3: Enrollment grain

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
);


-- Check 4: Outcome reconciliation

WITH cohort_check AS (
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
)

SELECT
    'outcome_reconciliation' AS check_name,
    COUNT(*) AS failure_count,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS details
FROM cohort_check
WHERE enrollment_count <> (
    distinction_count
    + pass_count
    + fail_count
    + withdrawn_count
);


-- Check 5: Outcome categories

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
   );


-- Check 6: Rate range

WITH cohort_rates AS (
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
)

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
   OR withdrawn_rate NOT BETWEEN 0 AND 100;


-- Check 7: Rounded rates

-- Tolerance: ±0.02 percentage points.

WITH cohort_rates AS (
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
)

SELECT
    'rate_reconciliation' AS check_name,
    COUNT(*) AS failure_count,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS details
FROM cohort_rates
WHERE ABS(
    distinction_rate
    + pass_rate
    + fail_rate
    + withdrawn_rate
    - 100.00
) > 0.02;


-- Check 8: Unknown demographics

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
WHERE s.imd_band IS NULL
  AND g.id_student IS NULL;