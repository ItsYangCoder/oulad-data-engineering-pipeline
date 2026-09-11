-- File: 01_cohort_analysis.sql
-- Branch: feature/cohort-analysis
-- Purpose: Compare outcomes by module-presentation cohort.

WITH cohort_summary AS (
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
    -- Combined label for charting (avoids Group-by limitation in Databricks viz)
    CONCAT(code_module, ' ', code_presentation) AS cohort_label,

    code_module,
    code_presentation,

    enrollment_count,

    distinction_count,
    pass_count,
    fail_count,
    withdrawn_count,

    -- Check outcome totals
    (
        distinction_count
        + pass_count
        + fail_count
        + withdrawn_count
    ) AS outcome_total_count,

    -- Outcome rates
    ROUND(
        100.0 * distinction_count
        / NULLIF(enrollment_count, 0),
        2
    ) AS distinction_rate_pct,

    ROUND(
        100.0 * pass_count
        / NULLIF(enrollment_count, 0),
        2
    ) AS pass_rate_pct,

    ROUND(
        100.0 * fail_count
        / NULLIF(enrollment_count, 0),
        2
    ) AS fail_rate_pct,

    ROUND(
        100.0 * withdrawn_count
        / NULLIF(enrollment_count, 0),
        2
    ) AS withdrawn_rate_pct

FROM cohort_summary

ORDER BY
    code_module,
    code_presentation;