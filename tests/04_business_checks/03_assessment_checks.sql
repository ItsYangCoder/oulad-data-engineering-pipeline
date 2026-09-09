-- Purpose: Validate assessment performance statistics, coverage and business definitions.
-- Input: 03_assessment_performance.sql logic and Gold fact_assessments.
-- Result: Read-only validation queries. Each query returns only failures unless noted.
-- Manual Databricks checks: a displayed zero-row result is evidence for that check,
-- but an automated runner must explicitly fail on violations.
-- Business definitions checked here:
-- * result_count includes scored and missing-score records.
-- * scored_result_count uses COUNT(score), so NULL scores are excluded.
-- * missing_score_count is result_count - scored_result_count.
-- * The current source batch has exactly 173 missing TMA scores.
-- * Missing scores are not converted to zero or automatic failures.
-- * No pass threshold is documented, so no pass-rate assertion is made.
-- * Lateness is evaluated only when both assessment_date and date_submitted are known;
--   date_submitted > assessment_date means late.
-- * Banked results remain in the reported population because no exclusion rule is documented.
-- * Assessment weight is descriptive only; no weighted score is calculated.

-- 1. Overall fact population and coverage reconciliation.
WITH metrics AS (
    SELECT
        COUNT(*) AS result_count,
        COUNT(score) AS scored_result_count,
        COUNT(*) - COUNT(score) AS missing_score_count
    FROM open_university.oulad_gold.fact_assessments
)
SELECT
    'RESULT_COUNT_RECONCILIATION' AS check_name,
    result_count,
    scored_result_count,
    missing_score_count,
    scored_result_count + missing_score_count AS recomputed_result_count
FROM metrics
WHERE result_count <> scored_result_count + missing_score_count
   OR result_count <> 173912;

-- 2. Expected current-batch missing TMA scores remain visible.
WITH missing_scores AS (
    SELECT
        COUNT(*) AS missing_score_count,
        SUM(CASE WHEN assessment_type = 'TMA' THEN 1 ELSE 0 END) AS tma_missing_count,
        SUM(CASE WHEN assessment_type <> 'TMA' THEN 1 ELSE 0 END) AS non_tma_missing_count
    FROM open_university.oulad_gold.fact_assessments
    WHERE score IS NULL
)
SELECT
    'MISSING_SCORE_COVERAGE' AS check_name,
    missing_score_count,
    tma_missing_count,
    non_tma_missing_count
FROM missing_scores
WHERE missing_score_count <> 173
   OR tma_missing_count <> 173
   OR non_tma_missing_count <> 0;

-- 3. Assessment-type coverage reconciliation.
WITH by_type AS (
    SELECT
        assessment_type,
        COUNT(*) AS result_count,
        COUNT(score) AS scored_result_count,
        COUNT(*) - COUNT(score) AS missing_score_count
    FROM open_university.oulad_gold.fact_assessments
    GROUP BY assessment_type
)
SELECT
    'TYPE_COVERAGE_RECONCILIATION' AS check_name,
    assessment_type,
    result_count,
    scored_result_count,
    missing_score_count
FROM by_type
WHERE result_count <> scored_result_count + missing_score_count;

-- 4. Assessment analytics coverage must reconcile back to the Gold fact.
-- This reproduces the analytics grouping at its source and verifies that the
-- grouped totals still equal the complete fact population and its score coverage.
WITH grouped_metrics AS (
    SELECT
        code_module,
        code_presentation,
        assessment_type,
        COUNT(*) AS result_count,
        COUNT(score) AS scored_result_count,
        COUNT(*) - COUNT(score) AS missing_score_count,
        AVG(score) AS avg_score
    FROM open_university.oulad_gold.fact_assessments
    GROUP BY
        code_module,
        code_presentation,
        assessment_type
),
reconciled AS (
    SELECT
        SUM(result_count) AS grouped_result_count,
        SUM(scored_result_count) AS grouped_scored_result_count,
        SUM(missing_score_count) AS grouped_missing_score_count,
        SUM(result_count) - SUM(scored_result_count) AS recomputed_missing_score_count
    FROM grouped_metrics
),
fact_metrics AS (
    SELECT
        COUNT(*) AS fact_result_count,
        COUNT(score) AS fact_scored_result_count,
        COUNT(*) - COUNT(score) AS fact_missing_score_count,
        AVG(score) AS fact_avg_score
    FROM open_university.oulad_gold.fact_assessments
)
SELECT
    'ANALYTICS_FACT_RECONCILIATION' AS check_name,
    grouped_result_count,
    fact_result_count,
    grouped_scored_result_count,
    fact_scored_result_count,
    grouped_missing_score_count,
    fact_missing_score_count,
    fact_avg_score
FROM reconciled
CROSS JOIN fact_metrics
WHERE grouped_result_count <> fact_result_count
   OR grouped_scored_result_count <> fact_scored_result_count
   OR grouped_missing_score_count <> fact_missing_score_count
   OR recomputed_missing_score_count <> fact_missing_score_count;

-- 5. Average-score calculation must exclude NULL scores.
WITH direct_metrics AS (
    SELECT AVG(score) AS expected_avg_score
    FROM open_university.oulad_gold.fact_assessments
),
non_null_metrics AS (
    SELECT AVG(score) AS non_null_avg_score
    FROM open_university.oulad_gold.fact_assessments
    WHERE score IS NOT NULL
)
SELECT
    'AVG_SCORE_RECONCILIATION' AS check_name,
    expected_avg_score,
    non_null_avg_score
FROM direct_metrics
CROSS JOIN non_null_metrics
WHERE ABS(COALESCE(expected_avg_score, 0) - COALESCE(non_null_avg_score, 0)) > 0.0001;

-- 6. Scores must remain within the documented 0-100 range; NULL scores are allowed.
SELECT
    'SCORE_RANGE' AS check_name,
    COUNT(*) AS failure_count
FROM open_university.oulad_gold.fact_assessments
WHERE score < 0
   OR score > 100
HAVING COUNT(*) > 0;

-- 7. Lateness rule: only known deadline/submission pairs are eligible;
--    unknown dates must not be classified as late.
WITH lateness AS (
    SELECT
        COUNT(*) AS eligible_count,
        SUM(
            CASE
                WHEN date_submitted > assessment_date THEN 1
                ELSE 0
            END
        ) AS late_count
    FROM open_university.oulad_gold.fact_assessments
    WHERE date_submitted IS NOT NULL
      AND assessment_date IS NOT NULL
)
SELECT
    'LATENESS_RULE' AS check_name,
    eligible_count,
    late_count
FROM lateness
WHERE late_count > eligible_count;

-- 8. Banked results are reported, not silently excluded.
WITH banked AS (
    SELECT
        COUNT(*) AS total_count,
        SUM(CASE WHEN is_banked = 1 THEN 1 ELSE 0 END) AS banked_count
    FROM open_university.oulad_gold.fact_assessments
)
SELECT
    'BANKED_RESULT_COVERAGE' AS check_name,
    total_count,
    banked_count
FROM banked
WHERE banked_count < 0
   OR banked_count > total_count;

-- 9. Assessment weights stay within the documented 0-100 range.
SELECT
    'ASSESSMENT_WEIGHT_RANGE' AS check_name,
    COUNT(*) AS failure_count
FROM open_university.oulad_gold.fact_assessments
WHERE weight IS NULL
   OR weight < 0
   OR weight > 100
HAVING COUNT(*) > 0;
